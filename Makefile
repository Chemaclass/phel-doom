.PHONY: help install d dev t test f format fc fix b build r repl doctor clean p play play-dev play-boss play-level play-armory

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

play-dev: ## god mode: no damage, GOD badge in HUD — for testing rooms / weapons end-to-end
	vendor/bin/phel run phel-doom.main play --god

play-boss: ## god + armory + L10 boss arena straight away
	vendor/bin/phel run phel-doom.main play --god --armory --level=10

play-level: ## god + armory + start at level N: `make play-level LV=8`
	vendor/bin/phel run phel-doom.main play --god --armory --level=$(or $(LV),1)

play-armory: ## god + armory (every weapon, infinite ammo); start at L1
	vendor/bin/phel run phel-doom.main play --god --armory

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

r: repl
repl: ## start phel REPL
	vendor/bin/phel repl

doctor: ## verify environment + module health
	vendor/bin/phel doctor

clean: ## drop build artifacts and caches
	rm -rf out .phel/cache
