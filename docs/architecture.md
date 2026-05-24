# Architecture

Pure `core/` (deterministic logic) → composition `glue/` (pure wiring) → effects `io/` (terminal/disk/audio). CLI entrypoint in `commands/` and `main.phel`.

```
src/
├── main.phel                        ; phel.cli wiring, CLI entrypoint
├── commands/play.phel               ; outer orchestration (game-loop, run-levels)
└── modules/
    ├── core/                        ; pure, deterministic, no IO
    │   ├── state.phel               ; world + player maps, gain-life, max-lives
    │   ├── map.phel                 ; grid generators, cell constants, wall? / door?
    │   ├── engine.phel              ; raycaster (cast-ray, cast-frame)
    │   ├── physics.phel             ; player rotation + translation + counter decay
    │   ├── combat.phel              ; fire-shot + damage-step + tunables
    │   ├── enemy.phel               ; spawn-enemies, advance, shoot, respawn timer
    │   ├── level.phel               ; per-level catalog + build-world factory
    │   ├── weapons.phel             ; per-weapon stat catalog + switch/reload
    │   └── difficulty.phel          ; per-difficulty scaling (speed, HP, count)
    ├── io/                          ; effects, touch the OS
    │   ├── input.phel               ; raw STDIN, alt screen buffer
    │   ├── render.phel              ; ANSI escape composition + flush
    │   ├── sound.phel               ; afplay/paplay/aplay shell-out
    │   ├── scores.phel              ; JSON in $HOME
    │   └── wad.phel                 ; .wad file format parser
    └── glue/                        ; composition, needs both halves
        └── controls.phel            ; key bytes -> world state mutations
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
              │ pure orchestration:           │
              │   handle-toggles              │
              │   refresh-from-keys (glue)    │
              │   apply-physics    (core)     │
              │   pickup-hearts    (core)     │
              │   tick-enemies     (core)     │
              │   tick-shooting    (core)     │
              │   damage-step      (core)     │
              └───────────────────────────────┘
```

IO shell does two things: drain input from stdin, flush a frame to stdout. Everything between is one pure call, `tick-world`, composed of pure helpers.

## Why this layout

- Test cost visible from folder name. `core/` = unit test against a Phel map. `io/` would need a fake (none exist; IO shell is integration-tested by running the binary).
- Dependency arrows point one direction. Easy to grep, easy to reason about.
- Refactors stay local. Changing wall shading touches only `core/engine.phel` + `io/render.phel`.

See [game-loop.md](game-loop.md) for the per-frame walkthrough.
