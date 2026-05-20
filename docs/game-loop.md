# Game loop

The IO shell + the pure per-frame transition. Lives in
`src/commands/play.phel`.

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

Three lifecycle layers, outermost first:

1. **`run-play`** — installs terminal mode, plays one full run, then
   restores. The only function with cleanup responsibility.
2. **`run-levels`** — loops through levels carrying lives + kills +
   time. On death/victory it consults `handle-end` which writes the
   high-score file and shows the end screen; restart loops back to
   level 1.
3. **`game-loop world0`** — one level. Reads input, calls render, calls
   `tick-world`, decides per-frame whether the level continues, the
   player died, the player stepped on a door, or the player quit.

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

Reads top-to-bottom:

1. **Capture terminal size**, clear the buffer if dimensions changed.
2. **Render the current frame** — `draw-frame` calls `render!` from
   `io/render.phel` and sleeps 1ms (yields the CPU; render time is
   the real throttle).
3. **Drain input** — `drain-keys` reads up to 64 bytes from stdin
   non-blocking. Held keys deliver multiple bytes per frame.
4. **Compute dt + edges** — `ms-since` gives the wall-clock elapsed
   ms; `rising-edges` compares this frame's key snapshot with the
   previous one and surfaces rising edges (one-shot actions).
5. **Tick the world** — `tick-world` is a pure function. Same call
   the test suite uses.
6. **Decide what happens next**: quit (Q), die (lives ≤ 0), step on
   a door (level advance / victory), or recur with the new world.

## tick-world

The pure per-frame transition:

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

Seven steps, each one a small focused function:

| Step | What it does | Module |
|---|---|---|
| `handle-toggles` | Apply rising-edge toggle keys (pause / map / sound) | `commands/play` |
| `refresh-from-keys` | Walk input bytes, refresh `:moves` counters | `glue/controls` |
| `apply-physics` | Rotate then translate then decay counters | `core/physics` |
| `pickup-hearts` | If player stands on a heart, gain a life | `commands/play` |
| `tick-enemies` | Step alive enemies toward player; tick respawn timers | `core/enemy` |
| `tick-shooting` | If fire edge, resolve hitscan | `core/combat` |
| `damage-step` | Decay timers; apply contact damage if i-frames are 0 | `core/combat` |

`tick-world` does not call any IO function. Everything is data in,
data out — which is what lets the test suite drive entire frame
sequences without touching the terminal.

## Frame timing

- `frame-us = 1000` (1ms `usleep` per frame). The actual frame
  duration is bounded by render time (~5ms at 180×40), not the
  sleep. The sleep is just there to yield the CPU.
- `ms-since` computes the elapsed wall-clock delta between frames.
  Tagged `^float` on its time params so Phel doesn't infer `int`
  from `* 1000` and trigger a PHP 8.4+ implicit-conversion
  deprecation on the microtime values.
- `dt` is the elapsed-seconds float that every physics / AI / decay
  step uses. Same dt across all sub-steps so the simulation stays
  consistent inside a frame.

## Per-level result kinds

`game-loop` returns one of:

```phel
:quit                                ; player pressed Q
{:game-over true ... }               ; lives reached 0
{:victory   true ... }               ; stepped on the door of level 5
{:next-level true :level N ... }     ; stepped on the door of level N<5
```

`run-levels` matches on these to decide the next iteration.

## Restart with same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` call
and `mt_srand`s it. On `R` (capital) from an end screen, it re-uses
the captured seed → identical map sequence (L1, L2, ...). On `r`
(lowercase) it picks a fresh seed → brand new maps. Lets the player
replay a particular tough spawn.

See [input.md](input.md) for how keys reach `tick-world` and
[rendering.md](rendering.md) for what `render!` does on the way out.
