# Demo record / replay

`src/io/demo.phel` + `src/core/rng.phel` (issue #64). Deterministic record/replay for bug repros and property-testable game-loop.

## Seeded RNG

Replaced `php/random_int` + `php/mt_rand` with single Park-Miller LCG (seeded module atom). Every gameplay draw (level gen, enemy spawn/wander, loot, blood, angles) flows through it. Result: **seed + input stream fully determine the run** - re-seed + same inputs = world matches frame for frame. Fixes `R` (restart same map) which previously re-seeded `mt_rand` but map-gen ignored it.

## Format

Demo = seed + per-frame `[key-bytes, dt-ms]` stream:
```json
{"version": 1, "seed": 4242, "frames": [["w", 16], ["wa", 17]]}
```

`frames->json` / `json->demo` are pure (unit-tested). Version mismatch or malformed file -> `nil`.

## Record / replay

`--record=FILE`: each frame appends live `[keys, ms]` and passes it through; on exit writes file.
`--demo=FILE`: loads seed + frames, re-runs `game-loop` with recorded inputs, skips start menu.

Seam is `resolve-frame!` (`phel-doom.io.demo`) called from the play loop: `:off` (live), `:record` (tap live), `:replay` (substituted). File IO in loop, never pure `tick-world`. When replay exhausts frames, returns `{:end? true}` and loop quits.
