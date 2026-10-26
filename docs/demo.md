# Demo record / replay

`src/io/demo.phel` and `src/core/rng.phel` provide deterministic recording and replay for bug reproduction (issue #64). For the `demo` command, see the [tech-talk showcase](demo-showcase.md).

## Seeded RNG

Every gameplay draw (level gen, enemy spawn and wander, loot, blood, angles) goes through one seeded Park-Miller LCG in `core/rng`. `php/random_int` cannot be seeded, so it cannot support replay or `R` (restart the same map). The seed and input stream determine the world frame by frame.

## Format

A demo is the seed plus a per-frame `[key-bytes, dt-ms]` stream:

```json
{"version": 1, "seed": 4242, "frames": [["w", 16], ["wa", 17]]}
```

`frames->json` and `json->demo` are pure and unit-tested. A version mismatch, malformed JSON, or a frame that is not a `[string, number]` pair parses to `nil`.

## Record / replay

- `--record=FILE`: each frame appends the live `[keys, ms]` and passes it through. The file is written on exit.
- `--demo=FILE`: loads seed and frames, re-runs `game-loop` on the recorded input, and skips the start menu.

`resolve-frame!` runs once per frame from the play loop. Modes: `:off` (live), `:record` (tap live), `:replay` (substitute recorded). File IO stays in the loop, never in the pure `tick-world`. When a replay runs out of frames, `resolve-frame!` returns `{:end? true}` and the loop quits.
