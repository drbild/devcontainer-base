# devcontainer-base

A small, opinionated [dev container](https://containers.dev) base image, published
to GitHub Container Registry.

```
ghcr.io/drbild/devcontainer-base:latest
```

It starts from [Microsoft's devcontainer base image][ms-base]
(`mcr.microsoft.com/devcontainers/base:ubuntu`) and adds the handful of tools I
want in every project:

| Tool | Source | Notes |
|------|--------|-------|
| **git** | base image | |
| **zsh** | base image | with oh-my-zsh, default shell |
| **gh** | official apt repo | GitHub CLI |
| **claude** | native installer | [Claude Code], no Node.js required |
| **mise** | [mise.run] | tool manager, **shims mode** |

Per-project tools (node, go, python, bun, …) are intentionally **not** baked in.
Projects pin them in a `mise.toml` / `.tool-versions` and install them with
`mise install`.

## Why this base?

The Microsoft devcontainer base already provides git, zsh + oh-my-zsh, a non-root
`vscode` user, `sudo`, and common build/CLI tooling. Starting there (rather than a
plain `node` image) means less to maintain and no Node.js runtime we don't need —
Claude Code is installed via its native installer, and project toolchains come from
mise.

## mise: shims mode

mise is configured in **shims mode**, not shell activation. The per-user shims
directory (`~/.local/share/mise/shims`) is placed on `PATH` in the image, so a
project's pinned tools resolve correctly in **every** context — interactive
shells, login shells, and non-interactive ones (Makefiles, git hooks, CI steps) —
without relying on a shell hook.

In a project:

```sh
mise install      # materialize the tools pinned in mise.toml / .tool-versions
node --version    # resolves via the mise shim to the pinned version
```

## Usage

Reference the image directly from a project's `.devcontainer/devcontainer.json`:

```jsonc
{
  "name": "my-project",
  "image": "ghcr.io/drbild/devcontainer-base:latest",
  "remoteUser": "vscode",
  "postCreateCommand": "mise install"
}
```

A copy-pasteable starter lives in [`examples/devcontainer.json`](examples/devcontainer.json).

Pin to a timestamped tag (e.g. `ghcr.io/drbild/devcontainer-base:2026-06-23-060500`)
instead of `latest` for reproducible builds.

## Publishing

`.github/workflows/build-image.yml` builds and pushes to `ghcr.io` on:

- every push to `main`,
- a weekly schedule (Mondays 06:00 UTC) to pick up upstream base image and tool
  updates,
- manual `workflow_dispatch`.

It builds a single-arch image first, smoke-tests that every bundled tool runs,
then pushes a multi-arch image (`linux/amd64` + `linux/arm64`) tagged `latest` and
a UTC timestamp (`YYYY-MM-DD-HHmmss`), which uniquely identifies every build.
Publishing uses the built-in `GITHUB_TOKEN`
— no extra secrets required. The first publish may create the package as private;
make it public (or grant access) in the repository's package settings if other
machines need to pull it.

[ms-base]: https://github.com/devcontainers/images/tree/main/src/base-ubuntu
[Claude Code]: https://docs.claude.com/en/docs/claude-code
[mise.run]: https://mise.jdx.dev
