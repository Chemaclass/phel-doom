# Level system

10-level progression catalog + `build-world` factory. `src/modules/core/level.phel`.

## Levels at a glance

| # | Name | Type | Enemies |
|---|---|---|---|
| 1 | imps | random | 4 imps |
| 2 | demons | random | 6 demons (shotgun pickup) |
| 3 | cacodemons | random | 8 cacos (chaingun pickup) |
| 4 | barons | random + blue lock | 5 barons |
| 5 | cyberdemons | random + red lock | 7 cyberdemons |
| 6 | spectres | random mix | 4 spectres + 2 imps |
| 7 | revenants | random mix | 4 revenants + 2 demons |
| 8 | archvile court | random mix | 2 archviles + 3 cacos + 2 mancubi |
| 9 | the brood | random mix | 3 pinkies + 3 barons + 2 mancubi |
| 10 | the final | **hand-authored arena** | 1 cyberdemon BOSS (HP 20) + 4 imps |

## Catalog

```phel
(def levels
  [{:size [22 16] :walls 12 :enemy :imp   :enemies 4 :chase 0.8 :name "imps"}
   {:size [28 20] :walls 22 :enemy :demon :enemies 6 :chase 1.0 :name "demons"}
   {:size [36 24] :walls 38 :enemy :caco  :enemies 8 :chase 1.3 :name "cacodemons"}
   {:size [44 28] :walls 55 :enemy :baron :enemies 5 :chase 1.6 :name "barons"      :door-lock :blue}
   {:size [52 32] :walls 75 :enemy :cyber :enemies 7 :chase 2.0 :name "cyberdemons" :door-lock :red}])
```

Required fields:

| Field | Meaning |
|---|---|
| `:size`     | `[width height]` of grid in cells |
| `:walls`    | Random wall blobs (procedural path only) |
| `:enemy`    | Catalog kw — see [monsters.md](monsters.md) for the type list |
| `:enemies`  | Int (count of `:enemy`) OR vector of mixed specs (see below) |
| `:chase`    | Chase AI speed (units/sec) |
| `:name`     | HUD + intro-splash label |

Optional:

| Field | Meaning |
|---|---|
| `:enemy-lives` | Override the catalog's `:default-lives` (single-type entries only) |
| `:door-lock`   | `:blue` / `:red` — adds a matching keycard pickup and locks the exit |
| `:layout`      | Hand-authored ASCII grid (vector of strings) — bypasses `random-grid` |

### Mixed-monster rooms

When `:enemies` is a vector, each spec spawns its own count + HP and the enemy carries `:type` for render lookup:

```phel
{:size [40 30] :walls 50 :enemy :imp :name "the brood" :chase 1.8
 :enemies [{:type :pinky :count 3 :lives 2}
           {:type :baron :count 3 :lives 4}
           {:type :mancubus :count 2}]}   ; :lives omitted → catalog default
```

### Hand-authored arenas (`:layout`)

`[" ###### " " #....# " " #..@.# " " #....D " " ###### "]` parses via `map/parse-layout`. Char map:

| Char | Cell |
|---|---|
| `#` | wall |
| `.` | floor |
| `@` | floor + player spawn |
| `D` | unlocked door |
| `B` | blue-locked door |
| `R` | red-locked door |

`:layout` skips `random-grid`, `seed-doors`, and `lock-the-door` — the author placed everything explicitly. Enemy spawn (random / mixed-spec) still applies on top.

### Adding a new room

Append one map literal to `levels`. Adding a new enemy type = append one entry to `enemies/enemy-types` (see [monsters.md](monsters.md)).

## `config-for`

```phel
(defn config-for [n]
  (get levels (php/max 0 (php/min (php/- num-levels 1) (php/- n 1)))))
```

Level N config (1-indexed). Clamps out-of-range to nearest valid.

## `build-world`

Signature: `(build-world level-num lives backpack? diff owned)`. Sequence per build:

1. Grid: hand-authored (`map/parse-layout` of `:layout`) OR procedural (`random-grid` + `seed-doors` + `lock-the-door`).
2. Player spawn: `:layout`'s `@` cell OR `random-spawn`. Random angle either way.
3. Enemies: `spawn-enemies-mixed` from the normalised spec vector. Each enemy carries `:type` for per-enemy render visuals.
4. `maybe-spawn-heart` only if `lives < max-lives`.
5. `maybe-spawn-armor` (50%); `maybe-spawn-berserk` (1/8); `maybe-spawn-invuln` (1/12); `maybe-spawn-backpack` (L2+, 1/5, skipped when already owned).
6. `maybe-spawn-keycard` when `:door-lock` is set.
7. `maybe-spawn-weapon-pickups`: shotgun on L2 / chaingun on L3, skipped when already owned.
8. `spawn-ammo-boxes` count = `ceil(sum(count × lives) / 8)`, floor 2.
9. Stamp `:enemy` (primary type), `:level-name`, `:difficulty`, 1.5s `:intro-secs`.

`run-levels` (in `commands/play.phel`) wraps the call and overlays cross-level carries on top of the fresh world: **active weapon + per-weapon mag/reserve state**, minimap + sound toggles, `:god?` flag.

## Why hearts only when lives < max-lives

Wasted pickups clutter the minimap; seeing a heart signals "below cap" without text.

## Reading order through a run

```
build-world 1 5     → L1 imps, no heart (started at max-lives)
... play ...
result :next-level :level 2 :lives 4
build-world 2 4     → L2 demons, ONE heart (lives < 5)
... play ...
result :next-level :level 3 :lives 5
build-world 3 5     → L3 cacodemons, no heart
... play ...
```

`run-levels` in `commands/play.phel` calls `build-world` per iteration.

## Restart with the same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` and `mt_srand`s it. On `R` (capital) from an end screen the seed is reused. `random-grid` / `random-spawn` / `seed-doors` / `spawn-enemies` all draw from the same PRNG, so the sequence is bit-identical. Lets the player replay a tough spawn.
