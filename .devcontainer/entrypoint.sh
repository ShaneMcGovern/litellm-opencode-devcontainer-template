#!/bin/bash
set -euo pipefail

cd /app

# The bind-mounted repo is owned by the host user, not by `developer`. The grep
# check matters because --add appends a duplicate on every start. .git needs
# its own entry because git checks that exact path when a tool clones this repo
# from inside the container, as `copier update` does.
for d in /app /app/.git; do
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "${d}"; then
    git config --global --add safe.directory "${d}"
  fi
done

if [ -n "${GIT_AUTHOR_NAME:-}" ] && [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
  git config --global user.name "${GIT_AUTHOR_NAME}"
  git config --global user.email "${GIT_AUTHOR_EMAIL}"
else
  echo "GIT_AUTHOR_NAME and GIT_AUTHOR_EMAIL not set; skipping git identity config"
  echo "Set them in .devcontainer/.env, or run git config --global user.name/user.email"
fi

# Start the proxy early, before the slow uv sync and hook install, so it is up
# by the time anyone runs opencode. It needs only the uv tool, not the venv.
# It listens on localhost only, and the master key makes every request need
# auth. The key is made once per container and saved to a private file.
# opencode.json reads the same file, so nobody has to set it. The proxy runs in
# the background, and a crash does not stop the container. If it dies, the log
# says why.
if [ -f .devcontainer/litellm.yaml ]; then
  key_file="${HOME}/.config/litellm/master_key"
  if [ ! -s "${key_file}" ]; then
    mkdir -p "$(dirname "${key_file}")"
    (umask 077 && python3 -c 'import secrets; print("sk-" + secrets.token_hex(32))' > "${key_file}")
  fi
  # The two LITELLM_LOCAL_* switches make LiteLLM use the model map and the
  # Anthropic beta-header table that ship with the pinned release. Without
  # them, it fetches both from the main branch on GitHub at startup.
  LITELLM_MASTER_KEY="$(cat "${key_file}")" \
    LITELLM_LOCAL_MODEL_COST_MAP=true \
    LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=true \
    litellm --config .devcontainer/litellm.yaml --host 127.0.0.1 --port 4000 \
    > /tmp/litellm.log 2>&1 &
  echo "LiteLLM proxy starting on 127.0.0.1:4000 (log: /tmp/litellm.log)"
else
  echo "No .devcontainer/litellm.yaml; skipping LiteLLM proxy"
fi

if [ -f pyproject.toml ]; then
  # A Windows bind mount can present uv.lock as read-only, so sync it with
  # --frozen when it isn't writable. Keep the `! -f` arm. `[ -w uv.lock ]` is
  # also false when the file is absent, so a fresh clone would take the
  # --frozen path and fail on a missing lockfile.
  if [ ! -f uv.lock ] || [ -w uv.lock ]; then
    sync_cmd=(uv sync --all-groups)
  else
    echo "uv.lock is read-only; syncing with --frozen (the lock will not be updated)"
    sync_cmd=(uv sync --frozen --all-groups)
  fi

  # Don't make this fatal. Under `set -e`, a brief failure here, such as a
  # network error, would stop the container and leave no way to shell in and
  # find the cause.
  if ! "${sync_cmd[@]}"; then
    echo "WARNING: uv sync failed. The container is still running so you can"
    echo "         attach and re-run 'uv sync --all-groups' once the cause is fixed."
  fi
else
  echo "pyproject.toml not found; skipping uv sync"
fi

# Here rather than in a devcontainer postCreateCommand, so `docker compose up`
# alone produces a complete environment.
if [ -d .git ] && [ -f .pre-commit-config.yaml ]; then
  if ! uv run --frozen pre-commit install --install-hooks; then
    echo "WARNING: pre-commit install failed; git hooks are not active."
    echo "         Re-run 'uv run pre-commit install --install-hooks' once fixed."
  fi
else
  echo "No .git or no .pre-commit-config.yaml; skipping pre-commit install"
fi

exec sleep infinity
