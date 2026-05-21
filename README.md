# phel-doom

![phel-doom in action](docs/screenshot.png)

DOOM-lite raycaster in your terminal. Written in [Phel](https://phel-lang.org/), a Lisp that compiles to PHP. Non-trivial Phel sample: 256-color ANSI rendering, raycasting, procedural levels, FPS combat, persisted scores, WAD parser, ~5ms frame time.

## Features

- 256-color ANSI raycaster, full-terminal viewport
- 5 procedurally-generated levels, escalating difficulty
- 5 monster types (imps, demons, cacodemons, barons, cyberdemons) with distinct color, body texture, animated face glyph, aggro pulse + attack telegraph at close range
- Hitscan combat: blood splatter, muzzle flash, 5-stage death animation, 3-6s respawn cooldown
- Pistol with cooldown + heat / overheat jam
- 5 lives, i-frame window, directional red band on the side the hit came from, knockback shove
- Walk-into-door auto-advance, heart pickups (refill life, cap 5), armor pickups (absorb one hit)
- Compass strip, kill-streak counter, pulsing minimap door, live minimap, top-left heart + armor HUD, bottom HUD
- Pause menu, start menu, end screens (death + victory) with cumulative kills + time and persisted bests
- Restart from end screen: `r` fresh seed, `R` same map; both restart on the level you died on (victory restarts at L1)
- About-face on `e` (snap 180°)
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

| Key            | Action                       |
|----------------|------------------------------|
| `w` / `s` / ↑↓ | Move forward / back          |
| `a` / `d`      | Strafe left / right          |
| `←` / `→`      | Turn left / right            |
| `e`            | About-face (snap 180° turn)  |
| `space`        | Fire                         |
| `m`            | Toggle minimap               |
| `n`            | Toggle sound                 |
| `p`            | Pause                        |
| `q`            | Quit                         |

Walk into a door to advance. Walk over a heart to refill a life. The first thing you see is a start menu listing the controls + how-to-play; press any key to dive in (`q` exits without playing).

### Best input feel

Movement uses the [kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
when the terminal supports it: real press / release events, so motion
stops the instant you let go of WASD or arrows. Falls back to legacy
auto-repeat (~300ms post-release glide) on terminals without it.

- **Instant release**: kitty, WezTerm, Ghostty, Alacritty ≥ 0.13, iTerm2 ≥ 3.5
- **Legacy fallback**: macOS Terminal.app, GNOME Terminal, xterm
- **Inside tmux**: add `set -g extended-keys on` (and `setw -g xterm-keys on`) to pass kitty events through

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
composer test     # phel tests (230 across all modules)
composer format   # auto-format
composer lint     # static analysis (warnings allowed, errors fail)
composer build    # out/main.php
composer repl     # REPL
composer ci       # format-check + lint + test + build (full gate)
```

CI runs `composer ci` on PHP 8.5.

### Pre-commit hook

`composer install` (and `composer update`) installs a pre-commit hook
at `.githooks/pre-commit` and points `core.hooksPath` at it. The hook
runs `composer ci` before every commit, so broken or unformatted code
can't land. Bypass with `git commit --no-verify` only in genuine
emergencies.

### Test conventions

- All tests are **behavioural**: assert WHAT a fn returns, never how
  it computes. Lets internals be refactored freely.
- `composer test` sets `PHEL_DOOM_SILENT=1`, which short-circuits
  `play-sfx!` in `src/modules/io/sound.phel` so the suite never
  shells out to afplay/paplay or rings the bell. Running
  `vendor/bin/phel test` directly bypasses this — always use the
  composer script.
- One `*-test.phel` per module; mirrors `src/` layout.

### Phel gotchas (devs new to the language)

A few things that trip up newcomers, picked up the hard way:

- **PHP arrays are pass-by-value across fn boundaries.** A helper
  that does `(php/aset arr ...)` on an array passed in as an arg
  mutates a local copy; the caller never sees the writes. Either
  keep the loop in the same lexical scope (inline) OR have the
  helper own creation + return the array. See `compute-wall-shades`
  in `src/modules/io/render.phel` for the return-the-buffer pattern.
- **Destructure direction is `{:keyword local-name}`** (opposite of
  Clojure's `{local-name :keyword}`). `{:keys [foo bar]}` works too,
  but if you need to rename a key to a different local you have to
  remember the key comes first.
- **Lint doesn't macro-expand `->`** or other threading macros, so
  it emits false-positive arity errors. Stick with sequential `let`.
- **`vendor/bin/phel lint` warnings on let-binding forward refs** are
  also false positives — Phel `let` is sequential, but the linter
  treats each binding's RHS as if outer-only. Harmless; CI passes.

## License

MIT
