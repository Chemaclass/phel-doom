# Player guide

Full controls, pickups, weapons, and CLI flags. The README keeps a short
version; this page is the complete reference.

## Controls

| Key            | Action                                  |
|---|---|
| `w` / `s` / ↑↓ | Forward / back                          |
| `a` / `d`      | Strafe left / right                     |
| `←` / `→`      | Turn left / right                       |
| `SHIFT` / `x`  | Sprint (1.6x speed)                     |
| `e`            | About-face (180 degrees)                |
| `space`        | Fire (hold to spray auto-fire weapons)  |
| `r`            | Reload                                   |
| `f`            | Use: reveal secret / toggle switch      |
| `1`...`8`      | Switch weapon                           |
| `m`            | Minimap toggle                          |
| `n`            | Sound toggle                            |
| `p`            | Pause + settings                        |
| `h` / `ESC`    | Info menu + pause                       |
| `F3`           | Debug overlay                           |
| `F5` / `F9`    | Save / load                             |
| `q`            | Quit                                    |

Walk into doors to advance.

Compass at top-centre tints the cardinal letter (E/S/W/N) toward your
target. Orange = exit, blue/red = keycard needed.

Terminal quirks (kitty, tmux): [input.md](input.md).

## Pickups

- **heart**: `+1` life
- **armor**: absorbs one hit (cap 5)
- **armor shard**: `+1` armor over 5, up to 10
- **soulsphere**: `+1` life over cap, decays back
- **ammo box**: `+N` to weapon reserve
- **berserk**: full heal + 20s melee surge (chainsaw `x6`, guns `x2`)
- **invuln**: 10s immunity
- **backpack**: increases reserve cap
- **keycard**: unlocks L4 (blue) / L5 (red) exits; L10 is boss-locked

## Weapons

DPS-balanced niches rather than monotonic upgrades; weapons are found on
the map and selected with keys `1`...`8`.

| Key | Weapon | Dmg | CD | Mag | DPS | Type / niche |
|---|---|---|---|---|---|---|
| 1 | pistol | 1 | 0.12s | 10 | 8 | ballistic, fallback; pierces the whole line |
| 2 | shotgun | 3 | 0.6s | 4 | 5 | ballistic; cone graze (primary + 2 neighbours) |
| 3 | chaingun | 1 | 0.05s | 30 | 20 | ballistic, sustained single-target |
| 4 | chainsaw | 1 | 0.10s | inf | 10 | melee, no ammo |
| 5 | BFG | 10 + 6 splash (r3.0) | 1.2s | 1 | - | plasma, AoE (ignores fire-resist) |
| 6 | incinerator | 1 | 0.06s | 40 | 16 | fire, swarm-clearer (caco/baron/archvile/mancubus resist) |
| 7 | rocket launcher | 4 + 3 splash (r2.0) | 0.9s | 1 | - | ballistic, mid-tier AoE (cheaper than BFG) |
| 8 | super shotgun | 5 + 2 graze | 0.9s | 2 | - | ballistic, short-range tank-killer (wide cone) |

Hold `space` to spray auto-fire weapons (pistol / chaingun / chainsaw /
incinerator). Shotgun, super shotgun, BFG, and rocket launcher fire one
shot per pull.

## CLI flags

- `--difficulty=easy|normal|hard|nightmare` (`-d`) - scales enemy speed, HP, count
- `--level=N` (`-l`) - start at level N
- `--god` (`-g`), `--armory` (`-a`), `--full-map` (`-f`) - dev flags
