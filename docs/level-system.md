# Level system

The 10-level catalog, difficulty scaling and the `build-world` factory. `src/core/level.phel`, `src/core/difficulty.phel`. Grid generation lives in [map.md](map.md); monster types in [monsters.md](monsters.md).

## Levels at a glance

| # | Name | Room | Lock | Enemies | Chase | `:walls` | Theme | Weapon debut |
|---|---|---|---|---|---|---|---|---|
| 1 | imps | procgen 22x16 | - | 4 imps | 0.8 | 12 | base | - |
| 2 | demons | layout 24x18 | - | 5 demons, 2 imps | 1.0 | 12 | steel | shotgun |
| 3 | cacodemons | layout 28x24 | - | 3 cacos, 2 demons, 2 imps | 1.2 | 18 | steel | chaingun |
| 4 | barons | layout 44x28 | blue | 3 barons, 4 demons, 2 imps | 1.4 | 34 | moss | chainsaw |
| 5 | cyberdemons | layout 30x26 | red | 2 cybers, 4 imps | 1.6 | 22 | clay | rocket |
| 6 | spectres | layout 42x26 | - | 6 spectres, 3 imps, 1 caco | 1.7 | 30 | moss | incinerator |
| 7 | revenants | layout 42x26 | yellow | 5 revenants, 2 demons, 1 baron | 1.8 | 30 | rust | BFG |
| 8 | archvile court | layout 50x30 | - | 2 archviles, 3 cacos, 3 mancubi | 1.9 | 42 | clay | - |
| 9 | the brood | procgen 54x32 | - | 6 pinkies, 4 barons, 2 mancubi | 2.0 | 78 | rust | - |
| 10 | the final | hand-authored arena | boss | 1 cyber (50 HP), 2 imps (max 1 alive) | 1.6 | - | hell | - |

- **Procgen** (L1, L9): `random-grid` builds the room from `:size` and `:walls`.
- **Fixed shell** (L2-L8): a `:layout` gives an empty bordered room and spawn; `:walls` random blobs fill it each run.
- **Hand-authored arena** (L10): the layout pins walls, 2 secrets and 2 switches. No random walls: switch targets are fixed cells.

Every level gets a random exit (`map/place-exit`), then its lock, so finding the way out is part of the game.

Design rules: chase speed never drops before L10, which eases to 1.6 (a dodging arena, not a swarm). L1 is pure imps; later levels mix in a melee secondary. L6 and L7 each carry one caster. L5 has two cybers, not five: five out-gunned the L10 boss.

### Secrets

`build-world` seeds up to 2 secrets (`map/seed-secrets`) only on levels with no `:layout` and no lock: L1 and L9. Layouts keep explicit geometry, and a secret could bypass a keycard door. L10 has a hand-authored pair. Mechanics: [map.md](map.md#secret-walls).

## Config fields

Required:

| Field | Meaning |
|---|---|
| `:enemy`   | Headline type: the render fallback for sprites. The splash and HUD show `:name` |
| `:enemies` | Int (count of `:enemy`) or a vector of mixed specs |
| `:chase`   | Chase speed (units/sec) |
| `:name`    | HUD and intro-splash label |
| `:size`    | `[width height]` in cells. Procgen levels only |
| `:walls`   | Random wall-blob count. Used by procgen and fixed-shell levels; ignored when `:switches` is set |

Optional:

| Field | Meaning |
|---|---|
| `:layout`      | Hand-authored ASCII grid (vector of strings); bypasses `random-grid` |
| `:door-lock`   | `:blue` / `:red` / `:yellow` (spawns a matching keycard) or `:boss` (opens on the cyber kill) |
| `:switches`    | `[{:at [x y] :targets [[x y] ...]}]`, see [map.md](map.md#switches) |
| `:theme`       | Floor tint (#417), resolved by `io/render/palette.phel` `theme-floor-code` at load time; unknown falls back to `:base` |
| `:enemy-lives` | HP override for single-type (int `:enemies`) levels |

### Mixed-monster rooms

A vector of specs, each with its own count and HP:

```phel
{:size [54 32] :walls 78 :enemy :pinky :chase 2.0 :name "the brood" :theme :rust
 :enemies [{:type :pinky    :count 6}
           {:type :baron    :count 4}
           {:type :mancubus :count 2}]}   ; :lives omitted -> catalog default
```

Specs may add `:lives N` and `:max-concurrent K` ([monsters.md](monsters.md#spawning)).

### Layouts (`:layout`)

`map/parse-layout` reads one character per cell:

| Char | Cell |
|---|---|
| `#` | wall |
| `.` | floor |
| `@` | player spawn (required, else `build-world` throws) |
| `S` | secret wall (F reveals) |
| `T` | switch (F toggles its `:switches` targets) |

Unknown characters read as floor. A layout never holds the exit: `build-grid` scatters `:walls` (unless `:switches` is set), then `place-exit` adds the door and `lock-the-door` locks it.

### Adding a level

Append one map literal to `levels`; `num-levels` follows. New enemy types: [monsters.md](monsters.md#catalog-enemy-types).

## Difficulty

`difficulty/scale-cfg` applies the multipliers before the build. `--difficulty` overrides the settings default; an unrecognised value falls back to the settings-page default (`resolve-difficulty`).

| | easy | normal | hard | nightmare |
|---|---|---|---|---|
| Chase speed | x0.7 | x1.0 | x1.3 | x1.8 |
| Enemy HP (rounded up) | x1.0 | x1.0 | x1.3 | x1.5 |
| Enemy count (L1 only) | x0.7 | x1.0 | x1.3 | x1.5 |
| Ammo boxes | x1.0 | x1.0 | x1.2 | x1.5 |
| Hearts / armor shards | 1 / 3 | 1 / 3 | 1 / 4 | 2 / 5 |

Count scales only int `:enemies` (L1); mixed specs are author-tuned. Powerup odds never scale. Nightmare also gives 1-2s respawns and no `:max-concurrent` cap ([monsters.md](monsters.md#respawn)).

## `build-world`

`(build-world level-num lives backpack-level diff owned)` returns a fresh world (shorter arities default to 0, `:normal`, `#{:pistol}`). `config-for` reads level N, clamped. Per build: grid, secrets, enemies ([monsters.md](monsters.md#spawning)), then pickups:

| Pickup | Rule |
|---|---|
| Hearts | 1 (2 on nightmare), only when `lives < max-lives` |
| Armor | 1 in 2 levels |
| Berserk / invuln / soulsphere | 1 in 8 / 1 in 12 / 1 in 10 |
| Backpack | 1 in 5, from L2, while below the 3-stack cap |
| Armor shards | 3 (4 hard, 5 nightmare) |
| Keycard | one, when the lock is a colour |
| Weapons | every weapon whose debut level has passed and the player lacks, most recent first, capped at 2 |
| Ammo boxes | `max(2, ceil(ammo-mul * total_hp / 8))`, `total_hp = sum(count * lives)` |

The weapon rule (#453) arms a player who arrives with an empty rack (`--level=8`); the level's own debut is always the most recent, so the cap never drops it. The world also gets `:intro-secs` (1.5s splash) and, on L1, `:hint-secs` (first-run key hints).

Gotcha: every roll draws from one seeded stream in a fixed order. A guard that skips a roll must short-circuit before drawing, or every later spawn shifts and same-seed replay breaks.

## Run flow

`run-levels` (`commands/play.phel`) seeds `core/rng` and calls `build-world` per level, then overlays the dev flags, toggles, settings and the weapon stash.

- **Next level**: seed from the stream (`rng/next-raw!`). Lives, kills, time, weapons, ammo, backpack and toggles carry; stamina refills.
- **Death retry**: the same level with the weapons and backpack you entered it with, fresh ammo, full health, kills and time reset. `r` = fresh seed, `R` = same seed. Entry values keep `R` identical: a weapon grabbed during the fatal attempt would shift every later spawn.
- **Victory or pause-menu Restart**: L1 with a fresh rack (victory `R` reuses the seed).

A seed plus the input stream fully determines a run ([demo.md](demo.md)).
