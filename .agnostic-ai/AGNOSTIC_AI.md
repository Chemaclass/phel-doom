# phel-doom

Terminal raycaster DOOM-lite, written in pure Phel (Lisp on PHP). ANSI render, pure-functional state, hot frame budget.

## Architecture

```
src/main.phel                → CLI bootstrap (symfony/console via phel.cli)
src/commands/play.phel       → game loop (input → step → cast → render)
src/commands/demo.phel       → talk showcase: the play loop plus src/demo/phases.phel
src/core/                    → pure logic: engine, combat, enemies, level, map, physics, state, weapons, ...
src/glue/controls.phel       → pure wiring: key codes to intents
src/io/                      → side effects: render/ (ANSI), input, sound, music, scores, savegame, wad
tests/<layer>/               → phel.test deftest files, mirror src layout (`-test` suffix)
docs/<topic>.md              → architecture, perf, render, raycaster, state, etc.
out/main.php                 → `composer build` artifact (do NOT edit by hand)
```

Read `docs/architecture.md`, `docs/state.md`, `docs/performance.md` before touching anything cross-cutting. Each major module has matching `docs/<module>.md`.

## Skills and agents

Project skills (`test`, `commit`, `pr`, `fix`, `changelog`, `release`, `phel-repl`, `perf-bench`, `play`) are authoritative for their topic: load one before guessing. Hand engine math, render, perf, debugging and docs drift to the matching project agent. For codebase search use a read-only explorer.

Run `composer install` in the main checkout to install the Git hooks. New linked worktrees without `vendor/` sync the agent configuration on checkout when `agnostic-ai` is on PATH. In Codex, use `/hooks` to review and trust the project hooks before they run. Codex 0.155 and later inherit the parent session sandbox, so `readonly: true` does not enforce a read-only reviewer; use a read-only parent session when that guarantee is required.

## Project conventions (not in global)

- Branch prefixes match commit type: `feat/` `fix/` `ref/` `docs/` `perf/`.
- Phel: kebab-case, `defn-` for private, `;` line comments, `conj` over `put`. Namespaces use **dot** (`phel.test`, never `phel\test`).
- `docs/` is part of the codebase — drift = same-commit fix.
- NEVER use the em-dash character `—` in `README.md` or `docs/*.md`. Use ASCII hyphen `-`, colon, or split into separate sentences instead. (CLAUDE.md + commit messages + code comments are exempt.)
- `feat:` / `fix:` / `perf:` commits update `CHANGELOG.md` under `## Unreleased`.
- Side effects only in `src/io/`. `core/` and `glue/` stay pure.
- PR label by branch prefix: `fix/` → `bug`, `feat/` → `enhancement`, `perf/` → `performance`, `docs/` → `documentation`, `ref/` → `refactoring`.
- GH issues: do NOT auto-assign on create. Assignment = WIP signal.

## Issue work

`/gh-issue` and `/gh-issues` (personal skills) own the workflow. Project specifics:

- Branch `<prefix><issue>-<slug>` from `origin/main`; prefix from issue label: `bug` → `fix/`, `enhancement` → `feat/`, `performance` → `perf/`, `documentation` → `docs/`, `refactoring` → `ref/`, none → `feat/`.
- Test first via `tdd-coach`; hand engine math, render, and perf to their specialist agents. `io/` changes need a `/play` smoke test.
- Gate: `composer ci`. Before `/pr`, run `clean-code-reviewer` over the diff and commit its fixes as a separate `ref:` commit.
- Squash-merge only after CI is green; never `--admin` past a red check.

## Module-specific rules

Sources live in `.agnostic-ai/rules/`: `phel.md` (naming, interop, per-frame maps), `macro-hygiene.md`, `game.md` (frame budget, pure state), `io-boundaries.md` (what goes in `core/`, `glue/`, `io/`).

::target codex
Codex loads them through the nested `AGENTS.md` in `src/`, `tests/` and `tools/` only when the session starts there. From the root, read that folder's `AGENTS.md` before editing under it.
::end
