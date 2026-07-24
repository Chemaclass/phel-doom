.PHONY: help install d dev t test f format fc b build r repl doctor clean p play \
        docker-build docker-play docker-test docker-shell docker-clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

install: ## composer install
	composer install --no-interaction --no-ansi --no-progress

d: dev
dev: ## run CLI from sources (pass args: make dev ARGS="play")
	vendor/bin/phel run phel-doom.main $(ARGS)

p: play
play: ## start the DOOM showcase
	vendor/bin/phel run phel-doom.main play

t: test
test: ## run phel tests
	PHEL_DOOM_SILENT=1 vendor/bin/phel test

f: format
format: ## auto-format sources
	vendor/bin/phel format

fc: ## format check only (CI-style, exits non-zero on drift)
	vendor/bin/phel format --dry-run

b: build
build: ## build standalone PHP binary -> out/main.php
	vendor/bin/phel build

r: repl
repl: ## start phel REPL
	vendor/bin/phel repl

doctor: ## verify environment + module health
	vendor/bin/phel doctor

clean: ## drop build artifacts and caches
	rm -rf out .phel/cache

# ---------------------------------------------------------------------
# Docker — for hosts without PHP / Composer locally. The image
# bundles PHP 8.4 CLI + Composer + project deps; targets here are
# 1-line wrappers around `docker run --rm`. Host-PHP targets above
# stay the inner-loop default — Docker per-command adds ~1s overhead.
# Pass DOCKER_IMG=... to point at a custom tag (defaults to phel-doom).
# ---------------------------------------------------------------------

DOCKER_IMG ?= phel-doom
DOCKER_TTY := $(shell test -t 0 && echo -it || echo -i)

docker-build: ## build the phel-doom image
	docker build -t $(DOCKER_IMG) .

docker-play: ## play the game inside the container (raw TTY pass-through)
	docker run --rm $(DOCKER_TTY) $(DOCKER_IMG)

docker-test: ## run the phel test suite inside the container
	docker run --rm -e PHEL_DOOM_SILENT=1 $(DOCKER_IMG) test

docker-shell: ## drop into a bash shell inside the container
	docker run --rm $(DOCKER_TTY) --entrypoint bash $(DOCKER_IMG)

docker-clean: ## remove the local image
	docker rmi $(DOCKER_IMG) 2>/dev/null || true
