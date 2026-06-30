# Architecture

Pure `core/` (deterministic logic) → composition `glue/` (pure wiring) → effects `io/` (terminal/disk/audio). CLI entrypoint in `commands/` and `main.phel`.

```
src/
├── main.phel                        ; phel.cli wiring, CLI entrypoint
├── commands/play.phel               ; orchestration (game-loop, run-levels, tick-world)
├── commands/demo.phel               ; tech-talk showcase command
├── demo/phases.phel                 ; per-phase world->world transform
├── core/                            ; pure, deterministic, no IO
│   ├── state.phel                   ; world + player maps, gain-life, max-lives
│   ├── map.phel                     ; grid generators, cell constants, wall? / door?
│   ├── engine.phel                  ; raycaster (cast-ray, cast-frame)
│   ├── physics.phel                 ; rotation + translation + counter decay + stamina
│   ├── combat.phel                  ; fire-shot + damage-step + timers
│   ├── loot.phel                    ; kill-loot drop economy (ammo / armor / heart)
│   ├── enemy.phel                   ; spawn, step, shoot, respawn timer
│   ├── enemy_ai.phel                ; AI state machine
│   ├── enemies.phel                 ; enemy-type catalog
│   ├── projectile.phel              ; enemy fireballs: spawn + march + impacts
│   ├── level.phel                   ; level catalog + build-world factory
│   ├── weapons.phel                 ; per-weapon stats + switch/reload
│   ├── pickups.phel                 ; step-on item rules (hearts, ammo, keys, weapons)
│   ├── format.phel                  ; render format helpers
│   ├── settings.phel                ; difficulty + volume + minimap settings
│   ├── perf.phel                    ; frame cadence + render-scale (uniform)
│   ├── rng.phel                     ; seeded PRNG
│   ├── difficulty.phel              ; easy/normal/hard/nightmare multipliers
│   └── version.phel                 ; version string
├── glue/controls.phel               ; key bytes -> :moves counters + rising edges
└── io/                              ; effects, touch the OS
    ├── input.phel                   ; STDIN setup + drain
    ├── render.phel + submodules      ; ANSI emit + layout
    ├── sound.phel                   ; sfx shell-out
    ├── music.phel                   ; OST loop process
    ├── scores.phel                  ; JSON high-score file
    ├── settings.phel                ; settings JSON persist
    ├── savegame.phel                ; mid-level save/load
    ├── demo.phel                    ; record / replay harness
    └── wad.phel                     ; .wad parser
```

## Dependency rules

- `core/` - pure, no `io/` or `glue/`. Runs on maps.
- `glue/` - pure wiring, may require `core/`. No IO.
- `io/` - effects, may require `core/` + `glue/`.
- `commands/play.phel` - top-level orchestrator. Composes all three.

Tests only import from `core/` so no terminal, disk, or audio mocking needed. Enforceable via `(:require ...)` inspection.

## Data flow per frame

```
                ┌─────────────────────────────────────────────┐
                │  commands/play.phel (game-loop)              │
                └─────┬─────────────────────────────────┬──────┘
                      │                                 │
            drains keys (io/input)             renders frame (io/render)
                      │                                 ▲
                      ▼                                 │
              ┌───────────────┐                ┌────────┴────────┐
              │ glue/controls │                │ frame->string   │
              │ key bytes ->  │                │ uses cast-frame │
              │ counters      │                │ (core/engine)   │
              └───────┬───────┘                └────────▲────────┘
                      │                                 │
                      ▼                                 │
              ┌───────────────────────────────┐         │
              │ tick-world  (commands/play)   │─────────┘
              │ pure orchestration. Per frame:│
              │   handle-toggles              │
              │   refresh-from-keys (glue)    │
              │   weapon swap / reveal-secret │
              │   toggle-switch / mark-vis    │
              │   tick-stamina + apply-physics│
              │   pickup-* (hearts, armor,    │
              │     shards, ammo, berserk,    │
              │     invuln, soul, backpack,   │
              │     keycards, weapon-pickups) │
              │   tick-enemies                │
              │   tick-projectiles / reload   │
              │   tick-armory / tick-shooting │
              │   damage-step + horror layer  │
              │   decay-soul-overcap          │
              └───────────────────────────────┘
```

See [game-loop.md](game-loop.md) for the full tick-world step table. Game-loop: read input -> pure tick-world -> render. Two IO boundaries only: drain stdin, flush stdout.

## Why this layout

- Test cost visible from folder: `core/` = unit tests (pure maps), `io/` = integration tests (run binary).
- Dependency arrows point one way: no cycles, easy to grep.
- Refactors stay local: wall-shade tweak touches `core/engine.phel` + `io/render.phel` only.
