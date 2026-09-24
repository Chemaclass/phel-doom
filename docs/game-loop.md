# Game loop

An IO shell around a pure per-frame transition, in `src/commands/play.phel`. The loop shape is: input, `tick-world` (pure), cast and render (io).

## Lifecycle layers

1. **`run-play`**: reads CLI options and settings, arms signal handlers, enters raw mode, runs the start menu and the run. Teardown runs in a `finally` (see [input.md](input.md#teardown-and-signals)). Settings and scores write failures are reported after teardown, on the cooked terminal.
2. **`show-start-menu!`**: polls until the player starts (`Enter` / `Space`), opens settings (`s`) or quits (`q`, Ctrl-C). Redraws every frame, so a resize repaints cleanly. `--demo` replay skips it.
3. **`run-levels`**: the level chain. Carries lives, kills, time, run stats, backpack, owned weapons, the active weapon with per-weapon ammo, the minimap and sound toggles, and live settings. Stamina does not carry: each level starts with a full pool.
4. **`game-loop`**: one level. Returns a result kind (below).

## One frame of `game-loop`

1. **Size.** Ask `resized?` (SIGWINCH), then fork `stty size` only when `sample-size?` says so. `cap-dims` applies `--max-cols` / `--max-rows`. `redraw-if-resized` clears the screen on a size change.
2. **Re-arm mouse** on a resize or every 120th frame, when the Mouse setting is on ([input.md](input.md#re-arming-mouse-reporting-issue-288)).
3. **Render.** `draw-frame` calls `render!` with `frame-stats`, the render DTO. `adaptive-sleep!` fills the rest of the frame budget. `next-cal` feeds the measured render time to auto calibration.
4. **Input.** `drain-keys`, then `dt` from `ms-since` clamped by `clamp-frame-ms`. Under `--demo` / `--record`, `demo/resolve-frame!` swaps in or taps the recorded keys and ms (#64).
5. **Edges.** `key-states` and `rising-edges`. `mouse-aim` and `wheel-weapon-step` read the same string; a left click ORs into `:fire` / `:fire-held`, the wheel into `:next-weapon` / `:prev-weapon`.
6. **Quit check.** A replay out of frames, a confirmed `q` (`quit-confirmed?`) or `interrupted?` returns `:quit`. `interrupted?` is also where pending signals dispatch. Quitting from the pause page saves settings.
7. **Tick.** Stamp `:scene-rows` / `:scene-cols` so the hitscan gates project against the exact view drawn. `reset-reticle`, then `apply-mouse-look` (unpaused only), then `tick-world`.
8. **Menus.** While paused outside the help panel, drive the pause menu (`step-pause-menu`) or the settings sub-page (`step-settings!`). See [settings.md](settings.md#access).
9. **Save / load.** `handle-save-load` runs F5 / F9 here, outside the pure tick ([savegame.md](savegame.md)).
10. **Effects.** Save settings when the pause page closes. Drain `:sfx` through `io/sound`, plus the heartbeat thump and the silence cue, all gated on `:sound-on`. Start or stop the OST when `:sound-on` flips; SIGSTOP / resume it when `:paused` flips.
11. **Branch.** Pause-menu quit or restart, death, door, or `recur`.

The recur threads `world`, timing, the key snapshot, `[rows cols]`, calibration state, the pointer position and the poll counter.

## tick-world

Pure one-frame transition: `(tick-world world keys dt edges)` returns the next world. The game loop and the tests call it the same way.

It first applies `handle-toggles` (focus loss, quit request, pause, minimap, sound, debug, help, about-face) and resets `:sfx` to `[]`. Toggles run before the pause check, so `P`, `H`, `Esc` and `F3` work while paused. Then:

1. Paused: return.
2. `:hit-stop-secs` > 0 (a heavy kill): decay it and return. The frozen frame holds the muzzle flash and blood.
3. Otherwise run the pipeline:

| Step | What | Module |
|------|------|--------|
| `refresh-from-keys` | Refresh `:moves` hold counters | `glue/controls` |
| `switch-weapon` / `cycle-weapon` | `1`-`7`, then `[` `]` / wheel. No-op mid-reload. A swap that took names the weapon on the message line. | `core/weapons` |
| `note-hint-progress` | Retire the first-run key hints once the player moved, turned and fired (#467) | `core/state` |
| `try-reveal-secret` / `try-toggle-switch` | `F` on the cell ahead. Secret first, so one press never does both. | `commands/play` |
| `mark-visible-cells` | Stamp line-of-sight cells onto `:visited` (minimap fog) | `core/engine` |
| `tick-stamina`, `apply-physics` | Stamina first, so the frame the pool empties already walks at base speed. Then rotate, pitch, translate, bob, decay counters. | `core/physics` |
| `tick-pickups` | All step-on pickups in one pass | `core/pickups` |
| `tick-enemies` | `enemy/advance` plus one wake growl for the nearest enemy that woke this frame (#460). Respawns stop once the boss is down. | `commands/play` |
| `tick-projectiles`, `tick-tracers` | Spawn and march bolts, resolve player hits before contact damage | `core/projectile` |
| `reload` | `R` edge | `core/combat` |
| `tick-armory` | `--armory` ammo refill | `core/combat` |
| `tick-shooting` | Fire edge: hitscan, empty-mag click | `core/combat` |
| `damage-step` | Decay timers, apply contact damage | `core/combat` |
| READY flash | `:reload-ready-secs` on the frame the reload cooldown ends | `commands/play` |
| `tick-heartbeat` | Low-health heartbeat | `core/physics` |
| `tick-scare` | Proximity `:silence-tick?` audio cue | `core/enemy` |
| `tick-blood-drops` | Screen-edge drips | `core/physics` |
| `decay-soul-overcap` | Soulsphere over-cap HP decay | `core/state` |
| HUD timers | Decay `:save-flash-secs`, `:reload-ready-secs` | `commands/play` |
| `advance-game-time` | Add `dt` to the pause-aware `:game-time` | `core/state` |

`tick-world` does no IO. Every cue goes onto `:sfx` as `{:name :vol}` via `push-sfx`, and the loop plays them after the tick. So tests can run whole frame sequences with no side effects. See [audio.md](audio.md).

Physics details (collision in `physics/try-move`, the `:bob-phase` walk cycle) are in [state.md](state.md#the-player).

## Frame timing

- **120 fps target.** `target-frame-us` returns 8333 µs at every size. It is a ceiling: `adaptive-sleep!` sleeps the remainder, floored at `min-yield-us` (1 ms), so a slow frame degrades smoothly toward render speed.
- **Clamped `dt`.** `clamp-frame-ms` caps a frame at `max-frame-ms` (100 ms, a ~10 fps floor) before it becomes `dt` (#278). One stall cannot tunnel the player through a 1-thick wall in the unswept physics step or drain every timer at once. Real frames sit well under the cap.
- **`ms-since`** tags its arguments `^float` so Phel does not infer `int` from `* 1000` and truncate microtime values.
- **One `dt` per frame** for physics, AI and decay, so a frame's simulation stays consistent.
- **Menu loops** (start, settings, intermission, end screens) sleep a flat `menu-frame-us` (16 ms, ~60 fps).

### Render size and auto pixel scale

`cap-dims` (`core/perf`) shrinks the render area to `--max-cols` / `--max-rows`, leaving a blank border. Caps never grow past the terminal.

With neither flag set (`opt-int` returns -1), auto mode fills the terminal and picks the detail level. The first `auto-cal-frames` (5) frames render at full detail under the intro splash; `next-cal` keeps the minimum render time, then `auto-pixel-scale` locks scale 1 (full detail) or 2 (pixel-doubled: half resolution, each scene cell painted as a 2x2 block, ~4x cheaper, same FOV). Scale 2 is only possible on a big screen (area beyond 200x45, `perf/big-screen?`). The measured time includes the terminal write, so the choice tracks real smoothness. A size change recalibrates. An explicit flag, even `0` (fill), opts out. See [performance.md](performance.md).

## Resize: SIGWINCH, not polling (issue #459)

Each `term-size` sample forks `stty size`, about 5 ms on an 8.3 ms budget, to answer a question that changes about once a session. `install-resize-handler!` traps SIGWINCH and raises a flag.

- The game loop asks `resized?` every frame, at the checkpoint where it already asks `interrupted?`. `sample-size?` forks only on the signal, plus frame 0 so initial sizing is never late.
- The menu and end-screen loops do not read the flag. They keep `poll-size?`: frame 0, then every `resize-poll-frames` (12) frames, about 200 ms at their ~60 fps. A static screen can afford it.
- Without ext-pcntl, the game loop falls back to the same frame-count poll (~100 ms at 120 fps).

Delivery is synchronous, never mid-render, per [io-boundaries](../.agnostic-ai/rules/io-boundaries.md).

## Per-level result kinds

```phel
:quit                           ; confirmed q, pause-menu Quit, Ctrl-C, or replay end
:restart                        ; pause-menu Restart (asked twice)
{:game-over true ...}           ; lives reached 0
{:victory true ...}             ; stepped on the exit of the last level (L10)
{:next-level true :level N ...} ; stepped on any earlier exit
```

`run-levels` branches on them:

- `:next-level`: show the intermission card, then build the next level with the carried state.
- `:victory` / `:game-over`: update the scores file, show the end screen with the run summary ([scores.md](scores.md)).
- `:restart`: level 1, fresh seed, fresh loadout.

## Run transitions (issue #470)

- **Death beat.** `death-beat!` holds the killing frame 0.6 s, then drains input typed during it, so a panicked key cannot select anything on the death screen.
- **Intermission.** `intermission-loop` shows a card for the cleared level: its kills, secrets and time. Any key continues; `q` and Ctrl-C quit.

Both are skipped under `--demo` replay: nothing is watching, and waiting for input would desync the recording.

## Quitting and restarting (issue #454)

`q` in a live run does not quit. `arm-quit-menu` opens the pause menu with the cursor on Quit and zeroes the hold counters, so the second `q` (or Enter on that row) confirms. `quit-confirmed?` is the one gate: true on the pause page, false in the `H` / `Esc` help panel. The help panel freezes the world too, but it has no Quit row and `Esc` is the universal back-out key, so `q` there arms the menu like a live run does. Holding `q` on a legacy terminal reaches the quit through key repeat; a held key is not an accident.

The start menu, intermission and end screens run their own loops and quit on one `q`. Ctrl-C quits from anywhere.

Restart on the pause menu asks twice: the first select arms it (`Restart?  enter again`), a second fires it, and moving the cursor disarms it. The armed flag is never saved; resume and re-pause clear it.

Losing terminal focus pauses a live run and drops held movement ([input.md](input.md#focus-tracking-issue-454)).

## Restart modes

The end screen offers `r` (fresh seed) and `R` (same seed); `q` quits.

- **After death**, both retry the level you died on. `R` reuses that level's seed, so it rebuilds the identical level.
- **After victory**, both restart at level 1 with the starting loadout. `R` passes the last level's seed, so it is not a replay of the run.

A death retry carries the loadout you ENTERED the level with (`retry-loadout`, #453): owned weapons, backpack stack and the gun in hand. Not the rack you died holding, because weapon-pickup cells are drawn from the run PRNG before the ammo boxes; one more owned weapon shifts every later spawn and breaks `R`. A weapon picked up on the fatal attempt is back on the floor. Ammo does not carry: mags and reserves come fresh from `build-world`. Kills, time and lives reset, so a retry is a fresh attempt, not a checkpoint.
