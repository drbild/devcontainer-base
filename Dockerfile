# devcontainer-base
#
# A small, opinionated devcontainer base image. It starts from Microsoft's
# devcontainer base (Ubuntu) — which already ships git, zsh (+ oh-my-zsh), a
# non-root `vscode` user, sudo, and the usual build/CLI tooling — and adds:
#
#   * gh          GitHub CLI (official apt repo)
#   * claude      Claude Code (native installer, no Node required)
#   * mise        polyglot tool manager, configured in SHIMS mode
#
# Per-project tools (node, go, python, bun, ...) are NOT baked in here: projects
# pin and install them with mise. Because mise runs in shims mode, the shims
# directory is on PATH for interactive AND non-interactive shells, so a project's
# pinned tools resolve correctly even from Makefiles, hooks, and CI steps.

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Provided by the base image; re-declared so we can reference it below.
ARG USERNAME=vscode

# --- gh (GitHub CLI) -------------------------------------------------------
# git, zsh, curl, sudo, etc. are already present in the base image.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
         -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
         > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- mise ------------------------------------------------------------------
# Install the binary system-wide so it is on PATH for every user and every
# (even non-interactive) shell.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && chmod 0755 /usr/local/bin/mise

# Shims mode (not shell activation): put the per-user shims directory on PATH.
# Setting it here makes pinned tools resolve in interactive shells, login
# shells, and non-interactive contexts (Makefiles, git hooks, CI) alike. The
# directory is created/populated lazily by `mise install`; an empty/absent dir
# on PATH is harmless. /home/${USERNAME}/.local/bin is where the Claude Code
# native installer drops the `claude` binary.
ENV PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}

# Convenience wrapper: run `mise install` in every project under the CWD.
# Handy from a consumer's postCreateCommand when a whole monorepo is mounted in.
COPY --chmod=0755 scripts/mise-install-all /usr/local/bin/mise-install-all

# Quality-of-life: orientation flag + sane shell/editor defaults.
ENV DEVCONTAINER=true \
    SHELL=/bin/zsh

# --- Claude Code -----------------------------------------------------------
# Native installer (no Node). Run as the non-root user so the binary lands in
# /home/${USERNAME}/.local/bin (already added to PATH above). Installs the
# latest release; the weekly scheduled rebuild keeps it current.
USER ${USERNAME}
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
