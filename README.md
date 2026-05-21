# phel-doom

![phel-doom in action](docs/screenshot.png)

DOOM-lite raycaster in your terminal. Written in [Phel](https://phel-lang.org/), a Lisp that compiles to PHP. Non-trivial Phel sample: 256-color ANSI rendering, raycasting, procedural levels, FPS combat, persisted scores, WAD parser, ~5ms frame time.

## Features

- 256-color ANSI raycaster, full-terminal viewport
- 5 procedurally-generated levels, escalating difficulty
- 5 monster types (imps, demons, cacodemons, barons, cyberdemons) with distinct color, body texture, animated face glyph, aggro pulse at close range
- Hitscan combat: blood splatter, muzzle flash, 3-6s respawn cooldown
- 5 lives, i-frame window, blood-red palette flush + 1-frame white impact flash
- Walk-into-door auto-advance, heart pickups (refill life, cap 5)
- Live minimap, top-left heart HUD, bottom HUD with level/kills/fps/pos/angle
- Pause menu, end screens (death + victory) with cumulative kills + time and persisted bests
- Restart from end screen: `r` fresh seed, `R` same map sequence
- OS audio (afplay / paplay / aplay) with terminal-bell fallback
- WAD parser (header + lump directory + VERTEXES/LINEDEFS)
- Sub-5ms `frame->string` at 180×40

## Quick start

Requires PHP >= 8.4, Composer, 256-color terminal.

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

`composer install` / `composer play` also work.

## Controls

| Key            | Action               |
|----------------|----------------------|
| `w` / `s` / ↑↓ | Move forward / back  |
| `a` / `d`      | Strafe left / right  |
| `←` / `→`      | Turn left / right    |
| `space`        | Fire                 |
| `m`            | Toggle minimap       |
| `n`            | Toggle sound         |
| `p`            | Pause                |
| `q`            | Quit                 |

Walk into a door to advance. Walk over a heart to refill a life.

## Internals

Per-subsystem write-ups in [docs/](docs/README.md): architecture, game-loop, raycaster, rendering, monsters, combat, levels, input, audio, scores, WAD parser, performance.

## Layout

Functional core / imperative shell. Pure code at bottom, effects at edges, composition between.

```
src/
├── main.phel                 ; CLI entrypoint
├── commands/play.phel        ; orchestration: game-loop + end screens + lifecycle
└── modules/
    ├── core/                 ; pure, no side effects, fully testable
    │   state, map, engine, physics, combat, enemy, level
    ├── io/                   ; effects: terminal / disk / audio
    │   input, render, sound, scores, wad
    └── glue/                 ; composition: wires core + io
        controls
tests/                        ; mirrors src/, one *-test.phel per module
```

Invariants: `core/` never imports `io/` or `glue/`. `io/` may import `core/`. `glue/` may import both. Everything under `core/` is unit-testable against bare data, no fakes.

## Architecture

Per-frame transition is a pure function:

```phel
(tick-world world keys dt edges)  ; called by game-loop, also by tests
```

`game-loop` polls `stty size`, calls `render!`, sleeps 1ms, drains keys, edge-detects toggle keys, hands the world off. Render time is the throttle.

## Performance

`frame->string`: ~2ms (80×24), ~3ms (120×30), ~5ms (180×40). Hot loop uses direct PHP ops (`php/aget` etc.) over Phel polymorphic dispatch, pre-baked shade tables, run-length encoded rows, PHP-native nested arrays for the grid, alt screen buffer + cursor-home redraw.

`proj-dist` decoupled from viewport width: resizing widens FOV instead of zooming walls.

## Development

```bash
composer test     # phel tests (137 across all modules)
composer format   # auto-format
composer lint     # zero-warning policy
composer build    # out/main.php
composer repl     # REPL
```

CI runs format-check, lint, test, build on PHP 8.4 + 8.5.

## License

MIT
