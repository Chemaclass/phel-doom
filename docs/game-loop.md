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

1. Capture terminal size; clear buffer on resize. `term-size` forks + execs `stty size`, so the real loop does NOT call it every frame: a `poll-frame` counter is threaded through the recur and `term-size` is sampled only when `(poll-size? poll-frame)` is true (frame 0, then every `resize-poll-frames` = 6 frames). Between samples the last `[rows cols]` is reused. The first frame is always eager so initial sizing is never delayed; `redraw-if-resized` + the auto-calibration tolerate a resize being noticed up to ~6 frames late. The simplified snippet above omits this throttle for clarity. Throttled at all four size-polling loops: the game loop, the end screens (`end-loop`), the settings sub-loop (`settings-screen!`), and the start menu (`show-start-menu!`).
2. Render frame via `draw-frame` + `render!` (io/render.phel); adaptive-sleep yields per frame budget.
3. Drain input: `drain-keys` reads up to `drain-bytes` (512) bytes non-blocking. Held keys send multiple bytes per frame.
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
| `tick-stamina` + `apply-physics` | Drain sprint pool; rotate + translate (with Z step/fall) + ease pending fall + decay counters | `core/physics` |
| `pickup-*` (x10) | Hearts, armor, armor-shards, ammo, berserk, invuln, soulsphere, backpack, weapon, keycards | `core/pickups` |
| `tick-enemies` | Step alive enemies; tick respawn + AI + hit-flash | `core/enemy`, `core/enemy_ai` |
| `tick-projectiles` | Spawn bolts from released casters; march + cull; resolve player impacts | `core/projectile` |
| `reload` | R edge: drain reserve into mag; arm cooldown | `core/combat` |
| `tick-armory` | `--armory`: refill reserves per frame | `core/combat` |
| `tick-shooting` | Fire edge: resolve hitscan; empty-mag CLICK prompt | `core/combat` |
| `damage-step` | Decay iframes + timers; apply contact damage | `core/combat` |
| `tick-heartbeat` / `tick-scare` / `tick-blood-drops` | Horror beats: heartbeat thump + edge, proximity sfx-silence, ceiling drips. (The lights-flicker and door-eye ticks were removed with their decorative visuals; `tick-scare` stays for the `:silence-tick?` audio cue - the jump-scare visual was dropped.) | `commands/play` |
| `decay-soul-overcap` | Over-cap HP decay (soulsphere timer) | `core/state` |
| `advance-game-time` | Add `dt` to pause-aware `:game-time` (render pulses) | `core/state` |

`tick-world` calls no IO. Every cue (pickups, combat, secret reveal, switch) enqueues `{:name :vol}` on `:sfx` via `push-sfx`. Queue reset at tick top, drained + emitted by game-loop after tick, gated on `:sound-on`. Keeps tick pure so tests run full frame sequences without side effects. See [audio.md](audio.md).

## Physics on flat ground

The world is uniformly flat (z = 0 floor, z = 1 ceiling). `apply-physics` translates and returns updated player position. No step-up / fall / handrail logic applies since there is no elevation change. Wall and locked-door collision are checked. The player's camera is fixed at standard eye height (0.5 units above the ground). See [state.md](state.md) for the field contract.

## Frame timing + adaptive FPS

- **60 fps target** (16.667 ms) at every terminal size, via `core/perf.phel`. The old big-screen 30fps cap was removed - it was an artificial ceiling (see `docs/performance.md`).
- `target-frame-us` returns a uniform 16667 µs. Render time is the real bottleneck on big screens; `adaptive-sleep!` fills the remainder of the budget and floors at `min-yield-us`, so framerate degrades smoothly toward render-native instead of snapping to 30fps.
- The live `term-size` is clamped through `cap-dims` (`core/perf.phel`) before render, applying the `--max-cols` / `--max-rows` caps. A manual cap shrinks the render area and leaves the surplus terminal as a blank inset border (the full-screen clear on resize keeps it clean). Caps only shrink, never grow past the real terminal.
- **Auto-calibrated pixel scale** (default when neither `--max-cols` nor `--max-rows` is set; `opt-int` returns `-1` for unset so the loop can tell "auto" from an explicit `0` = fill). The render always fills the whole terminal in auto mode; what calibration picks is the DETAIL. The loop renders at full detail for the first `auto-cal-frames` frames (covered by the intro splash), tracks the min measured render-ms, then `auto-pixel-scale` locks pixel scale 1 (full detail) or 2 (pixel-doubled: the scene renders at half resolution and each scene cell paints a 2x2 block, ~4x cheaper, same framing/FOV - see `docs/performance.md`). Pixel scale 2 is only ever picked on a big screen (cell area beyond 200x45, `perf/big-screen?`); a terminal at or below that size keeps full detail regardless of the measured cost - detail wins over framerate there. `next-cal` holds the calibration state; `draw-frame` passes the choice to the renderer as the `:px2?` stats flag. The render-ms measured here is the *real* per-frame cost (frame->string + the terminal write), so the choice targets actual smoothness, not just CPU. Recalibrates when `term-size` changes. An explicit `--max-cols` / `--max-rows` opts out (full detail at the player's size).
- `ms-since` computes wall-clock delta. Args tagged `^float` so Phel doesn't infer `int` from `* 1000` and trigger PHP 8.4+ implicit-conversion deprecation on microtime values.
- `dt` is elapsed-seconds float used by physics, AI, decay. Same dt across sub-steps keeps simulation consistent inside a frame. The raw frame ms is clamped through `clamp-frame-ms` (cap `max-frame-ms` = 100ms, a ~10fps floor) before becoming dt (#278), so one stalled frame can't feed a hundreds-of-ms dt into the un-swept physics tick (which would tunnel the player through a 1-thick wall / locked door) or drain every feel timer a full step at once. Real frames (16-50ms) are well under the cap, so live tick / FPS / golden frames are unaffected.

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
