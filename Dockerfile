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

# --- systemd + Docker --------------------------------------------------------
# The image is booted as a microVM guest with systemd handed PID 1 (msb
# `run --init auto`), so Docker starts via the stock distro units — no custom
# launcher scripts.
#
#   * systemd, systemd-sysv  real init; systemd-sysv provides the /sbin/init
#                            symlink that `--init auto` probes first. dbus is
#                            pulled in explicitly for systemctl/journald use
#                            by non-root users under systemd boot.
#   * docker.io              dockerd + containerd + docker CLI from Ubuntu apt
#   * docker-compose-v2      compose CLI plugin (Ubuntu universe), lands
#                            system-wide in /usr/libexec/docker/cli-plugins —
#                            not ~/.docker/cli-plugins, which sits in a guest
#                            upper layer wiped on sandbox recreate
#   * fuse-overlayfs         the guest rootfs is itself an overlayfs upper
#                            layer and the kernel forbids nesting overlayfs
#                            upperdirs, so Docker's native overlay driver can
#                            never work there; dockerd is pointed at
#                            fuse-overlayfs via /etc/docker/daemon.json below
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         systemd systemd-sysv dbus \
         docker.io docker-compose-v2 fuse-overlayfs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# See fuse-overlayfs note above: native overlay2 cannot sit on the microVM's
# writable upper layer.
RUN mkdir -p /etc/docker \
    && printf '{\n  "storage-driver": "fuse-overlayfs"\n}\n' > /etc/docker/daemon.json

# Socket activation only: enable docker.socket, not docker.service, so dockerd
# (and containerd, pulled in via docker.service unit deps) stays cold until the
# first `docker` command touches /var/run/docker.sock — sandboxes that never
# use Docker pay zero daemon RAM. systemd isn't running at build time (and
# /usr/local/bin/systemctl is the devcontainers shim), so enable via symlink
# and drop the eager-start symlinks the package postinst may have created.
RUN mkdir -p /etc/systemd/system/sockets.target.wants \
    && ln -sf /lib/systemd/system/docker.socket \
         /etc/systemd/system/sockets.target.wants/docker.socket \
    && rm -f /etc/systemd/system/multi-user.target.wants/docker.service \
         /etc/systemd/system/multi-user.target.wants/containerd.service

# The stock docker.socket is root:docker 0660; group membership is the whole
# permission story for the non-root user.
RUN usermod -aG docker ${USERNAME}

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
# Pre-create mise's XDG directories owned by the non-root user. mise creates
# these lazily (each only when first written to), so a host that bind-mounts
# into a not-yet-created subdir — e.g. microsandbox mounting host volumes —
# would otherwise create the parent as root. Creating them up front (as the
# user, so intermediate parents are user-owned too) guarantees ${USERNAME}
# ownership regardless of mount order.
RUN mkdir -p \
      /home/${USERNAME}/.config/mise \
      /home/${USERNAME}/.cache/mise \
      /home/${USERNAME}/.local/state/mise \
      /home/${USERNAME}/.local/share/mise
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
