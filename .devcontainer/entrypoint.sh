#!/bin/bash
set -euo pipefail

cd /app

# The bind mount is owned by the host user. The grep check stops --add from
# adding a duplicate on every start. `copier update` needs the .git entry.
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

# Start the proxy before the slow sync, so it is up by the time you run
# opencode. opencode.json reads this key file too.
if [ -f .devcontainer/litellm.yaml ]; then
  key_file="${HOME}/.config/litellm/master_key"
  if [ ! -s "${key_file}" ]; then
    mkdir -p "$(dirname "${key_file}")"
    (umask 077 && python3 -c 'import secrets; print("sk-" + secrets.token_hex(32))' > "${key_file}")
  fi
  # Use the data bundled with this release, not files fetched from GitHub.
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
  # A Windows bind mount can make uv.lock read-only. Keep the `! -f` test,
  # because `-w` is also false for a missing file.
  if [ ! -f uv.lock ] || [ -w uv.lock ]; then
    sync_cmd=(uv sync --all-groups)
  else
    echo "uv.lock is read-only; syncing with --frozen (the lock will not be updated)"
    sync_cmd=(uv sync --frozen --all-groups)
  fi

  # Keep this non-fatal, so you can still shell in and fix it.
  if ! "${sync_cmd[@]}"; then
    echo "WARNING: uv sync failed. The container is still running so you can"
    echo "         attach and re-run 'uv sync --all-groups' once the cause is fixed."
  fi
else
  echo "pyproject.toml not found; skipping uv sync"
fi

# Do this here, not in postCreateCommand, so plain `docker compose up` works
# too.
if [ -d .git ] && [ -f .pre-commit-config.yaml ]; then
  if ! uv run --frozen pre-commit install --install-hooks; then
    echo "WARNING: pre-commit install failed; git hooks are not active."
    echo "         Re-run 'uv run pre-commit install --install-hooks' once fixed."
  fi
else
  echo "No .git or no .pre-commit-config.yaml; skipping pre-commit install"
fi

exec sleep infinity
