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
| `r`            | Reload (draws from spare reserve, ~1.2s anim) |
| `1` / `2` / `3` | Switch weapon (pistol / shotgun / chaingun) |
| `m`            | Toggle minimap               |
| `n`            | Toggle sound                 |
| `p`            | Pause (full controls reference) |
| `h`            | Info menu (weapons table, inventory, run stats) |
| `F3`           | Toggle perf + technical overlay |
| `q`            | Quit                         |

Walk into a door to advance. Walk over pickups to collect:

- **Heart** `+1` life
- **Armor** absorbs one contact hit (capped at 3)
- **Ammo box** `+N` rounds to the active weapon's reserve
- **Berserk sphere** 20s of `×2` weapon damage
- **Invulnerability sphere** 10s of damage immunity
- **Backpack** doubles every weapon's reserve cap for the run
- **Keycard** `⌷` unlocks matching coloured exit on L4 / L5

Launch with `--difficulty=easy|normal|hard|nightmare` (`-d`) to scale enemy speed, HP, and count. Press any key on the start menu to play (`q` exits).

Dev god mode: `make play-dev` (or `--god` / `-g`) suppresses every contact hit so you can walk every room / test every weapon without dying. Top-left HUD adds a yellow `GOD` badge while active.

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
