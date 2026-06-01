# phel-doom

Terminal raycaster DOOM-lite, written in pure Phel (Lisp on PHP). ANSI render, pure-functional state, hot frame budget.

## Architecture

```
src/main.phel                → CLI bootstrap (symfony/console via phel.cli)
src/commands/play.phel       → game loop (cast → step → render)
src/core/            → pure logic: engine, combat, enemy, level, map, physics, state
src/glue/            → wiring: controls, input, scores, sound, wad
src/io/              → side effects: render (ANSI), audio
tests/<layer>/       → phel.test deftest files, mirror src layout (`-test` suffix)
tests/commands/              → top-level command tests
docs/<topic>.md              → architecture, perf, render, raycaster, state, etc.
out/main.php                 → `composer build` artifact (do NOT edit by hand)
```

Read `docs/architecture.md`, `docs/state.md`, `docs/performance.md` before touching anything cross-cutting. Each major module has matching `docs/<module>.md`.

## Skills (slash commands)

Authoritative for their topic. Load skill before guessing. Match workflow first, fall back to plain commands.

- `/test [scope]` → run tests, scope mapping (`.claude/skills/test/SKILL.md`)
- `/commit [msg]` → ci gates + conventional commit (`.claude/skills/commit/SKILL.md`)
- `/pr [issue]` → push + open PR via template (`.claude/skills/pr/SKILL.md`)
- `/gh-issue [N]` → fetch issue, branch, TDD, ship (`.claude/skills/gh-issue/SKILL.md`)
- `/gh-issues` → walk all open issues sequentially (`.claude/skills/gh-issues/SKILL.md`)
- `/fix` → auto-format + lint (`.claude/skills/fix/SKILL.md`)
- `/changelog [entry]` → update `## Unreleased` (`.claude/skills/changelog/SKILL.md`)
- `/phel-repl <expr>` → eval Phel expression (`.claude/skills/phel-repl/SKILL.md`)
- `/perf-bench [scope]` → cast/render phase timing (`.claude/skills/perf-bench/SKILL.md`)
- `/play` → launch game, smoke-test feature manually (`.claude/skills/play/SKILL.md`)

## Agents (subagents)

Spawn via Agent tool. Prefer parallel where independent. For codebase search use built-in `Explore`. For changelog updates use `/changelog`.

| Agent | When |
|-------|------|
| `tdd-coach` | red-green-refactor a new behavior. owns failing test first. |
| `clean-code-reviewer` | review diff or PR for Phel smells + game conventions. |
| `game-debugger` | crash, wrong render, input desync, raycast math off. |
| `raycaster-expert` | DDA, ray math, fisheye, hit-side, sprite occlusion (`engine.phel`). |
| `render-expert` | ANSI emit, RLE, frame-stats, color, HUD layout (`render.phel`). |
| `perf-profiler` | cast/render ms split, bytes emitted, memory. measurement-led. |
| `docs-sync` | drift between code and `docs/<module>.md`. |

## Project conventions (not in global)

- Branch prefixes match commit type: `feat/` `fix/` `ref/` `docs/` `perf/`.
- Phel: kebab-case, `defn-` for private, `;` line comments, `conj` over `put`. Namespaces use **dot** (`phel.test`, never `phel\test`).
- `docs/` is part of the codebase — drift = same-commit fix.
- NEVER use the em-dash character `—` in `README.md` or `docs/*.md`. Use ASCII hyphen `-`, colon, or split into separate sentences instead. (CLAUDE.md + commit messages + code comments are exempt.)
- `feat:` / `fix:` / `perf:` commits update `CHANGELOG.md` under `## Unreleased`.
- Side effects only in `src/io/`. `core/` and `glue/` stay pure.
- PR label by branch prefix: `fix/` → `bug`, `feat/` → `enhancement`, `perf/` → `performance`, `docs/` → `documentation`, `ref/` → `refactoring`.
- GH issues: do NOT auto-assign on create. Assignment = WIP signal.

## Module-specific rules

Under `.claude/rules/`:
- `phel.md` — naming, docstrings, comments
- `macro-hygiene.md` — quasiquote, gensym, shadowing
- `game.md` — frame budget, pure state, immutable world
- `io-boundaries.md` — what may live in `io/` vs `core/` vs `glue/`
