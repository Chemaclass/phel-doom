# Game loop

IO shell + pure per-frame transition. `src/commands/play.phel`.

## Top-level structure

```phel
(defn- run-play [ctx]
  (init-input!)                    ; switch to alt screen + raw mode
  (run-levels)                     ; play through L1..L5 with restart
  (restore!)                       ; restore terminal
  (clear-screen)
  (cli/success ctx "Thanks for playing.")
  (print-credits)
  0)
```

Three lifecycle layers:

1. **`run-play`**: installs terminal mode, plays one run, restores. Only function with cleanup responsibility.
2. **`run-levels`**: loops levels carrying lives + kills + time. On death/victory calls `handle-end`, which writes the high-score file and shows the end screen. Restart loops to L1.
3. **`game-loop world0`**: one level. Reads input, calls render, calls `tick-world`, decides per frame: continue / died / stepped on door / quit.

## game-loop

```phel
(defn- game-loop [world0]
  (let [t-start (php/microtime true)]
    (loop [world     world0
           t-last    t-start
           frame-ms  0
           fps       0
           prev-keys initial-key-snapshot
           dims      [0 0]]
      (let [[rows cols] (term-size)]
        (redraw-if-resized dims rows cols)
        (draw-frame world fps frame-ms rows cols)
        (let [keys     (drain-keys)
              now      (php/microtime true)
              ms       (ms-since t-last now)
              now-keys (key-states keys)
              world'   (tick-world world keys (php// ms 1000.0)
                                   (rising-edges now-keys prev-keys))]
          (cond
            (str/contains? keys "q")    :quit
            (php/<= (:lives world') 0)  (result-game-over world' t-start now)
            (on-door? world')           (door-result      world' t-start now)
            :else                       (recur world' now ms
                                               (fps-from-ms ms)
                                               now-keys
                                               [rows cols])))))))
```

1. Capture terminal size; clear buffer on resize.
2. Render frame. `draw-frame` calls `render!` from `io/render.phel`, sleeps 1ms (yields CPU; render time is the real throttle).
3. Drain input. `drain-keys` reads up to 64 bytes non-blocking. Held keys deliver multiple bytes per frame.
4. Compute dt + edges. `ms-since` for elapsed wall-clock. `rising-edges` diffs key snapshots for one-shot actions.
5. Tick world. `tick-world` is pure. Same call the tests use.
6. Decide next: quit (Q), die (lives <= 0), step on door (advance / victory), or recur.

## tick-world

```phel
(defn tick-world
  {:export true}
  [world keys ^float dt edges]
  (let [w0 (handle-toggles world edges)]
    (if (:paused w0)
      w0
      (let [w1 (refresh-from-keys w0 keys)]
        (let [w2 (apply-physics w1 dt)]
          (let [w3 (pickup-hearts w2)]
            (let [w4 (tick-enemies w3 dt)]
              (let [w5 (tick-shooting w4 (:fire edges))]
                (damage-step w5 dt)))))))))
```

| Step | What it does | Module |
|---|---|---|
| `handle-toggles` | Apply rising-edge toggles (pause / map / sound) | `commands/play` |
| `refresh-from-keys` | Walk input bytes, refresh `:moves` counters | `glue/controls` |
| `apply-physics` | Rotate then translate then decay counters | `core/physics` |
| `pickup-hearts` | Standing on a heart = gain a life | `commands/play` |
| `tick-enemies` | Step alive enemies toward player; tick respawn timers | `core/enemy` |
| `tick-shooting` | If fire edge, resolve hitscan | `core/combat` |
| `damage-step` | Decay timers; apply contact damage if i-frames are 0 | `core/combat` |

`tick-world` calls no IO. Data in, data out. Lets the test suite drive entire frame sequences without touching the terminal.

## Frame timing

- `frame-us = 1000` (1ms `usleep`). Actual frame bounded by render time (~5ms at 180×40), not sleep. Sleep yields CPU.
- `ms-since` computes wall-clock delta. Tagged `^float` on time params so Phel doesn't infer `int` from `* 1000` and trigger PHP 8.4+ implicit-conversion deprecation on microtime values.
- `dt` is elapsed-seconds float used by every physics / AI / decay step. Same dt across sub-steps keeps simulation consistent inside a frame.

## Per-level result kinds

```phel
:quit                                ; player pressed Q
{:game-over true ... }               ; lives reached 0
{:victory   true ... }               ; stepped on door of L5
{:next-level true :level N ... }     ; stepped on door of L<5
```

`run-levels` matches on these to decide the next iteration.

## Restart with same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` call and `mt_srand`s it. On `R` (capital) from an end screen, the captured seed is reused: identical map sequence. On `r` (lowercase) it picks a fresh seed. Lets the player replay a tough spawn.

See [input.md](input.md) for how keys reach `tick-world` and [rendering.md](rendering.md) for what `render!` does on the way out.
