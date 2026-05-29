# Demo record / replay

`src/io/demo.phel` + `src/core/rng.phel` (issue #64). Deterministic
record + replay of a run for bug repros, highlight reels, and making the
game-loop determinism property testable.

## Determinism foundation: seeded RNG

The game used to draw randomness from `php/random_int` (via `rand-int`)
and `php/mt_rand`. `random_int` is a CSPRNG and cannot be seeded, so runs
were unreproducible. `core/rng` replaces both with a single seeded
generator (Park-Miller minimal-standard LCG, `x' = 16807x mod 2^31-1`,
held in a module atom):

```phel
(rng/seed! n)     ; seed (folds any int into 1..m-1)
(rng/int! n)      ; 0..n inclusive  (rand-int replacement)
(rng/float!)      ; [0, 1)          (mt_rand/getrandmax replacement)
(rng/next-raw!)   ; raw advance
(rng/fresh-seed)  ; a nondeterministic seed for a new run (does NOT seed)
```

Every gameplay draw (level gen, enemy spawn / respawn / pain / wander,
loot rolls, blood drops, player spawn angle) now flows through it. So
**seed + input stream fully determine the run** - re-seed and feed the
same inputs and the world matches frame for frame (pinned by
`tests/commands/play-test test-replay-reproduces-world` and
`level-test test-build-world-deterministic-under-seed`).

This also fixes `R` (restart same map): it always re-seeded `mt_rand`,
which the `random_int`-based map gen ignored, so the geometry was never
actually reproduced. Now it is.

## Demo format

A demo is the run's seed plus the per-frame `[key-bytes, dt-ms]` stream:

```json
{"version": 1, "seed": 4242, "frames": [["w", 16], ["wa", 17], ["", 16]]}
```

`frames->json` / `json->demo` are pure (unit-tested round-trip); a
version mismatch or malformed file parses to `nil`.

## Record / replay loop

`commands/play` flags:

- `--record=FILE` - `demo/start-record!` with a fresh seed; each frame
  `demo/resolve-frame!` appends the live `[keys, ms]` and passes it
  through; on exit `demo/save-recording!` writes the file.
- `--demo=FILE` - `demo/read-demo` loads `{seed, frames}`;
  `demo/start-replay!` seeds the run with the recorded seed and feeds
  the recorded frames back through the same `game-loop`, skipping the
  start menu. When the stream is exhausted `resolve-frame!` returns
  `{:end? true}` and the loop quits.

The seam is `demo/resolve-frame!` in `game-loop`: `:off` passes the live
frame through, `:record` taps it, `:replay` substitutes the recorded
one. File IO lives in the loop, never in the pure `tick-world`.

## Scope

Replay reproduces a run from the same start state (seed + level chain +
inputs). The start menu and end-screen interactions aren't part of the
recorded stream; a demo captures the playable frames.
