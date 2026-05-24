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
| `r`            | Reload (draws from reserve) |
| `1` / `2` / `3` | Switch weapon (pistol / shotgun / chaingun) |
| `m` / `n`      | Toggle minimap / sound       |
| `p`            | Pause                        |
| `h`            | Info menu (stats, weapons table, controls) — also pauses |
| `F3`           | Debug overlay (fps, pos, perf) |
| `q`            | Quit                         |

Walk into a door to advance. Walk over pickups:

- **♥ heart** — `+1` life
- **◆ armor** — absorbs one hit (cap 3)
- **ammo box** — `+N` to a weapon's reserve (kill-loot picks a random owned weapon)
- **berserk** — 20s of `×2` damage
- **invuln** — 10s damage immunity
- **backpack** — doubles every weapon's reserve cap
- **⚿ keycard** — unlocks matching exit on L4 (blue) / L5 (red)

Weapons (DPS-balanced niches, find on map):

| Weapon | Dmg | Cd | Mag | DPS | Tier |
|---|---|---|---|---|---|
| pistol | 1 | 0.12s | 10 | 8 | L1 start (auto-fire) |
| shotgun | 3 | 0.6s | 4 | 5 | L2 pickup (single-action) |
| chaingun | 1 | 0.05s | 30 | 20 | L3 pickup (auto-fire) |

Hold space to spray with the pistol/chaingun. Shotgun needs a fresh pull per shell.

CLI:
- `--difficulty=easy|normal|hard|nightmare` (`-d`) — scales enemy speed, HP, count
- `--god` (`-g`) or `make play-dev` — no damage, GOD badge in HUD

Terminal quirks (kitty keyboard, tmux): see [docs/input.md](docs/input.md).

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
