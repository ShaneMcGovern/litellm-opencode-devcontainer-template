# syntax=docker/dockerfile:1

# A named build stage keeps the uv version in a literal FROM tag. Dependabot's
# docker ecosystem tracks those, but not an inline `COPY --from=...:X`.
FROM ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f AS uv

# The tag alone moves: Docker re-publishes it for each Debian point release and
# security rebuild. The digest fixes the exact image. It is the multi-arch
# index digest, so both amd64 and arm64 work. Dependabot proposes tag and
# digest together.
FROM python:3.13.17-slim-trixie@sha256:d98cc29d3266e535dd9da1099688d9cb3ca4753813571e071763d17725460962

# The base already ships a trust store, and the Node tarball below is fetched
# through Python rather than curl, so neither ca-certificates nor curl is
# installed here.
#
# gh: trixie freezes it at 2.46.0, which is enough for auth, repo and pr.
#   Dependabot does not track apt packages, so gh stays on 2.46.0 unless
#   Debian ships a fix for it. That is fine for now. A newer gh would need
#   GitHub's own apt repository, with its keyring and source list.
# libatomic1: the nodejs.org Node binaries need it, and the slim base leaves it
#   out. That Node also serves pre-commit's prettier and markdownlint hooks.
#
# The packages have no version pins. The base image digest already fixes the
# Debian release, and an exact apt version breaks the build as soon as Debian
# replaces it with a security fix.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gh \
        git \
        libatomic1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /bin/

# With pipefail, a failure on the left of a pipe fails the whole RUN, not just
# whatever the last command returns.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Node comes from the nodejs.org tarball, checksum-pinned per architecture, so
# no extra apt repository is needed. Dependabot cannot see ARG pins, so bump
# these by hand, taking the hashes from
# https://nodejs.org/dist/v<version>/SHASUMS256.txt.
ARG NODE_VERSION=26.13.1
ARG NODE_SHA256_AMD64=518674de2b621728a5e4486f5fb3b7d2900bb3cc4aa97969edaa463db99f9778
ARG NODE_SHA256_ARM64=80a330b35415382878df18d41afbd106ea89bfb3be0087d6608e289a14c5cc7d
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
        amd64) arch=x64; sha="${NODE_SHA256_AMD64}" ;; \
        arm64) arch=arm64; sha="${NODE_SHA256_ARM64}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && tarball="node-v${NODE_VERSION}-linux-${arch}.tar.gz" \
    && python3 -c 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' \
        "https://nodejs.org/dist/v${NODE_VERSION}/${tarball}" "/tmp/${tarball}" \
    && echo "${sha}  /tmp/${tarball}" | sha256sum -c - \
    && tar -xzf "/tmp/${tarball}" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "/tmp/${tarball}"

# OpenCode is the coding agent. It talks only to the LiteLLM proxy, which is
# installed below and started by entrypoint.sh (see opencode.json at the repo
# root).
ARG OPENCODE_VERSION=1.19.5
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force

# LiteLLM is a uv tool rather than a project dependency, so it never enters the
# project's lock. Pin it exactly and review each bump: this process holds every
# provider key. The pin covers only litellm itself. --exclude-newer holds its
# dependencies at the date of that release, so bump LITELLM_VERSION and
# LITELLM_EXCLUDE_NEWER together. --compile-bytecode is set because
# `developer` cannot write .pyc files into this root-owned tree, and without
# them every start is slower.
ARG LITELLM_VERSION=1.108.4
ARG LITELLM_EXCLUDE_NEWER=2026-11-10T00:00:00Z
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --no-cache --compile-bytecode \
    --exclude-newer "${LITELLM_EXCLUDE_NEWER}" \
    "litellm[proxy]==${LITELLM_VERSION}"

# UV_LINK_MODE is copy because hard links fail across the bind-mount/volume
# boundary. VIRTUAL_ENV and PATH put the project environment ahead of the
# system interpreter, so a plain interactive shell finds pytest, ruff and mypy.
# VS Code points at the venv interpreter and the hooks use `uv run`, but a
# plain terminal does neither.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    VIRTUAL_ENV=/app/.venv \
    PATH=/app/.venv/bin:$PATH

# ENV alone is not enough. A login shell sources /etc/profile, which rebuilds
# PATH from scratch and drops the venv. The single quotes are on purpose:
# ${PATH} must expand when the profile runs, not now.
# hadolint ignore=SC2016
RUN printf 'export VIRTUAL_ENV=/app/.venv\nexport PATH="/app/.venv/bin:${PATH}"\n' \
    >/etc/profile.d/10-venv.sh

# The user name is fixed because compose.yaml hardcodes /home/developer for the
# cache volumes and GH_CONFIG_DIR. The IDs are build args because a bind mount
# keeps the host's IDs. On a Linux host where your uid is not 1000, the
# container can read /app but not write to it, and pytest fails when it writes
# coverage.xml. Docker Desktop maps every file to the container user, so
# Windows and macOS never need these.
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} developer \
    && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash developer

WORKDIR /app

COPY --chown=root:root --chmod=755 .devcontainer/entrypoint.sh /entrypoint.sh

# Every path compose.yaml mounts a named volume onto must exist and belong to
# the non-root user. Docker creates a missing mount target as root, which
# breaks `gh auth login`, `uv sync` and pre-commit hook installation.
RUN mkdir -p /app/.venv \
    "/home/developer/.cache/uv" \
    "/home/developer/.cache/pre-commit" \
    "/home/developer/.config/gh" \
    && chown -R developer:developer \
        /app \
        "/home/developer/.cache" \
        "/home/developer/.config"

# hadolint wants a numeric user, for tools that check it without reading
# /etc/passwd. Docker looks up the name in /etc/passwd here, and the paths in
# compose.yaml depend on that name.
# hadolint ignore=DL3066
USER developer

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
