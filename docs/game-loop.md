# Game loop

IO shell + pure per-frame transition. `src/commands/play.phel`.

## Top-level structure

```phel
(defn- run-play [ctx]
  (init-input!)                    ; switch to alt screen + raw mode
  (if (php/=== (show-start-menu!) :quit)
    (do (restore!) (clear-screen) 0)
    (do (clear-screen)
        (run-levels)               ; play through L1..L5 with restart
        (restore!)                 ; restore terminal
        (clear-screen)
        (cli/success ctx "Thanks for playing.")
        (print-credits)
        0)))
```

Four lifecycle layers:

1. **`run-play`**: installs terminal mode, shows the start menu, plays one run, restores. Only function with cleanup responsibility.
2. **`show-start-menu!`**: polls for any keypress while drawing `render-start-menu` each frame (so terminal resizes redraw cleanly). `q` aborts before the run begins.
3. **`run-levels`**: loops levels carrying lives + kills + time. On death/victory calls `handle-end`, which writes the high-score file and shows the end screen. `r`/`R` restarts on the level you died on; victory restarts at L1.
4. **`game-loop world0`**: one level. Reads input, calls render, calls `tick-world`, decides per frame: continue / died / stepped on door / quit.

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
(defn tick-world [world keys ^float dt edges]
  (let [w0 (handle-toggles world edges)]
    (cond
      (:paused w0) w0
      ;; Hit-stop: a meaty kill stamped :hit-stop-secs last frame. Freeze
      ;; the whole gameplay step (just decay the timer) so the blow lands
      ;; with weight; render keeps drawing the frozen frame. See combat.md.
      (pos? (:hit-stop-secs w0))
      (assoc w0 :hit-stop-secs (max 0.0 (- (:hit-stop-secs w0) dt)))
      ;; Linear pipeline. Each step takes the previous world + own deps.
      ;; Real code uses sequential `let` bindings, not `->` (Phel lint
      ;; doesn't macro-expand `->`, false arity errors).
      :else
      (-> (refresh-from-keys w0 keys)
          (switch-weapon-if-edge edges)
          (try-reveal-secret  (:action edges))
          (try-toggle-switch  (:action edges))
          (mark-visible-cells)
          (tick-stamina dt) (apply-physics dt)
          (pickup-hearts) (pickup-armors) (pickup-armor-shards) (pickup-ammos)
          (pickup-berserks) (pickup-invulns) (pickup-soulspheres)
          (pickup-backpacks) (pickup-keycards) (pickup-weapon-pickups)
          (tick-enemies dt)
          (tick-projectiles dt)
          (maybe-reload edges)
          (tick-armory)
          (tick-shooting (:fire edges) (:fire-held edges))
          (damage-step dt)
          (tick-heartbeat dt) (tick-flicker dt) (tick-scare dt)
          (tick-blood-drops dt) (tick-door-face dt)
          (decay-soul-overcap dt)
          (advance-game-time dt)))))
```

| Step group | What | Module |
|---|---|---|
| `handle-toggles` | Rising-edge: pause / map / sound / debug / about-face | `commands/play` |
| `refresh-from-keys` | Refresh `:moves` counters from input bytes | `glue/controls` |
| `switch-weapon` | 1/2/3/4 keys swap active weapon (no-op while reloading) | `core/weapons` |
| `try-reveal-secret` / `try-toggle-switch` | `F` adjacent: unhide secret wall OR flip switch + linked cells | `commands/play` |
| `mark-visible-cells` | Stamp visit + LOS cells onto `:visited` (fog-of-war) | `commands/play` |
| `tick-stamina` + `apply-physics` | Drain sprint pool, then rotate + translate + decay counters | `core/physics` |
| `pickup-*` | Hearts, armor + shards, ammo, berserk, invuln, soulsphere, backpack, keycards, weapon pickups | `commands/play` |
| `tick-enemies` | Step alive enemies; tick respawn + AI + hit-flash | `core/enemy`, `enemy_ai` |
| `tick-projectiles` | Spawn caster fireballs, march + cull bolts, resolve player impacts | `core/projectile` |
| `reload` | R edge: drain `:ammo-reserve` into `:mag`, arm cooldown + anim | `core/combat` |
| `tick-armory` | `--armory` flag: refill reserves to `armory-reserve` per frame | `core/combat` |
| `tick-shooting` | Fire edge: resolve hitscan; empty mag arms CLICK prompt | `core/combat` |
| `damage-step` | Decay timers; apply contact damage if `:iframes` is 0 | `core/combat` |
| `tick-heartbeat` … `tick-door-face` | Horror layer: pulse, light flicker, jump-scare, ceiling drips, door eye | `commands/play` |
| `decay-soul-overcap` | Drop one life per 5s while `:lives > max-lives` (soulsphere) | `core/state` |
| `advance-game-time` | Add `dt` to pause-aware `:game-time` (drives render pulses) | `core/state` |

`tick-world` calls no IO. Data in, data out. Sound is the one effect that looks tempting to fire inline (a pickup "should" beep): instead every cue (combat, pickups, secret reveal, switch toggle) enqueues a `{:name :vol}` event on the world's `:sfx` queue via `combat/push-sfx`. The queue is reset at the top of the tick and drained by the game loop afterwards, emitted via `io/sound` and gated on `:sound-on`. That keeps the whole transform pure, so tests drive entire frame sequences without touching the terminal. See [audio.md](audio.md).

## Frame timing + adaptive FPS

- **60 fps target** (16.667 ms) on standard terminals (< 200 cols OR area ≤ 12000 cells).
- **30 fps** on big screens (≥ 200 cols OR area > 12000 cells) - perf-mode engagement via `core/perf.phel`.
- `target-frame-us` reads terminal dimensions each loop and selects 16667 µs (60 fps) or 33333 µs (30 fps). Render time is the real bottleneck; sleep yields CPU.
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
