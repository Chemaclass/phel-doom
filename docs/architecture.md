# Architecture

Pure `core/` (deterministic logic) → composition `glue/` (pure wiring) → effects `io/` (terminal/disk/audio). CLI entrypoint in `commands/` and `main.phel`.

```
src/
├── main.phel                        ; phel.cli wiring, CLI entrypoint
├── commands/play.phel               ; orchestration (game-loop, run-levels, tick-world)
├── core/                            ; pure, deterministic, no IO
│   ├── state.phel                   ; world + player maps, gain-life, max-lives
│   ├── map.phel                     ; grid generators, cell constants, wall? / door?
│   ├── engine.phel                  ; raycaster (cast-ray, cast-frame)
│   ├── physics.phel                 ; rotation + translation + counter decay + stamina
│   ├── combat.phel                  ; fire-shot + damage-step + tunables
│   ├── enemy.phel                   ; spawn-enemies, advance, shoot, respawn timer
│   ├── enemy_ai.phel                ; AI state machine (dormant/wander/aware/hunting/pain/attacking)
│   ├── enemies.phel                 ; enemy-type catalog (visuals + default HP)
│   ├── projectile.phel              ; enemy fireballs: spawn + march + player impacts
│   ├── level.phel                   ; 10-level catalog + build-world factory
│   ├── weapons.phel                 ; per-weapon stat catalog + switch/reload
│   ├── perf.phel                    ; big-screen perf-mode predicates
│   ├── rng.phel                     ; seeded PRNG (deterministic runs / demos)
│   └── difficulty.phel              ; easy/normal/hard/nightmare multipliers
├── glue/                            ; pure wiring, needs both halves
│   └── controls.phel                ; key bytes -> :moves counters + rising edges
└── io/                              ; effects, touch the OS
    ├── input.phel                   ; raw STDIN, alt screen buffer
    ├── render.phel                  ; ANSI escape composition + flush
    ├── sound.phel                   ; afplay/paplay/aplay shell-out (one-shot sfx)
    ├── ambient.phel                 ; synthesised drone loop (crash-safe bg process)
    ├── scores.phel                  ; JSON in $HOME
    ├── savegame.phel                ; mid-level save/load (tagged JSON world dump)
    ├── demo.phel                    ; record / replay input stream + seed
    └── wad.phel                     ; .wad file format parser
```

## Dependency rules

- `core/` may not require `io/` or `glue/`. Runs against in-memory data in isolation.
- `io/` may require `core/`. Adapters speak the domain language.
- `glue/` may require both. Only place that mixes effects with pure logic.
- `commands/play.phel` is the top-level orchestrator. Composes every layer.

Tests never need a fake terminal, audio device, or disk: all tests import from `core/`. Boundary is enforceable by reading `(:require ...)` lines.

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

See [game-loop.md](game-loop.md) for the full step table.

IO shell does two things: drain input from stdin, flush a frame to stdout. Everything between is one pure `tick-world` call.

## Why this layout

- Test cost visible from folder name. `core/` = unit test against a Phel map. `io/` integration-tested by running the binary.
- Dependency arrows point one way. Easy to grep + reason about.
- Refactors stay local. Wall-shade tweak touches only `core/engine.phel` + `io/render.phel`.
