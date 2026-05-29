# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Pure [Phel](https://phel-lang.org/) (Lisp on PHP). 256-color ANSI, 10 procgen levels, FPS combat, ~5ms frame. Full feature list: [docs/features.md](docs/features.md).

## Quick start

Needs PHP >= 8.4, Composer, 256-color terminal.

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

Or `composer install && composer play`.

### Docker

No PHP? Run in Docker: PHP 8.5 CLI + Composer + deps in an image. `docker` is the only prerequisite.

```bash
make docker-build      # build image
make docker-play       # launch game (raw TTY)
make docker-test       # run test suite
make docker-shell      # bash inside container
make docker-clean      # remove image
```

Override tag: `DOCKER_IMG=mytag make docker-build`. Host PHP is the inner loop; Docker adds ~1s startup.

## Controls

| Key            | Action                       |
|---|---|
| `w` / `s` / ↑↓ | Forward / back               |
| `a` / `d`      | Strafe left / right          |
| `←` / `→`      | Turn left / right            |
| `SHIFT` / `x`  | Sprint (1.6× speed)          |
| `e`            | About-face (180°)            |
| `space`        | Fire                         |
| `r`            | Reload                       |
| `1` / `2` / `3` | Switch weapon                |
| `m` / `n`      | Minimap / sound toggle       |
| `p`            | Pause                        |
| `h` / `ESC`    | Info menu + pause            |
| `F3`           | Debug overlay                |
| `q`            | Quit                         |

Walk into doors to advance. Pickups:

- **♥ heart**: `+1` life
- **◆ armor**: absorbs one hit (cap 5)
- **armor shard**: `+1` armor over 5, up to 10
- **soulsphere**: `+1` life over cap, decays back
- **ammo box**: `+N` to weapon reserve
- **berserk**: 20s of `×2` damage
- **invuln**: 10s immunity
- **backpack**: increases reserve cap
- **⚿ keycard**: unlocks L4 (blue) / L5 (red) exits; L10 boss-locked

Compass at top-centre: tints the cardinal letter (E/S/W/N) toward your target. Orange = exit, blue/red = keycard needed.

Weapons (DPS-balanced, found on map):

| Slot | Weapon | Dmg | CD | Mag | DPS |
|---|---|---|---|---|---|
| 1 | pistol | 1 | 0.12s | 10 | 8 |
| 2 | shotgun | 3 | 0.6s | 4 | 5 |
| 3 | chaingun | 1 | 0.05s | 30 | 20 |
| 4 | chainsaw | 1 | 0.10s | ∞ | 10 |

Hold space to spray (pistol / chaingun / chainsaw). Shotgun: one pull per shell.

CLI flags:

- `--difficulty=easy|normal|hard|nightmare` (`-d`) - scales enemy speed, HP, count
- `--level=N` (`-l`) - start at level N
- `--god` (`-g`), `--armory` (`-a`), `--full-map` (`-f`) - dev flags

Terminal quirks (kitty, tmux): [docs/input.md](docs/input.md).

## Internals

[docs/README.md](docs/README.md) - per-subsystem guide.

## License

MIT
