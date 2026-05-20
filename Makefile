.PHONY: help install d dev t test f format fc fix b build export r repl doctor clean

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
	vendor/bin/phel test

f: format
format: ## auto-format sources
	vendor/bin/phel format

fc: ## format check only (CI-style, exits non-zero on drift)
	vendor/bin/phel format --dry-run

b: build
build: ## build standalone PHP binary -> out/main.php
	vendor/bin/phel build

export: ## regenerate PHP wrappers in src/PhelGenerated/
	vendor/bin/phel export

r: repl
repl: ## start phel REPL
	vendor/bin/phel repl

doctor: ## verify environment + module health
	vendor/bin/phel doctor

clean: ## drop build artifacts and caches
	rm -rf out .phel/cache
