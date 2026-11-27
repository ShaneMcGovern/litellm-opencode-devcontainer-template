# OpenCode Dev Container

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python 3.13.17](https://img.shields.io/badge/python-3.13.17-blue.svg)](https://www.python.org/downloads/)
[![Validate](https://github.com/ShaneMcGovern/litellm-opencode-devcontainer-template/actions/workflows/validate.yml/badge.svg)](https://github.com/ShaneMcGovern/litellm-opencode-devcontainer-template/actions/workflows/validate.yml)
[![Coverage](badges/coverage.svg)](badges/coverage.svg)
[![uv](https://img.shields.io/badge/uv-package%20manager-green.svg)](https://github.com/astral-sh/uv)
[![Ruff](https://img.shields.io/badge/ruff-linted-261230.svg)](https://github.com/astral-sh/ruff)

A dev container that runs [OpenCode](https://opencode.ai), a coding agent for
the terminal, with your own API keys. OpenCode talks only to a
[LiteLLM](https://docs.litellm.ai) proxy inside the container. The proxy
sends each request on to Anthropic or DeepSeek, and moves to the next model
in line if one fails. Around that sits a Python project setup: a locked `uv`
environment, tests, lint and type checks, and one set of checks that runs the
same way on your machine and in CI.

Generated from the
[uv-devcontainer](https://github.com/ShaneMcGovern/copier-uv-devcontainer)
Copier template, which supplies the container, the checks and the release
setup.

## Features

- **OpenCode, ready to run** - installed in the image at a pinned version,
  with its config in `opencode.json` at the repo root
- **Your own keys, one local proxy** - OpenCode reaches models only through
  LiteLLM on `127.0.0.1:4000`, and each key goes only to its own vendor
- **Nothing to set for the proxy** - its master key is written to a file once
  per container, and OpenCode reads that file
- **No hosted extras** - only the `litellm` provider is enabled, and session
  sharing is turned off
- **Pinned and repeatable** - base images pinned by digest, GitHub Actions
  pinned to commit SHAs, and LiteLLM pinned to one version, with its
  dependencies held to that release date
- **One quality gate** - the same pre-commit hooks run on your machine and in
  CI, and a release only happens after the checks and tests pass

## Installation

**Prerequisites**: [Docker](https://docs.docker.com/get-docker/),
[VS Code](https://code.visualstudio.com/), and the
[Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers),
or the [devcontainer CLI](https://github.com/devcontainers/cli)
(`npm i -g @devcontainers/cli`) instead of VS Code. You need no Python and no
uv on the host.

First, set up `.devcontainer/.env`. It holds your git identity and your API
keys. The file is gitignored, so it stays on your machine.
`.devcontainer/.env.example` is the committed copy, with placeholders:

```bash
cp .devcontainer/.env.example .devcontainer/.env
```

Then fill in your identity:

```bash
GIT_AUTHOR_NAME="Your Name"
GIT_AUTHOR_EMAIL="you@example.com"
```

These must not be empty. Git reads them directly, and they outrank
`user.name`, so a blank value fails every commit with
`fatal: empty ident name`.

Then add a key for each provider you use, and leave the rest commented out.
You need at least one:

```bash
ANTHROPIC_API_KEY=sk-ant-...
DEEPSEEK_API_KEY=sk-...
```

Set both keys if you can. `deepseek-v4-pro` is the default model, and a
request that fails there goes to `claude-opus` next. Without the Anthropic
key, that second try fails too.

If another tool already stores your DeepSeek key as `ANTHROPIC_AUTH_TOKEN`,
copy the value to `DEEPSEEK_API_KEY`. Do not add the names
`ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_BASE_URL` to this setup. LiteLLM reads
both for its Anthropic models, so Claude requests would go to the wrong
vendor.

A key with the same name exported in your host shell overrides the one in
`.env`.

### Option 1: VS Code Dev Container (Recommended)

Open the folder in VS Code, then click **"Reopen in Container"**, or open the
Command Palette (`Cmd/Ctrl+Shift+P`) and run
**"Dev Containers: Reopen in Container"**.

Each time the container starts, it starts the LiteLLM proxy, syncs the
environment (`uv sync`) and installs the pre-commit hooks. You don't need to
run any of these yourself.

### Option 2: Docker Compose

```bash
# Build and start the container
docker compose -f .devcontainer/compose.yaml up -d --build

# Open a shell inside it
docker compose -f .devcontainer/compose.yaml exec app bash

# Stop the container
docker compose -f .devcontainer/compose.yaml down
```

`entrypoint.sh` does the same work on every start. `devcontainer.json` is a
thin wrapper over this same compose file. It adds editor settings and stops VS
Code from forwarding the proxy port. It does no setup of its own, so the two
ways in can't drift apart.

**A change to `.env` needs a new container, not a restart.** A restart keeps
the old values. Recreate it with
`docker compose -f .devcontainer/compose.yaml up -d --force-recreate`, or
`devcontainer up --workspace-folder . --remove-existing-container`.

Either way, **commit from inside the container**. The git hooks call `uv run`,
so they need the container's tools. A VS Code terminal is already a shell
inside the container.

## Quick start

Once the container is running, start OpenCode from a shell inside it:

```bash
opencode
```

From the host, with the devcontainer CLI:

```bash
devcontainer exec --workspace-folder . opencode
```

Inside OpenCode, `/models` switches between `deepseek-v4-pro`, `claude-opus`,
`claude-sonnet` and `deepseek-flash`. The default is `deepseek-v4-pro`. If you
have no DeepSeek key, switch models first, or change `"model"` in
`opencode.json`. See [Known limitations](#known-limitations) for why.

The Python side works as in any project from the template:

```bash
# Run the tests, with coverage
uv run pytest

# Run the application
uv run python -m main
# Output: Hello from litellm-opencode-devcontainer-template.

# Run every hook, the same ones CI runs
uv run pre-commit run --all-files
```

`python -m main` works inside the container because `compose.yaml` sets
`PYTHONPATH=/app/src`. Outside it, pass the path yourself:
`PYTHONPATH=src uv run python -m main`. This project isn't a package.
Outside the container, only pytest puts `src/` on `sys.path`, through its
`pythonpath` setting.

## How OpenCode reaches the models

```text
opencode  ->  LiteLLM on 127.0.0.1:4000  ->  Anthropic or DeepSeek
```

- `opencode.json` defines one provider, `litellm`, that points at the proxy.
  `enabled_providers` turns every other provider off, so no request goes
  straight to a vendor or to OpenCode's own hosted models.
  `"share": "disabled"` stops `/share` from uploading a session.
- `.devcontainer/litellm.yaml` maps each model name to a vendor model and its
  key, and sets the order to try when a model fails.
- `entrypoint.sh` starts the proxy on every container start. The proxy is bound
  to `127.0.0.1`, so nothing outside the container can reach it. Its master key
  lives in `~/.config/litellm/master_key`, which `opencode.json` reads.

To check the setup from a shell inside the container:

```bash
# Lists only litellm/... models when the config is loaded
opencode models

# Shows the settings OpenCode actually uses
opencode debug config

# The proxy's log, which shows each request OpenCode sends
cat /tmp/litellm.log
```

### When something goes wrong

- **OpenCode reports a connection error.** The proxy takes a few seconds to
  start. Wait for `Uvicorn running` in `/tmp/litellm.log`. If the log shows
  that the proxy exited, restart the container
  (`docker compose -f .devcontainer/compose.yaml restart`), which runs the
  entrypoint again.
- **`AuthenticationError: Missing Anthropic API Key`** (or the same for
  another vendor). Every model in the fallback list is missing its key. Check
  the log for the first error. Then add the key to `.env` and recreate the
  container, as above.
- **`No deployments available for selected model`.** After a failure, LiteLLM
  stops sending requests to that model for a short time. Find the first error
  in the log and fix it, then try again.

### Adding a model or a provider

Make three edits:

1. Add an entry to `.devcontainer/litellm.yaml`, and a `fallbacks` entry if
   you want it in the failover order. Keep `claude` in the name of a Claude
   model. OpenCode turns on Anthropic prompt caching only for model names that
   contain `claude` or `anthropic`. Without it, every request pays full price
   for the whole conversation.
2. Add the same `model_name` under `provider.litellm.models` in
   `opencode.json`, with its `limit` (context and output tokens, from
   [LiteLLM's model map](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json)).
   Without the limit, OpenCode never compacts a long session.
3. Put its key in `.devcontainer/.env`. A provider that is new to the
   container also needs its variable name in `compose.yaml` under
   `environment`, and a commented line in `.env.example`.

Then recreate the container.

### Known limitations

- **Any process in the container can read your keys.** That includes
  OpenCode's shell tool and anything it installs. Each key is sent only to its
  own vendor, but be careful what you let the agent run.
- **A missing key may not show an error.** When a model's key is missing,
  LiteLLM moves to the next model in the fallback list. If that model has a
  key, OpenCode still shows the model you picked, so the answer may come from
  another vendor. Pick a model whose key you have.
- **Nothing restarts the proxy if it stops.** Restart the container to bring
  it back.

## CI and releases

Three workflows, all in `.github/workflows/`.

**`validate.yml`** runs on every push and on PRs to `main`:

1. `pre-commit` - every hook, across all files, then a secret scan of every
   commit in the history.
2. `test` - pytest, uploading `coverage.xml` as an artifact.
3. `release` - on pushes to `main` only, once `test` has passed, runs
   `release.yml`.
4. `badge` - on `main` only, regenerates `badges/coverage.svg` from that
   artifact and commits it if it changed.

**`commit-messages.yml`** runs on PRs to `main`, and again when a PR's title
is edited. It checks every commit message on the branch, and the title, with
the same hook that checks your commits. A squash merge puts all of them into
the commit on `main`, and the release reads that commit.

**`release.yml`** has no trigger of its own. `validate.yml` calls it, so a
commit that fails the hooks or the tests is never released. It hands off to
python-semantic-release, which reads its settings from `pyproject.toml`. The
commit message type decides whether a release happens.
[CONTRIBUTING.md](CONTRIBUTING.md) lists the types and which ones release.

On a release, python-semantic-release bumps the version in `pyproject.toml`,
the only place the version is set. It adds the new entry to `CHANGELOG.md`
below its `<!-- version list -->` marker and re-locks `uv.lock` so the lock
records the new version. Then it tags and publishes a GitHub Release.

Nothing installs this repo, so nothing is built or published to a package
index. `build_command` runs `uv lock` instead, and `assets` puts the new lock
in the release commit. Without that, a release would leave the lock behind and
fail the `uv-lock` hook on the next push.

The `badge` job runs after `release` and shares its `concurrency` group, so
the two can't race each other pushing to `main`.

## Updating from the template

This project was generated from a Copier template, and `.copier-answers.yml`
records which version and which answers. To pull in later template changes:

```bash
# Re-ask each question, prior answer as the default
uvx copier update --trust

# Reuse every prior answer, no prompts
uvx copier update --trust --defaults
```

**Commit your work first**: Copier refuses to update a dirty tree. It then
applies the template again and merges the result with your changes, asking
where they conflict.

`update` moves to the template's newest **tag**, so it can't see a template
change that has no tag yet. And `uvx` fetches whatever Copier version is
current, so pin it (`uvx copier@9.17.2`) when the update must be repeatable.

Some template releases make changes that `update` can't merge on its own. You
then fix up the result by hand. The template's
[UPGRADING.md](https://github.com/ShaneMcGovern/copier-uv-devcontainer/blob/main/docs/UPGRADING.md)
records what changed and the order to step through. Read it before you update
across several versions at once.

## Layout

```text
.devcontainer/       Dockerfile, compose, entrypoint, litellm.yaml, VS Code wiring
.github/workflows/   validate.yml (checks, tests, release, badge),
                     commit-messages.yml, release.yml
.gitleaks.toml       the secret scanner's extra rule, for DeepSeek keys
badges/              coverage.svg, regenerated by CI on main
opencode.json        OpenCode's config: the litellm provider and its models
src/main.py          the application entry point
tests/               the test suite
```

## Documentation

- **[OpenCode Documentation](https://opencode.ai/docs/)** - the agent, its
  commands and its config file
- **[LiteLLM Proxy Documentation](https://docs.litellm.ai/docs/proxy/configs)** -
  the proxy config that `litellm.yaml` follows
- **[uv Documentation](https://docs.astral.sh/uv/)** - package manager and
  lockfile reference
- **[Ruff Documentation](https://docs.astral.sh/ruff/)** - linter and
  formatter rules
- **[mypy Documentation](https://mypy.readthedocs.io/)** - type checker
  settings
- **[pytest Documentation](https://docs.pytest.org/)** - testing framework
  guide
- **[VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)** -
  container development guide
- **[uv-devcontainer](https://github.com/ShaneMcGovern/copier-uv-devcontainer)** -
  the template this project came from

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the change workflow: the quality
gate, commit message rules, dependencies, the OpenCode and LiteLLM setup,
tests, and types.

## License

MIT License - see the [LICENSE](LICENSE) file for details.

Copyright 2026 Shane McGovern
