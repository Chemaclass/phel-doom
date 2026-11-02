---
description: "Game-loop discipline, frame budget, state purity; use when editing src, tests or tools"
globs: src/**,tests/**,tools/**
---

# Game conventions

## Frame budget

Cast plus render under 5 ms per frame at 120x30; hard ceiling 16 ms. Do not regress the hot paths without justification:

- `src/core/engine.phel`: `cast-ray`, `cast-frame`
- `src/io/render/`: `render!`, RLE emit, shade strings
- `src/core/physics.phel`: `step-world`

Read `docs/performance.md` before optimizing. Bench before claiming a win (`/perf-bench`).

## State purity

- `world` is an immutable map threaded through the loop. Never mutate it.
- `core/` and `glue/`: no `php/print`, no `php/echo`, no global atom mutation, no `php/rand` (thread the RNG seed through `world`). Effects go in `src/io/` ([io-boundaries.md](io-boundaries.md)).
- Loop in `play.phel`: input, `step-world` (pure), `cast-frame` (pure), `render!` (io). Each frame makes a new `world`; keep no back-references.

## Tests

Pure modules need unit tests in `tests/<layer>/<name>-test.phel` (`tests/commands/` for the play loop). Side-effecting code may have smoke tests; `/play` covers it. Run `composer test` before any commit touching `core/` or `glue/`.

## Doc sync

Update the doc in the same commit; stale docs block merge.

| Code | Doc |
|------|-----|
| `engine.phel` | `docs/raycaster.md` |
| `src/io/render/` | `docs/rendering.md`, `docs/performance.md` |
| `combat.phel`, `enemy.phel` | `docs/combat.md`, `docs/monsters.md` |
| `level.phel`, `map.phel`, `wad.phel` | `docs/level-system.md`, `docs/map.md`, `docs/wad-parser.md` |
| `state.phel` | `docs/state.md` |
| `controls.phel`, `input.phel` | `docs/input.md` |
| `sound.phel`, `music.phel` | `docs/audio.md` |
| `scores.phel` | `docs/scores.md` |
| `play.phel` | `docs/game-loop.md` |
