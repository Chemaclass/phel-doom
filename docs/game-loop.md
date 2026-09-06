# Game loop

IO shell + pure per-frame transition. `src/commands/play.phel`.

## Top-level structure

Four lifecycle layers:

1. **`run-play`**: setup / start-menu / run-levels / cleanup. Owns terminal restore, discharged in a `finally` so a throw mid-run cannot leave the terminal in raw mode.
2. **`show-start-menu!`**: polls until the player starts or quits. Redraws each frame so resize works.
3. **`run-levels`**: level loop carrying lives + kills + time. On death/victory, writes score + shows end screen. `r` restarts with a fresh seed; `R` replays the same seed.
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
            (quit-confirmed? world
                             (:quit-request edges))    :quit
            (php/<= (:lives world') 0)  (result-game-over world' t-start now)
            (on-door? world')           (door-result      world' t-start now)
            :else                       (recur world' now ms
                                               (fps-from-ms ms)
                                               now-keys
                                               [rows cols])))))))
```

1. Capture terminal size; clear buffer on resize. `term-size` forks + execs `stty size`, so the real loop does NOT call it every frame. A `poll-frame` counter threads through the recur; `term-size` samples only when `(poll-size? poll-frame)` holds (frame 0, then every `resize-poll-frames` = 12 frames), reusing the last `[rows cols]` between samples. Frame 0 is eager, so initial sizing is never delayed. `redraw-if-resized` + auto-calibration tolerate a resize noticed up to ~12 frames late (~100ms at the loop's 120fps cap; the menu/end-screen loops run at ~60fps, so ~200ms there, fine for static screens). The snippet above omits this throttle for clarity. All four size-polling loops throttle: game loop, end screens (`end-loop`), settings sub-loop (`settings-screen!`), start menu (`show-start-menu!`).
2. Render frame via `draw-frame` + `render!` (io/render.phel); adaptive-sleep yields per frame budget.
3. Drain input: `drain-keys` reads up to `drain-bytes` (512) bytes non-blocking. Held keys send multiple bytes per frame.
4. Compute dt + edges: `ms-since` for wall-clock; `rising-edges` diffs key snapshots for one-shots.
5. Tick world: pure `tick-world` call (used by tests too).
6. Branch: quit (confirmed Q, see Restart modes), die (lives <= 0), door (next level or victory), or recur.

## tick-world

Pure one-frame state machine. Returns `world'` (same type). Called identically from the game-loop and unit tests.

Three early-exit paths:
1. If paused, return unchanged.
2. If hit-stop timer > 0, decay it and return.
3. Otherwise: full linear pipeline (input → physics → pickups → enemies → projectiles → combat → decay).

The pipeline enqueues effects (sfx, hits) into `:sfx` on the world itself. The game-loop drains it after tick and emits via `io/sound`, keeping tick pure.

| Step group | What | Module |
|---|---|---|
| `handle-toggles` | Rising-edge: pause / map / sound / debug / about-face | `commands/play` |
| `refresh-from-keys` | Refresh `:moves` counters from input bytes | `glue/controls` |
| `switch-weapon` (1-7), `cycle-weapon` (`[` / `]` / wheel) | Key-edge swap active weapon (no-op while reloading) | `core/weapons` |
| `try-reveal-secret` / `try-toggle-switch` | F-key adjacent: secret reveal OR switch toggle + targets | `commands/play` |
| `mark-visible-cells` | Stamp LOS cells onto `:visited` (fog-of-war reveal) | `core/engine` |
| `tick-stamina` + `apply-physics` | Drain sprint pool; rotate + translate + decay counters | `core/physics` |
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

## Physics

`apply-physics` translates and returns the updated player position; collision and the locked-door bump cue both resolve inside `physics/try-move`. A cell blocks the move only when it is a wall or a locked door the player lacks the key for; any open floor cell is walkable. See [state.md](state.md) for the field contract.

`apply-physics` also advances the head-bob walk cycle (#411). It measures the ground distance covered this frame and adds it, scaled by `bob-phase-per-unit`, to `:bob-phase`, wrapped into `[0, 2*pi)`. Zero distance (standing still, or shoved against a wall) settles `:bob-phase` back to exactly 0.0, so a resting frame renders byte-identical. Amplitude is render-only (the View bob setting via `projection/bob-rows`); physics tracks only the phase.

## Frame timing + adaptive FPS

- **120 fps target** (8.333 ms) at every terminal size, via `core/perf.phel`. The old big-screen 30fps cap was removed as an artificial ceiling (see `docs/performance.md`).
- `target-frame-us` returns a uniform 8333 µs. Render time is the real bottleneck on big screens; `adaptive-sleep!` fills the rest of the budget and floors at `min-yield-us`, so framerate degrades smoothly toward render-native instead of snapping to 30fps.
- `cap-dims` (`core/perf.phel`) clamps the live `term-size` before render, applying `--max-cols` / `--max-rows`. A manual cap shrinks the render area and leaves the surplus terminal as a blank inset border (the full-screen clear on resize keeps it clean). Caps only shrink, never grow past the real terminal.
- **Auto-calibrated pixel scale** (default when neither `--max-cols` nor `--max-rows` is set; `opt-int` returns `-1` for unset, so the loop tells "auto" from an explicit `0` = fill). Auto mode always fills the whole terminal; calibration picks the DETAIL. The loop renders full detail for the first `auto-cal-frames` frames (covered by the intro splash), tracks the min measured render-ms, then `auto-pixel-scale` locks pixel scale 1 (full detail) or 2 (pixel-doubled: the scene renders at half resolution, each scene cell paints a 2x2 block, ~4x cheaper, same framing/FOV - see `docs/performance.md`). Scale 2 is only ever picked on a big screen (cell area beyond 200x45, `perf/big-screen?`); at or below that, detail wins over framerate whatever the measured cost. `next-cal` holds the calibration state; `draw-frame` passes the choice to the renderer as the `:px2?` stats flag. The measured render-ms is the *real* per-frame cost (frame->string + the terminal write), so the choice targets actual smoothness, not just CPU. Recalibrates when `term-size` changes. An explicit `--max-cols` / `--max-rows` opts out (full detail at the player's size).
- `ms-since` computes wall-clock delta. Args tagged `^float` so Phel doesn't infer `int` from `* 1000` and trigger PHP 8.4+ implicit-conversion deprecation on microtime values.
- `dt` is the elapsed-seconds float for physics, AI, decay. One dt across sub-steps keeps a frame's simulation consistent. `clamp-frame-ms` caps the raw frame ms at `max-frame-ms` = 100ms, a ~10fps floor, before it becomes dt (#278). One stalled frame then cannot feed a hundreds-of-ms dt into the un-swept physics tick, which would tunnel the player through a 1-thick wall or locked door, nor drain every feel timer a full step at once. Real frames (16-50ms) sit well under the cap, so live tick / FPS / golden frames are unaffected.

## Per-level result kinds

```phel
:quit                                ; player confirmed Q from the pause page
{:game-over true ... }               ; lives reached 0
{:victory   true ... }               ; stepped on door of L5
{:next-level true :level N ... }     ; stepped on door of L<5
```

`run-levels` matches on these to decide the next iteration.

## Run transitions (issue #470)

Two beats the run used to skip.

**Death** cut straight to the YOU DIED box, so the blow that ended the run was never seen. `death-beat!` holds the killing frame 0.6s first, then drains whatever was typed during it, so a panicked keypress cannot select something on the screen that follows.

**Level exits** jumped straight into the next level, so the per-level numbers `run-stat-fields` already tracked showed only once the run was over. `intermission-loop` shows a card with the level just cleared, its kills, its secrets and its time. Any key continues; `q` and Ctrl-C still quit.

Both are skipped under `--demo` replay: nothing is watching, and waiting for input would desync a recorded run.

## Quitting and restarting (issue #454)

`q` in a live run does not quit. It opens the pause menu with the cursor on Quit and drops the movement hold counters, so the second `q` (or Enter on that row) is the confirmation. The H / ESC info panel freezes the world too but is no confirm surface, having no Quit row, so `q` there closes it and opens the menu the same way. `quit-confirmed?` is the single gate: pause page yes, help panel no. The start menu and the end screens run their own loops and still quit on one `q`. Ctrl-C still quits from anywhere.

Restart on the pause menu asks twice for the same reason: the first select arms it (the row reads `Restart?  enter again`), a second select fires, moving the cursor disarms. The armed flag never leaves the session - resume, re-pause and quick-saves all clear it.

Losing terminal focus (`\e[?1004h`, see [input.md](input.md#focus-tracking-issue-454)) pauses a live run and drops held movement, so alt-tabbing away cannot leave the player being chewed on. An already-paused world is left alone.

## Resize: SIGWINCH, not polling (issue #459)

The loops sampled `term-size` every 12th frame, and each sample forks `stty size` (~5ms) to answer a question that changes about once a session. `install-resize-handler!` traps SIGWINCH and raises a flag. The game loop asks `resized?` at the frame checkpoint where it already asks `interrupted?`, and `sample-size?` forks only on the signal (plus frame 0, so initial sizing is never delayed). The menu and end-screen loops do not read the flag, so they keep the frame-count `poll-size?` cadence at unchanged resize latency: a menu is static and a resize is a human-timescale event. Delivery is synchronous like SIGINT / SIGTERM, never asynchronously mid-render, per [io-boundaries](../.agnostic-ai/rules/io-boundaries.md). Without ext-pcntl the frame-count poll is the only mechanism.

## Restart modes

- `r` (restart, fresh): new PRNG seed, new level sequence.
- `R` (replay, same): reuse the captured seed, replay identical levels.

Both restart the level you died on and carry the loadout back: owned weapons, backpack stack, gun in hand (`retry-loadout`). It is the rack you ENTERED the level with, not the one you died holding. Weapon-pickup cells are drawn from the run PRNG before the ammo boxes, so rebuilding with a weapon grabbed during the fatal attempt would shift every later spawn, and `R` would no longer replay an identical level. A weapon picked up on that attempt is back on the floor where it was. Ammo does not carry: mags and reserves come back fresh from `build-world`. Kills, time and lives reset, so a retry is a fresh attempt, not a checkpoint.

Lets the player practice a tough spawn or die-on level. See [input.md](input.md) for key flow and [rendering.md](rendering.md) for render pipeline.
