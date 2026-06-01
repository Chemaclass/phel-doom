---
description: Game-loop discipline, frame budget, state purity
globs: src/**,tests/**,*.phel
---

# Game Conventions

## Frame budget

Target: **cast + render < 5 ms** per frame at 120×30. Hard ceiling: 16 ms (60 fps).

Hot paths (do NOT regress without justification):
- `src/core/engine.phel` — `cast-ray`, `cast-frame`
- `src/io/render.phel` — `render!`, RLE emit, shade strings
- `src/core/physics.phel` — `step-world`

Before optimizing: read `docs/performance.md`. Before claiming a win: bench (see `/perf-bench`).

## State purity

- `world` is an immutable map threaded through the loop. **Never mutate.**
- Pure transforms in `core/` and `glue/`. No `php/print`, no `php/echo`, no global atom mutation.
- Side effects only in `src/io/`. See [io-boundaries.md](io-boundaries.md).
- Random numbers: thread RNG seed through `world`. No `php/rand` in `core/`.

## Loop shape

`play.phel` runs: **input → step-world (pure) → cast-frame (pure) → render! (io)**.

Each frame produces a new `world`. Old `world` discarded. No back-references.

## Tests

Pure modules MUST have unit tests under `tests/<layer>/<name>-test.phel` (and `tests/commands/` for play loop). Side-effecting code may have smoke tests but covered primarily by `/play`.

Run `composer test` before any commit that touches `core/` or `glue/`.

## Doc sync

Changing behavior covered by `docs/<topic>.md`? Update the doc in the same commit. Stale docs are blocking issues, not "nice to have."

| Code area | Doc |
|-----------|-----|
| `engine.phel` | `docs/raycaster.md` |
| `render.phel` | `docs/rendering.md`, `docs/performance.md` |
| `combat.phel`, `enemy.phel` | `docs/combat.md`, `docs/monsters.md` |
| `level.phel`, `map.phel`, `wad.phel` | `docs/level-system.md`, `docs/map.md`, `docs/wad-parser.md` |
| `state.phel` | `docs/state.md` |
| `controls.phel`, `input.phel` | `docs/input.md` |
| `sound.phel` | `docs/audio.md` |
| `scores.phel` | `docs/scores.md` |
| `play.phel` | `docs/game-loop.md` |
