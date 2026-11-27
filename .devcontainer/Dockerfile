# syntax=docker/dockerfile:1

# A named stage lets Dependabot update the uv version.
FROM ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f AS uv

# Docker republishes the tag, so the digest pins the exact image. It is the
# multi-arch index digest, so amd64 and arm64 both work.
FROM python:3.13.17-slim-trixie@sha256:d98cc29d3266e535dd9da1099688d9cb3ca4753813571e071763d17725460962

# The nodejs.org Node build needs libatomic1. Debian's gh (2.46.0) is old but
# enough for auth, repo and pr. There are no version pins. An exact pin
# breaks the build once Debian replaces that version.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gh \
        git \
        libatomic1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /bin/

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Dependabot cannot update these. Take the hashes from
# https://nodejs.org/dist/v<version>/SHASUMS256.txt.
# Python downloads the file because the image has no curl.
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

ARG OPENCODE_VERSION=1.19.5
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force

# LiteLLM is a uv tool, so it stays out of the project lock. It holds every API
# key, so review each bump. --exclude-newer pins its dependencies to the
# release date, so bump LITELLM_VERSION and LITELLM_EXCLUDE_NEWER together.
# The developer user cannot write .pyc files here, so they are compiled at
# install time.
ARG LITELLM_VERSION=1.108.4
ARG LITELLM_EXCLUDE_NEWER=2026-11-10T00:00:00Z
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --no-cache --compile-bytecode \
    --exclude-newer "${LITELLM_EXCLUDE_NEWER}" \
    "litellm[proxy]==${LITELLM_VERSION}"

# Hard links fail across the volume boundary, so uv copies. The PATH lets a
# plain shell find pytest, ruff and mypy.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    VIRTUAL_ENV=/app/.venv \
    PATH=/app/.venv/bin:$PATH

# A login shell resets PATH from /etc/profile. ${PATH} must expand at login.
# hadolint ignore=SC2016
RUN printf 'export VIRTUAL_ENV=/app/.venv\nexport PATH="/app/.venv/bin:${PATH}"\n' \
    >/etc/profile.d/10-venv.sh

# On a Linux host whose uid is not 1000, set these to match, or /app is
# read-only in the container. compose.yaml relies on the name developer.
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} developer \
    && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash developer

WORKDIR /app

COPY --chown=root:root --chmod=755 .devcontainer/entrypoint.sh /entrypoint.sh

# Docker would create these volume mount points as root.
RUN mkdir -p /app/.venv \
    "/home/developer/.cache/uv" \
    "/home/developer/.cache/pre-commit" \
    "/home/developer/.config/gh" \
    && chown -R developer:developer \
        /app \
        "/home/developer/.cache" \
        "/home/developer/.config"

# compose.yaml and devcontainer.json use the name, not the uid.
# hadolint ignore=DL3066
USER developer

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
