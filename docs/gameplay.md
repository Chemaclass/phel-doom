# Player guide

Full controls, pickups, weapons, and CLI flags. The README has the short version.

## Controls

| Key | Action |
|---|---|
| `w` / `s` / ↑↓ | Forward / back |
| `a` / `d` | Strafe left / right |
| `←` / `→` | Turn left / right |
| `SHIFT` / `x` | Sprint (1.6x speed) |
| `e` | About-face (180 degrees) |
| `space` | Fire (hold to spray auto-fire) |
| `r` | Reload |
| `f` | Use: reveal secret, toggle switch |
| `1`-`8` | Switch weapon |
| `m` | Minimap toggle |
| `n` | Sound toggle |
| `p` | Pause + settings |
| `h` / `ESC` | Info menu + pause |
| `F3` | Debug overlay |
| `F5` / `F9` | Save / load (slot 1) |
| `q` | Quit |

Walk into doors to advance. Top-center compass tints the cardinal (E/S/W/N) toward target. Orange = exit. Blue/red = keycard needed.

Terminal quirks (kitty, tmux): [input.md](input.md).

## Pickups

- **heart**: plus 1 life
- **armor**: absorbs one hit (cap 5)
- **armor shard**: plus 1 armor over cap 5, up to 10 total
- **soulsphere**: boost to 7 lives (max 10), over-cap decays back over 5 seconds
- **ammo box**: plus N to active weapon reserve
- **berserk**: full heal plus 18s melee surge (chainsaw 6x, guns 2x)
- **invuln**: 10s damage immunity
- **backpack**: increases reserve cap by one base (stacks 3 times)
- **keycard**: blue unlocks L4 exit, red unlocks L5, yellow unlocks L7. L10 boss-locked

## Weapons

DPS-balanced niches, not monotonic upgrades. Found on the map, selected with keys 1-8.

| Key | Weapon | Dmg | CD | Mag | DPS | Type / niche |
|---|---|---|---|---|---|---|
| 1 | pistol | 1 | 0.12s | 10 | 8 | ballistic fallback; pierces line |
| 2 | shotgun | 3 | 0.6s | 4 | 5 | ballistic cone (primary + 2 graze) |
| 3 | chaingun | 1 | 0.05s | 30 | 20 | ballistic sustained |
| 4 | chainsaw | 1 | 0.10s | inf | 10 | melee no-ammo |
| 5 | BFG | 10 + 6 splash (r3.0) | 1.2s | 1 | - | plasma AoE |
| 6 | incinerator | 1 | 0.06s | 40 | 16 | fire swarm-clearer (fire-resist enemies) |
| 7 | rocket | 4 + 3 splash (r2.0) | 0.9s | 1 | - | ballistic mid-tier AoE |

Hold `space` for auto-fire on pistol/chaingun/chainsaw/incinerator. Shotgun, BFG, rocket fire one shot per pull.

## End screen (rank + summary)

Death and victory both show a run summary: cumulative kills + time, **accuracy %** (connecting trigger pulls / total pulls), **secrets** found/total, and a letter **rank** S/A/B/C/D from `0.7*accuracy + 0.3*secrets`. The rank is colour-coded (gold S down to dim D). Persisted bests show below it. See [scores.md](scores.md) for the exact grade formula and the "what counts as a hit" rule (pierce / cone / AoE).

## CLI flags

- `--difficulty=easy|normal|hard|nightmare` (`-d`) - scale enemy speed, HP, count, ammo-box budget, heal/armor pickup counts
- `--level=N` (`-l`) - start at level N
- `--god` (`-g`) - invincible
- `--armory` (`-a`) - start with all weapons
- `--full-map` (`-f`) - reveal map
- `--max-cols=N` - cap render width to N columns on a wider terminal; the surplus becomes a blank inset border. Unset fills the terminal and auto-picks the pixel detail for a smooth framerate (pixel-doubling only ever engages on big screens beyond 200x45 cells); 0 forces full terminal at full detail
- `--max-rows=N` - cap render height to N rows on a taller terminal (same unset/0 semantics)
