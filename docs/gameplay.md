# Player guide

Controls, pickups, weapons, CLI flags. The README has the short version; internals live in [combat.md](combat.md), [monsters.md](monsters.md), [level-system.md](level-system.md).

## Controls

| Key | Action |
|---|---|
| `w` / `s` | Forward / back |
| `a` / `d` | Strafe left / right |
| `←` / `→` | Turn left / right |
| `↑` / `↓` | Look up / down (pitch) |
| mouse | Turn + look up/down; left-click fires (hold = auto-fire). On by default |
| `SHIFT` / `x` | Sprint (1.6x speed, drains stamina) |
| `e` | About-face (180 degrees) |
| `space` | Fire (hold to auto-fire) |
| `r` | Reload |
| `f` | Use: open the secret wall or flip the switch directly ahead |
| `1`-`7` | Select weapon |
| `[` / `]` / wheel | Previous / next owned weapon |
| `m` | Minimap (off by default) |
| `n` | Sound |
| `p` | Pause menu: Resume / Settings / Restart / Quit |
| `h` / `ESC` | Info menu (pauses) |
| `F3` | Debug overlay |
| `F5` / `F9` | Quick-save / quick-load (slot 1) |
| `q` | Opens the pause menu on Quit; press again to quit |

`TAB` is not bound. Walk into the exit door to finish the level (no use key needed). The compass letter toward your goal tints: the keycard's colour until you hold it, then exit orange.

Mouselook is additive (every key still works); see the **Mouse** and **Sensitivity** settings in [settings.md](settings.md#fields) and [input.md](input.md#mouse-look-issue-246). Pitch drives aim: a shot must land on the drawn sprite, and the crosshair turns red while one would connect ([combat.md](combat.md#vertical-aim-gate-look-updown)). Terminal quirks (kitty, tmux): [input.md](input.md).

## Pickups

Health is 10 HP, drawn as 5 hearts. Hits cost 1-3 HP by attacker ([monsters.md](monsters.md#stats-comparison)); one armor point absorbs one whole hit.

- **heart**: heals one heart (2 HP), capped at 10. Only spawns while you are hurt.
- **armor**: +1 armor, cap 5.
- **armor shard**: +1 armor past the cap, up to 10. Never decays.
- **soulsphere**: +10 HP up to 14 (7 hearts). The surplus decays 1 HP every 5s.
- **ammo box**: a level box refills the active weapon's reserve. A kill-loot box refills the weapon it is tagged with.
- **berserk**: full heal plus 18s of damage boost: chainsaw x6, guns x2. A second one refreshes the timer.
- **invuln**: 10s of damage immunity.
- **backpack**: +1 base reserve cap for every weapon. Stacks 3 times (4x). L2 and later.
- **keycard**: blue opens the L4 exit, red L5, yellow L7. The L10 exit opens when the boss dies.
- **weapon**: yours for the run; the first pickup switches to it.

A revealed secret drops an ammo box, an armor shard and a rotating trophy (soulsphere, berserk, invuln). Spawn odds: [level-system.md](level-system.md#build-world).

## Weapons

Niches, not upgrades. Each weapon debuts on one level and is found on the map.

| Key | Weapon | Damage | Cooldown | Mag | Reserve cap | DPS | Debut | Niche |
|---|---|---|---|---|---|---|---|---|
| 1 | pistol | 1 | 0.12s | 10 | 50 | 8 | start | pierces every enemy in line (walls still stop it) |
| 2 | shotgun | 3 + 1 graze | 0.6s | 4 | 24 | 5 | L2 | cone: primary plus up to 2 grazed |
| 3 | chaingun | 1 | 0.05s | 30 | 90 | 20 | L3 | sustained single-target |
| 4 | chainsaw | 1 melee | 0.10s | - | - | 10 | L4 | 1.5-cell reach, no ammo, half speed while swinging |
| 5 | BFG | 6 splash, radius 3.0 | 1.2s | 1 | 20 | - | L7 | plasma, bypasses fire resist |
| 6 | incinerator | 1 fire | 0.06s | 40 | 120 | 16 | L6 | 4-cell reach; 0 damage to fire-resistant enemies |
| 7 | rocket | 3 splash, radius 2.0 | 0.9s | 1 | 30 | - | L5 | everyday area damage |

Pistol, chaingun, chainsaw and incinerator auto-fire while held; the rest fire once per press. Each weapon keeps its own mag and reserve. Starting reserve (`:reserve-start`): pistol 30, shotgun 8, BFG 5, rocket 5, chaingun and incinerator 0. `--armory` stamps every reserve to 9999. The info menu shows BFG 10 and rocket 4: unused direct-hit values ([combat.md](combat.md#splash-bfg-slot-5-rocket-slot-7)). Cacodemon, baron, archvile and mancubus take 0 from the incinerator.

## End screen (rank + summary)

Death and victory show kills, time, accuracy (connecting pulls / pulls), secrets, damage taken, kills per weapon, persisted bests, and a rank S-D from `0.7*accuracy + 0.3*secrets` ([scores.md](scores.md#run-summary--grade-end-screen)).

`r` restarts on a fresh map, `R` on the same map. After a death both re-enter that level with the weapons and backpack you entered it with, fresh ammo and full health. After a victory both start at L1.

## CLI flags

- `--difficulty=easy|normal|hard|nightmare` (`-d`): overrides the settings default. Harder raises enemy speed and HP and adds ammo and heals; nightmare respawns enemies in 1-2s. See [level-system.md](level-system.md#difficulty).
- `--level=N` (`-l`): start at level N (clamped to 1-10).
- `--god` (`-g`): dev mode, no damage, GOD badge.
- `--armory` (`-a`): dev mode, every weapon with infinite ammo.
- `--full-map` (`-f`): reveal the whole minimap.
- `--record=FILE` / `--demo=FILE`: record a run, or replay one deterministically. See [demo.md](demo.md).
- `--max-cols=N` / `--max-rows=N`: cap the render size; the surplus becomes a blank border. Unset fills the terminal with auto pixel detail (doubling only beyond 200x45 cells); `0` forces full detail.
