# phel-doom

Terminal raycaster DOOM-lite in pure Phel (Lisp on PHP). ANSI render, pure-functional state, hot frame budget.

## Layout

```
src/main.phel                CLI bootstrap (symfony/console via phel.cli)
src/commands/play.phel       game loop: input, step, cast, render
src/commands/demo.phel       talk showcase: play loop plus src/demo/phases.phel
src/core/                    pure logic: engine, combat, enemies, level, map, physics, state, weapons, ...
src/glue/controls.phel       pure wiring: key codes to intents
src/io/                      side effects: render/ (ANSI), input, sound, music, scores, savegame, wad
tests/<layer>/               phel.test files mirroring src (`-test` suffix)
docs/<topic>.md              architecture, perf, render, raycaster, state, ...
out/main.php                 `composer build` artifact; never edit by hand
```

Read `docs/architecture.md`, `docs/state.md`, `docs/performance.md` before cross-cutting changes. Each module has a `docs/<module>.md`.

## Skills and agents

Project skills (`test`, `commit`, `pr`, `fix`, `changelog`, `release`, `phel-repl`, `perf-bench`, `play`) are authoritative for their topic: load one before guessing. Hand engine math, render, perf, debugging and docs drift to the matching project agent. Use a read-only explorer for codebase search.

## Setup

- Run `composer install` in the main checkout to install the Git hooks.
- A linked worktree without `vendor/` syncs agent config on checkout when `agnostic-ai` is on PATH, and links `vendor/` from the main checkout when `composer.json` matches. Before changing dependencies there, remove the link and run `composer install`.
- Codex: review and trust the project hooks in `/hooks` before they run. Codex 0.155+ inherits the parent sandbox, so `readonly: true` does not enforce a read-only reviewer; use a read-only parent session when you need that.

## Conventions

- Branch prefix matches commit type: `feat/` `fix/` `ref/` `docs/` `perf/`.
- Phel: kebab-case, `defn-` for private, `;` comments, `conj` over `put`. Namespaces use a dot (`phel.test`, never `phel\test`).
- Side effects only in `src/io/`; `core/` and `glue/` stay pure.
- `docs/` is code: fix drift in the same commit.
- No em dash in `README.md` or `docs/*.md`; use a hyphen, colon or two sentences. (CLAUDE.md, commit messages and code comments are exempt.)
- `feat:`, `fix:` and `perf:` commits add a line under `## Unreleased` in `CHANGELOG.md`.
- PR label by branch prefix: `fix/` bug, `feat/` enhancement, `perf/` performance, `docs/` documentation, `ref/` refactoring.
- Do not assign a GitHub issue on create; assignment signals work in progress.

## Issue work

`/gh-issue` and `/gh-issues` (personal skills) own the workflow. Project specifics:

- Branch `<prefix><issue>-<slug>` from `origin/main`. Prefix from label: `bug` `fix/`, `enhancement` `feat/`, `performance` `perf/`, `documentation` `docs/`, `refactoring` `ref/`, none `feat/`.
- Test first via `tdd-coach`. `io/` changes need a `/play` smoke test.
- Gate: `composer ci`. Before `/pr`, run `clean-code-reviewer` over the diff and commit its fixes as a separate `ref:` commit.
- Squash-merge only on green CI; never `--admin` past a red check.

## Rules

`.agnostic-ai/rules/`: `phel.md` (naming, interop, per-frame maps), `macro-hygiene.md`, `game.md` (frame budget, pure state), `io-boundaries.md` (what goes in `core/`, `glue/`, `io/`).

::target codex
Codex loads them through the nested `AGENTS.md` in `src/`, `tests/` and `tools/` only when the session starts there. From the root, read that folder's `AGENTS.md` before editing under it.
::end
