# Local build/test helpers. CI (.github/workflows/build-image.yml) does the
# real multi-arch build and push; these targets mirror it for local iteration.

IMAGE ?= devcontainer-base
TAG   ?= local
REF   := $(IMAGE):$(TAG)

# Tools the image is expected to provide, smoke-tested by `make test`.
TOOLS := git zsh gh mise claude

.DEFAULT_GOAL := build

.PHONY: build test shell push-multiarch clean help

## build: Build the image locally (single-arch, host platform).
build:
	docker build -t $(REF) .

## test: Build, then verify every bundled tool runs (mirrors CI smoke test).
test: build
	@for t in $(TOOLS); do \
		echo "==> $$t --version"; \
		docker run --rm -u vscode $(REF) $$t --version || exit 1; \
	done
	@echo "All tools OK."

## shell: Open an interactive zsh in the image as the vscode user.
shell: build
	docker run --rm -it -u vscode $(REF) zsh

## push-multiarch: Build amd64+arm64 and push (set IMAGE=ghcr.io/<owner>/<repo>).
## Requires `docker buildx` and a registry login. Normally CI does this.
push-multiarch:
	docker buildx build --platform linux/amd64,linux/arm64 -t $(REF) --push .

## clean: Remove the locally built image.
clean:
	-docker image rm $(REF)

## help: List available targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
