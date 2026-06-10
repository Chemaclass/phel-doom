# Game loop

IO shell + pure per-frame transition. `src/commands/play.phel`.

## Top-level structure

Four lifecycle layers:

1. **`run-play`**: setup / start-menu / run-levels / cleanup. Only function with terminal restore responsibility.
2. **`show-start-menu!`**: polling loop until player starts or quits. Redraws each frame so terminal resize works.
3. **`run-levels`**: level loop carrying lives + kills + time. On death/victory, writes score + shows end screen. `r` restarts with fresh seed; `R` replays same seed.
4. **`game-loop world0`**: one level. Per-frame: render / drain input / tick-world / decide (continue / death / door / quit).

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
2. Render frame via `draw-frame` + `render!` (io/render.phel); adaptive-sleep yields per frame budget.
3. Drain input: `drain-keys` reads up to 64 bytes non-blocking. Held keys send multiple bytes per frame.
4. Compute dt + edges: `ms-since` for wall-clock; `rising-edges` diffs key snapshots for one-shots.
5. Tick world: pure `tick-world` call (used by tests too).
6. Branch: quit (Q), die (lives <= 0), door (next level or victory), or recur.

## tick-world

Pure one-frame state machine. Returns `world'` (same type). Called identically from both the game-loop and unit tests.

Three early-exit paths:
1. If paused, return unchanged.
2. If hit-stop timer > 0, decay it and return.
3. Otherwise: full linear pipeline (input → physics → pickups → enemies → projectiles → combat → decay).

The pipeline enqueues effects (sfx, hits) into `:sfx` on the world itself; the game-loop drains `:sfx` after tick and emits via `io/sound`, keeping tick pure.

| Step group | What | Module |
|---|---|---|
| `handle-toggles` | Rising-edge: pause / map / sound / debug / about-face | `commands/play` |
| `refresh-from-keys` | Refresh `:moves` counters from input bytes | `glue/controls` |
| `switch-weapon` (1-8) | Key-edge swap active weapon (no-op while reloading) | `core/weapons` |
| `try-reveal-secret` / `try-toggle-switch` | F-key adjacent: secret reveal OR switch toggle + targets | `commands/play` |
| `mark-visible-cells` | Stamp LOS cells onto `:visited` (fog-of-war reveal) | `core/engine` |
| `tick-stamina` + `apply-physics` | Drain sprint pool; rotate + translate + decay counters | `core/physics` |
| `pickup-*` (x9) | Hearts, armor, armor-shards, ammo, berserk, invuln, soulsphere, backpack, weapon | `commands/play` |
| `tick-enemies` | Step alive enemies; tick respawn + AI + hit-flash | `core/enemy`, `core/enemy_ai` |
| `tick-projectiles` | Spawn bolts from released casters; march + cull; resolve player impacts | `core/projectile` |
| `reload` | R edge: drain reserve into mag; arm cooldown | `core/combat` |
| `tick-armory` | `--armory`: refill reserves per frame | `core/combat` |
| `tick-shooting` | Fire edge: resolve hitscan; empty-mag CLICK prompt | `core/combat` |
| `damage-step` | Decay iframes + timers; apply contact damage | `core/combat` |
| `tick-heartbeat` / `tick-flicker` / `tick-scare` / `tick-blood-drops` / `tick-door-face` | Horror anims: heartbeat, light pulse, jumpscare, ceiling drips, door eye | `commands/play` |
| `decay-soul-overcap` | Over-cap HP decay (soulsphere timer) | `core/state` |
| `advance-game-time` | Add `dt` to pause-aware `:game-time` (render pulses) | `core/state` |

`tick-world` calls no IO. Every cue (pickups, combat, secret reveal, switch) enqueues `{:name :vol}` on `:sfx` via `push-sfx`. Queue reset at tick top, drained + emitted by game-loop after tick, gated on `:sound-on`. Keeps tick pure so tests run full frame sequences without side effects. See [audio.md](audio.md).

## Frame timing + adaptive FPS

- **60 fps target** (16.667 ms) at every terminal size, via `core/perf.phel`. The old big-screen 30fps cap was removed - it was an artificial ceiling (see `docs/performance.md`).
- `target-frame-us` returns a uniform 16667 µs. Render time is the real bottleneck on big screens; `adaptive-sleep!` fills the remainder of the budget and floors at `min-yield-us`, so framerate degrades smoothly toward render-native instead of snapping to 30fps.
- `ms-since` computes wall-clock delta. Args tagged `^float` so Phel doesn't infer `int` from `* 1000` and trigger PHP 8.4+ implicit-conversion deprecation on microtime values.
- `dt` is elapsed-seconds float used by physics, AI, decay. Same dt across sub-steps keeps simulation consistent inside a frame.

## Per-level result kinds

```phel
:quit                                ; player pressed Q
{:game-over true ... }               ; lives reached 0
{:victory   true ... }               ; stepped on door of L5
{:next-level true :level N ... }     ; stepped on door of L<5
```

`run-levels` matches on these to decide the next iteration.

## Restart modes

- `r` (restart, fresh): new PRNG seed, new level sequence.
- `R` (replay, same): reuse the captured seed, replay identical levels.

Lets the player practice a tough spawn or die-on level. See [input.md](input.md) for key flow and [rendering.md](rendering.md) for render pipeline.
