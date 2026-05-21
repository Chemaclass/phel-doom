# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Written in
[Phel](https://phel-lang.org/), a Lisp that compiles to PHP.
Non-trivial Phel sample: 256-color ANSI rendering, raycasting,
procedural levels, FPS combat, persisted scores, WAD parser, ~5ms
frame time.

Full feature catalogue: [docs/features.md](docs/features.md).

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
| `e`            | About-face (snap 180°)       |
| `space`        | Fire                         |
| `m`            | Toggle minimap               |
| `n`            | Toggle sound                 |
| `p`            | Pause                        |
| `q`            | Quit                         |

Walk into a door to advance. Walk over a heart to refill a life.
Press any key on the start menu to play (`q` exits).

For instant-release movement (kitty keyboard protocol, tmux setup,
terminal compatibility): see [docs/input.md](docs/input.md).

## Docs

Per-subsystem write-ups in [docs/](docs/README.md):

- [features](docs/features.md) — what the game does
- [architecture](docs/architecture.md) — module layout + dependency rules
- [game-loop](docs/game-loop.md) — per-frame state transition
- [raycaster](docs/raycaster.md) + [rendering](docs/rendering.md) — pixels on screen
- [monsters](docs/monsters.md) + [combat](docs/combat.md) — AI, damage, knockback
- [level-system](docs/level-system.md) + [map](docs/map.md) — progression + procgen
- [input](docs/input.md) + [audio](docs/audio.md) + [scores](docs/scores.md)
- [wad-parser](docs/wad-parser.md) — DOOM .wad reader
- [performance](docs/performance.md) — hot-loop optimisations
- [contributing](docs/contributing.md) — dev workflow + Phel quirks

## License

MIT
