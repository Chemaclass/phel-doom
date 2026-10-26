# Architecture

`core/` contains deterministic logic, `glue/` contains pure wiring, and `io/` handles terminal, disk and audio effects. `io/` may depend on `glue/` and `core/`; `glue/` may depend on `core/`. The CLI entry point is `main.phel`; `commands/` orchestrates the layers.

```
src/
├── main.phel                 ; phel.cli wiring: play + demo commands
├── commands/
│   ├── play.phel             ; orchestration: game-loop, run-levels, tick-world
│   └── demo.phel             ; tech-talk showcase command
├── demo/phases.phel          ; per-phase world -> world transform
├── core/                     ; pure, deterministic, no IO
│   ├── state.phel            ; world + player maps, lives
│   ├── map.phel              ; grid generators, cell constants, wall? / door?
│   ├── engine.phel           ; raycaster (cast-ray, cast-frame), line of sight
│   ├── projection.phel       ; vertical projection, pitch + bob shear
│   ├── light.phel            ; per-cell room lighting bias
│   ├── physics.phel          ; rotation, translation, counter decay, stamina
│   ├── combat.phel           ; fire-shot, damage-step, timers, sfx queue
│   ├── loot.phel             ; kill-loot drops (ammo, armor, hearts)
│   ├── enemy.phel            ; spawn, step, shoot, respawn timer
│   ├── enemy_ai.phel         ; AI state machine
│   ├── enemies.phel          ; enemy-type catalog
│   ├── projectile.phel       ; enemy fireballs: spawn, march, impacts
│   ├── level.phel            ; level catalog + build-world
│   ├── weapons.phel          ; per-weapon stats, switch, reload
│   ├── pickups.phel          ; step-on items (hearts, ammo, keys, weapons)
│   ├── format.phel           ; render format helpers
│   ├── settings.phel         ; options model (difficulty, volume, view)
│   ├── perf.phel             ; frame cadence + render scale
│   ├── rng.phel              ; seeded PRNG
│   ├── difficulty.phel       ; easy / normal / hard / nightmare multipliers
│   └── version.phel          ; version string
├── glue/controls.phel        ; key bytes -> :moves counters + rising edges
└── io/                       ; effects, touch the OS
    ├── input.phel            ; stdin setup + drain, terminal restore, signals
    ├── render.phel           ; facade over render/ (main = per-frame scene,
    │                         ;   screens = full-screen overlays, hud, paint, sprites)
    ├── sound.phel            ; sfx sidecar shell-out
    ├── sound_data.phel       ; baked Freedoom sounds (generated)
    ├── music.phel            ; OST loop process
    ├── scores.phel           ; JSON high-score file
    ├── settings.phel         ; settings JSON persistence
    ├── savegame.phel         ; save / load
    ├── demo.phel             ; record / replay harness
    └── wad.phel              ; .wad parser
```

## Dependency rules

- `core/` references only `core/`. Runs on maps.
- `glue/` may require `core/`. No IO.
- `demo/` may require `core/` and `glue/`. No IO.
- `io/` may require `core/` and `glue/`, never `commands/` or `main`.
- `commands/` composes all layers.

`composer check-layers` (`tools/check-layers.sh`) enforces these rules in `composer ci`.

## Data flow per frame

```
   commands/play (game-loop)
        │
        ├─ drain stdin (io/input)
        ▼
   glue/controls: key bytes -> move counters + edges
        ▼
   tick-world (pure): toggles, physics, pickups, enemies,
                      projectiles, shooting, damage, sfx queue
        ▼
   play queued sfx (io/sound), write frame (io/render,
   uses core/engine cast-frame)
```

The loop reads input, runs the pure `tick-world`, then renders. IO happens around the tick. See [game-loop.md](game-loop.md) for each step.

## Why this layout

- `core/` tests run on hand-built maps. `io/` tests cover the pure parts of effect modules and golden frame bytes.
- Dependencies point one way. `composer check-cycles` checks for cycles, and the layout makes them easy to search.
