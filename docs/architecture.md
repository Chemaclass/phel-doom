# Architecture

Module layout follows the **functional core / imperative shell**
pattern (Rich Hickey, Stuart Halloway). Pure code is grouped under
`core/`; side-effecting adapters under `io/`; the thin composition
layer that wires them together under `glue/`. The CLI entrypoint
lives outside the modules tree.

```
src/
├── main.phel                        ; phel.cli wiring, CLI entrypoint
├── commands/play.phel               ; outer orchestration (game-loop, run-levels)
└── modules/
    ├── core/                        ; pure, deterministic, no IO
    │   ├── state.phel               ; world + player records, gain-life, max-lives
    │   ├── map.phel                 ; grid generators, cell constants, wall? / door?
    │   ├── engine.phel              ; raycaster (cast-ray, cast-frame)
    │   ├── physics.phel             ; player rotation + translation + counter decay
    │   ├── combat.phel              ; fire-shot + damage-step + tunables
    │   ├── enemy.phel               ; spawn-enemies, advance, shoot, respawn timer
    │   └── level.phel               ; per-level catalog + build-world factory
    ├── io/                          ; effects — touch the OS
    │   ├── input.phel               ; raw STDIN, alt screen buffer
    │   ├── render.phel              ; ANSI escape composition + flush
    │   ├── sound.phel               ; afplay/paplay/aplay shell-out
    │   ├── scores.phel              ; JSON in $HOME
    │   └── wad.phel                 ; .wad file format parser
    └── glue/                        ; composition — needs both halves
        └── controls.phel            ; key bytes → world state mutations
```

## Dependency rules

- `core/` modules **may not** require `io/` or `glue/`. Anything in
  here can run against in-memory data structures in isolation.
- `io/` may require `core/`. It's how adapters speak the domain
  language.
- `glue/` may require both. It's the only place that mixes effects
  with pure logic.
- `commands/play.phel` is the top-level orchestrator. It composes
  every layer.

Why this matters: the test suite never needs a fake terminal, a fake
audio device, or a fake disk because every test imports from `core/`.
The boundary is enforceable by reading the `(:require ...)` lines.

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
              │ key bytes →   │                │ uses cast-frame │
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

The IO shell does two things: drain input from terminal stdin and
flush a frame to stdout. Everything in between is one pure function
call — `tick-world` — composed of pure helpers.

## Why this layout

- **Test cost is visible from the folder name.** Anything in `core/`
  is a unit test against a Phel map. Anything in `io/` would need a
  fake (none currently exist; the IO shell is integration-tested by
  running the binary).
- **Dependency arrows have one direction.** Easy to grep, easy to
  reason about.
- **Refactors stay local.** Changing the wall shading touches only
  `core/engine.phel` + `io/render.phel`; the rest of the codebase
  doesn't move.

See [game-loop.md](game-loop.md) for the per-frame walkthrough.
