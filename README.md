# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Pure [Phel](https://phel-lang.org/) (Lisp on PHP). 256-color ANSI, 10 procgen levels, FPS combat, ~5ms frame.

Feature list: [docs/features.md](docs/features.md).

## Quick start

Needs PHP >= 8.4, Composer, 256-color terminal.

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

`composer install` / `composer play` also work.

<details>
<summary><strong>No PHP locally? Run it in Docker</strong></summary>

The repo ships a `Dockerfile` (PHP 8.4 CLI + Composer + deps). `docker` is the only prerequisite.

```bash
make docker-build      # build image (~195MB)
make docker-play       # launch game with raw TTY
make docker-test       # run test suite headless
make docker-shell      # bash inside the image
make docker-clean      # remove local image
```

Each target is a one-line `docker run --rm` wrapper. Override tag with `DOCKER_IMG=...`. Host-PHP targets stay the inner-loop default; Docker adds ~1s startup per command. Rebuild after `composer.json` edits.

Custom invocations:

```bash
docker run --rm -it phel-doom run phel-doom.main play --god --level=10
docker run --rm -it -v "$PWD:/app" phel-doom    # live-mount for edits
```

</details>

## Controls

| Key            | Action                       |
|----------------|------------------------------|
| `w` / `s` / ↑↓ | Move forward / back          |
| `a` / `d`      | Strafe left / right          |
| `←` / `→`      | Turn left / right            |
| `SHIFT` / `x`  | Sprint (1.6× speed, drains stamina) |
| `e`            | About-face (snap 180°)       |
| `space`        | Fire                         |
| `r`            | Reload (draws from reserve) |
| `1` / `2` / `3` | Switch weapon (pistol / shotgun / chaingun) |
| `m` / `n`      | Toggle minimap / sound       |
| `p`            | Pause                        |
| `h` / `ESC`    | Info menu (stats + weapons + controls; also pauses) |
| `F3`           | Debug overlay (fps, pos, perf) |
| `q`            | Quit                         |

Walk into a door to advance. Walk over pickups:

- **♥ heart** - `+1` life
- **◆ armor** - absorbs one hit (cap 5)
- **armor shard** - `+1` armor over cap, up to 10 (no decay)
- **soulsphere** - `+1` life over cap; decays back to cap over time
- **ammo box** - `+N` to a weapon's reserve. Kill-loot tags a random non-pistol weapon you own
- **berserk** - 20s of `×2` damage
- **invuln** - 10s damage immunity
- **backpack** - stacks reserve cap (each pickup adds a tier)
- **⚿ keycard** - unlocks matching exit on L4 (blue) / L5 (red); L10 boss-locked

Compass top-centre tints one cardinal letter (E/S/W/N) toward your next target - **orange** = exit door, **blue / red** = keycard you need. Play in 3D without checking the 2D map.

Weapons (DPS-balanced niches, find on map):

| Slot | Weapon | Dmg | Cd | Mag | DPS | Tier |
|---|---|---|---|---|---|---|
| 1 | pistol | 1 | 0.12s | 10 | 8 | L1 start (auto-fire, overheats) |
| 2 | shotgun | 3 | 0.6s | 4 | 5 | L2 pickup (single-action) |
| 3 | chaingun | 1 | 0.05s | 30 | 20 | L3 pickup (auto-fire) |
| 4 | chainsaw | 1 | 0.10s | ∞ | 10 | melee (1.5 cell range, slows you to half speed) |

Hold space to spray with pistol/chaingun/chainsaw. Shotgun needs a fresh pull per shell.

CLI:
- `--difficulty=easy|normal|hard|nightmare` (`-d`) - scales enemy speed, HP, count
- `--level=N` (`-l`) - start at level N (clamped)
- `--god` (`-g`), `--armory` (`-a`), `--full-map` (`-f`) - dev flags

Terminal quirks (kitty keyboard, tmux): [docs/input.md](docs/input.md).

## Docs

[docs/](docs/README.md) - per-subsystem write-ups.

## License

MIT
