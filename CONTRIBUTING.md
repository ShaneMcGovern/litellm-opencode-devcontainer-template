# Contributing

## Setup

[README.md](README.md) has the prerequisites, what goes in
`.devcontainer/.env` (your git identity and API keys), and both ways to start
the container. Do that first. Everything below assumes you are inside it.

### Why everything runs in the container

The container pins the Python, uv, Node, OpenCode and LiteLLM versions, so
every machine gets the same tools. Tools that run on a host Python will sooner
or later disagree with CI.

This applies to `git commit` as well. The ruff and mypy hooks call `uv run`,
so a commit from a host shell can fail on the host's Python. Commit from a
container shell. A VS Code terminal is already one.

## Making a change

```text
edit -> git commit -> hooks run -> push -> CI -> merge to main -> release
```

1. Branch from `main`:

   ```bash
   git checkout -b feature/short-description
   ```

2. Make the change, with tests.

3. Run the gate:

   ```bash
   uv run pre-commit run --all-files
   uv run pytest
   ```

4. Commit. The hooks run on their own, and the commit-msg hook rejects any
   message that is not a Conventional Commit. If a hook fails, fix what it
   reports (some hooks fix files for you), stage the changes and commit again.

5. Push and open a PR against `main`.

Everyday commands:

```bash
# Tests, with coverage
uv run pytest

# Lint, fixing what can be fixed
uv run ruff check --fix .

# Format
uv run ruff format .

# Type check
uv run mypy

# All pre-commit stage hooks, as CI runs them
uv run pre-commit run --all-files
```

`pre-commit run --all-files` covers most of CI's `pre-commit` job. It skips
`gitleaks-history` (see below). The tests are a separate CI job and pytest is
not a hook, so run `uv run pytest` as well. `uv run` syncs the environment
first, so there's no virtualenv to activate.

## Quality gate

`.pre-commit-config.yaml` defines every hook. Your local hooks and CI both use
it.

CI runs `pre-commit run --all-files`, which runs the `pre-commit` stage. CI
runs the other two stages on their own:

- **`commit-msg`** needs a message. `commit-messages.yml` feeds it each
  non-merge commit message on a PR's branch, so a commit made on the GitHub
  website is checked too. Then it checks the PR title.
- **`manual`** holds `gitleaks-history`. The `gitleaks` hook scans what a
  commit stages, and CI stages nothing. So the `pre-commit` job also runs
  `gitleaks-history`, which scans every commit in the history.

| Hook | Stage | What it does |
| --- | --- | --- |
| Hygiene hooks | pre-commit | Whitespace, EOF, merge markers, large files, private keys, LF endings |
| `check-yaml`, `check-json`, `check-toml` | pre-commit | Checks that the files parse |
| `gitleaks` | pre-commit | Rejects a commit that adds an API key or other secret |
| `gitleaks-history` | manual | The same scan over every commit, run by CI |
| `prettier` | pre-commit | Formats YAML and JSON |
| `shellcheck` | pre-commit | Lints shell scripts |
| `actionlint` | pre-commit | Checks that the workflows are valid |
| `zizmor` | pre-commit | Checks the workflows and `dependabot.yml` for security problems, such as an action not pinned to a SHA |
| `dockerfmt`, `hadolint` | pre-commit | Formats and lints the Dockerfile |
| `check-dependabot` | pre-commit | Checks `dependabot.yml` against its schema |
| `markdownlint-fix` | pre-commit | Formats and lints Markdown |
| `uv-lock` | pre-commit | Fails if `uv.lock` has drifted |
| `ruff-check`, `ruff-format` | pre-commit | Lints and formats Python |
| `mypy` | pre-commit | Type checks `src/` and `tests/` |
| `conventional-pre-commit` | commit-msg | Rejects non-Conventional commit messages |

Some of these differ from the usual setup on purpose:

- **`ruff` and `mypy` run as local hooks** (`uv run ruff`, `uv run mypy`), not
  through mirror repositories. For mypy this is required: a mirrored hook runs
  in its own environment, can't see the project's dependencies, and reports
  false import errors. For ruff it means there is one version, declared in
  `pyproject.toml` and locked in `uv.lock`, so `uv run ruff` and the CI hook
  can't enforce different rules.
- **`prettier` is not given TOML.** It can't parse TOML without a plugin.
- **`check-json` and `prettier` both skip `devcontainer.json`.** It's JSONC,
  which allows comments, and both tools fail on them.
- **`markdownlint` skips `CHANGELOG.md`.** python-semantic-release writes it
  with two blank lines between releases, which breaks rule MD012. The release
  commit carries `[skip ci]`, so the problem would land unchecked and fail the
  *next* push.
- **`gitleaks` has one rule of its own, in `.gitleaks.toml`.** A DeepSeek key
  has no prefix that names it, and the built-in rules find one only next to a
  word like `key`. The added rule finds one anywhere. Test a new rule on a
  made-up key in a scratch repository, never on a real key here.
- **zizmor gets a token in CI only.** It runs in its own CI step with the
  job's read-only token. With it, zizmor also checks that each pinned SHA
  really belongs to the action it names. On your machine it skips that check.
- **actionlint shellchecks the `run:` blocks only in CI.** It needs shellcheck
  on its PATH. The GitHub runner has it, and the dev container does not.
- **Each hadolint rule that is off is turned off in the Dockerfile**, on the
  line above the instruction it applies to, with the reason.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), enforced by the
`conventional-pre-commit` hook on your machine and by `commit-messages.yml` on
every PR. The format drives releases: python-semantic-release works out the
next version from it, and a message it can't parse produces no release, with
no warning.

```text
<type>(<optional scope>): <description>
```

| Type | Meaning | Releases? |
| --- | --- | --- |
| `feat` | New functionality | Minor |
| `fix` | Bug fix | Patch |
| `perf` | Performance improvement | **Patch** |
| `docs` | Documentation only | No |
| `refactor` | Restructuring without behavior change | No |
| `test` | Tests only | No |
| `build` | Build system, dependencies, container | No |
| `ci` | CI configuration | No |
| `chore` | Everything else | No |
| `style` | Formatting only | No |

Breaking changes take a `!` after the type (`feat!: ...`) or a
`BREAKING CHANGE:` footer, and produce a major bump.

Watch `perf`. It reads like housekeeping, but it ships a patch release,
because the conventional parser in python-semantic-release treats `fix` and
`perf` as patch types. The commit-msg hook accepts `revert`, but `revert`
produces no release.

Examples:

```text
feat: add --json output flag
fix(opencode): disable session sharing
docs: document the release pipeline
```

## Pull requests

PRs are squash-merged, so the PR title becomes the commit message on
`main`, and every commit message on the branch goes into its body. The title
and each non-merge commit message must be a valid Conventional Commit.
`commit-messages.yml` checks them all when the PR opens, on each push, and
again when you edit the title.

**Nothing makes these checks required, so a failing one warns but does not
block a merge.** A branch ruleset can make them required. Until then, look for
a red X before you merge.

`validate.yml` runs on the branch push and again on the PR. It also runs on
`main` after the merge, because a squashed commit is new to CI. That run is
the one that can release.

## Dependencies

```bash
uv add httpx                      # runtime
uv add --group dev pytest-mock    # development only
uv remove httpx
```

Always commit `uv.lock`. CI installs with `--frozen`, which uses the lock as it
is and never checks it. The `uv-lock` hook is what fails when the lock has
drifted, on your machine and in CI's `pre-commit` job.

### Updating pinned tools

No single tool updates everything, so each kind of pin has its own route:

| What | How |
| --- | --- |
| Python dependencies | Dependabot, weekly (`uv` ecosystem) |
| GitHub Actions | Dependabot, weekly (`github-actions` ecosystem). Pinned to commit SHAs with a `# vX.Y.Z` comment, and Dependabot updates both |
| Base and uv images | Dependabot, weekly (`docker` ecosystem, `/.devcontainer`). Pinned by tag and digest, and Dependabot updates both |
| pre-commit hooks | Manual: `uv run pre-commit autoupdate` |
| python-semantic-release | Manual: the version in `.github/workflows/release.yml` |
| OpenCode | Manual: `OPENCODE_VERSION` in `.devcontainer/Dockerfile` |
| LiteLLM | Manual: `LITELLM_VERSION` and `LITELLM_EXCLUDE_NEWER` in `.devcontainer/Dockerfile`, together |
| Node | Manual: `NODE_VERSION` and both checksums in `.devcontainer/Dockerfile` |

Dependabot waits seven days after a release before it proposes an update
(`cooldown` in `dependabot.yml`). A bad release is usually pulled within
days, so the wait keeps most of them out.

This repo has no Dependabot entry for the hooks, so that row is manual. Run
it now and then, and follow it with `uv run pre-commit run --all-files`,
because a new hook version often finds new problems. `autoupdate` always takes
the newest release and has no cooldown, so check the release dates. Keep a
hook on its previous release until the new one is a week old.

The other manual rows are versions that no Dependabot ecosystem can see: a
`uvx` call in a workflow, and `ARG` lines in the Dockerfile. The comments
above the Node and LiteLLM `ARG` lines say what must change with them.

Dependabot keeps the base image on Python 3.13. `dependabot.yml` ignores
minor and major Python bumps, so moving to a new minor version is a change you
make on purpose. When Dependabot proposes a patch bump, also bump
`.python-version` and the Python badge in `README.md` in the same PR, because
Dependabot touches neither.

ruff and mypy are not pinned by hand. They are locked in `uv.lock`, so
Dependabot's `uv` ecosystem updates them.

## The OpenCode and LiteLLM setup

These files must agree with each other:

| File | What it holds |
| --- | --- |
| `.devcontainer/litellm.yaml` | Model names, the vendor model behind each, its key, and the fallback order |
| `opencode.json` | The `litellm` provider, the same model names, and each model's token limits |
| `.devcontainer/compose.yaml` | The key variables passed into the container, under `environment` |
| `.devcontainer/.env.example` | A commented line for each key, for anyone who clones the repo |
| `.devcontainer/entrypoint.sh` | How the proxy starts, and its master key |

If a model name is in `opencode.json` but not in `litellm.yaml`, it still
shows up in OpenCode's `/models` list and in `opencode models`. Every request
to it then fails with `Invalid model name passed in model=...`. A key that
`litellm.yaml` reads but `compose.yaml` does not pass never reaches the
container. `tests/test_model_config.py` catches both in CI. It also
checks that the default model and every fallback name a real model, and that
each Claude model's name still contains `claude` or `anthropic`. OpenCode
needs one of them before it turns on prompt caching.

**Nothing in CI builds the container or runs OpenCode.** CI checks that these
files agree with each other, but not that they work. So a change to any of
them needs a check by hand, in a new container.

To check a change, recreate the container, then from a shell inside it:

```bash
# Look for "Uvicorn running". If it's not there yet, run this again in a few
# seconds. If the proxy stopped, the last lines say why.
tail /tmp/litellm.log

# Should list only litellm/... models, including any you added
opencode models
# Output:
# litellm/claude-opus
# litellm/claude-sonnet
# litellm/deepseek-flash
# litellm/deepseek-v4-pro

# Sends one real request through the proxy
opencode run "Reply with: pong"

# Each request OpenCode sent shows up as a POST here
grep "POST /v1/chat/completions" /tmp/litellm.log
# Output, for a request with no valid key:
# INFO:     127.0.0.1:53392 - "POST /v1/chat/completions HTTP/1.1" 401 Unauthorized
```

A `POST /v1/chat/completions` line in the log means the request went through
the proxy. Without a valid key, the request still reaches the proxy. The proxy
then tries the next model in its fallback list, and fails the request if that
model has no key either. Either way, the log line shows the routing works.

## Tests

pytest, with coverage measured against `src/`.

```bash
uv run pytest                         # everything, with coverage
uv run pytest tests/test_smoke.py -v  # one file
uv run pytest -k greeting             # by name
```

`tests/test_smoke.py` is a placeholder: one test that calls `main()` and
checks what it printed. It is there so the project starts green with coverage
already set up. Replace it once there is real code to test.
`tests/test_model_config.py` checks that the OpenCode and LiteLLM settings
agree, as described above.

Coverage has no `omit` rules. It adds one exclusion to the defaults: the
`__main__` guard, because the code under it never runs under pytest. It is
set with `exclude_also` in `[tool.coverage.report]` in `pyproject.toml`.
Before you add another, check whether the code it hides is needed at all.

### The coverage badge

`badges/coverage.svg` is committed. The `badge` job in `validate.yml`
regenerates it on `main` from the `coverage.xml` that the `test` job uploads.

That takes a job, the `genbadge` dev dependency, a committed SVG, a README
badge, a `contents: write` grant and the `main-writes` concurrency group. It
is kept on purpose: many Python repositories show one, and adding one later
means working all of this out again.

To drop it: delete the `badge` job and the coverage upload step from
`validate.yml`, run `uv remove --group dev genbadge`, and delete the `badges/`
directory. Then remove from `README.md` the badge line at the top and the
places that describe the `badge` job and `badges/`. In `release.yml`, update
the comment above `concurrency`, which mentions the `badge` job.

## Types

mypy runs in `strict` mode over `src/` and `tests/`, test functions included.
New code needs annotations:

```python
def render(rows: list[str], *, indent: int = 0) -> str: ...
```

```bash
uv run mypy
```

## Writing style

This covers the README, this file, commit messages, PR text and code
comments.

- Write plainly. Use short sentences and common words.
- Use plain ASCII. No em dashes, en dashes, curly quotes or arrow symbols.
  Use a hyphen, a colon or a new sentence instead.
- Don't write the project's release version into the docs. A release rewrites
  `pyproject.toml`, `uv.lock` and `CHANGELOG.md`, not the docs, so a version
  written anywhere else goes stale.
- When you give an instruction, also say what to do if it fails.
- Run a command before you write it down. Where the output helps, show the
  real output, not a retyped guess.

`tests/test_docs_style.py` checks the ASCII rule and the version rule on
`README.md` and this file.

## Releasing

There's nothing to do by hand. Every merge to `main` runs `release.yml` once
`validate.yml`'s tests pass on it. Only a `feat:`, `fix:` or `perf:` commit, or
a breaking change, produces a release.
[README.md](README.md) describes what the release does.

Never edit `CHANGELOG.md` by hand or bump a version yourself.
python-semantic-release owns both. It adds each release's changelog entry from
the commit messages, and a version you bump by hand gets out of step with the
tags.
