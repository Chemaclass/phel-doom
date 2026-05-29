# Level system

10-level progression catalog + `build-world` factory. `src/core/level.phel`.

## Levels at a glance

| # | Name | Type | Enemies |
|---|---|---|---|
| 1 | imps | random | 4 imps |
| 2 | demons | random | 6 demons + shotgun |
| 3 | cacodemons | random | 8 cacos + chaingun |
| 4 | barons | random + blue lock | 5 barons |
| 5 | cyberdemons | random + red lock | 7 cyberdemons |
| 6 | spectres | random mix | 4 spectres + 2 imps |
| 7 | revenants | random mix | 4 revenants + 2 demons |
| 8 | archvile court | random mix | 2 archviles + 3 cacos + 2 mancubi |
| 9 | the brood | random mix | 3 pinkies + 3 barons + 2 mancubi |
| 10 | the final | hand-authored boss arena | 1 cyberdemon boss (50 HP) + 2 imps (max 1 alive) |

## Catalog

L1-L5: single-type procgen. L6-L9: mixed-monster procgen. L10: hand-authored arena with secrets + switches.

Non-locked procgen levels seed up to 2 secret passages (seen in [map.md](map.md)) that drop reward stashes on reveal. Locked levels (L4/L5) skip seeding to prevent bypassing the keycard door.

```phel
(def levels
  [{:size [22 16] :walls 12 :enemy :imp   :enemies 4 :chase 0.8 :name "imps"}
   {:size [28 20] :walls 22 :enemy :demon :enemies 6 :chase 1.0 :name "demons"}
   {:size [36 24] :walls 38 :enemy :caco  :enemies 8 :chase 1.2 :name "cacodemons"}
   {:size [44 28] :walls 55 :enemy :baron :enemies 5 :chase 1.4 :name "barons"      :door-lock :blue}
   {:size [52 32] :walls 75 :enemy :cyber :enemies 7 :chase 1.6 :name "cyberdemons" :door-lock :red}
   ;; L6-L9: mixed specs. L10: :layout + :switches, :door-lock :boss.
   ...])
```

Chase speed climbs monotonically L1-L9 (`0.8 1.0 1.2 1.4 1.6 1.7 1.8 1.9 2.0`) so difficulty never visibly dips; L10 eases to `1.6` because it is a single-boss dodging arena. L6 + L7 each carry one caster (a caco / baron) so ranged pressure never disappears across the mid-game stretch. Every enemy is also stamped with a depth-scaled `:aggression` cooldown multiplier (see [monsters.md](monsters.md)).

Only the headline `:enemies` count is shown above; in practice L2-L5 are now mixed-spec vectors (a melee secondary salted into the headline type) so no early room is single-type, and L1 stays pure imps as the tutorial. Mixed specs that omit `:lives` inherit the type's catalog HP.

Required fields:

| Field | Meaning |
|---|---|
| `:size`     | `[width height]` of grid in cells |
| `:walls`    | Random wall blobs (procedural path only) |
| `:enemy`    | Catalog kw - see [monsters.md](monsters.md) for the type list |
| `:enemies`  | Int (count of `:enemy`) OR vector of mixed specs (see below) |
| `:chase`    | Chase AI speed (units/sec) |
| `:name`     | HUD + intro-splash label |

Optional:

| Field | Meaning |
|---|---|
| `:enemy-lives` | Override the catalog's `:default-lives` (single-type entries only) |
| `:door-lock`   | `:blue` / `:red` - adds a matching keycard pickup and locks the exit |
| `:layout`      | Hand-authored ASCII grid (vector of strings) - bypasses `random-grid` |

### Mixed-monster rooms

When `:enemies` is a vector, each spec spawns its own count + HP and the enemy carries `:type` for render lookup:

```phel
{:size [40 30] :walls 50 :enemy :imp :name "the brood" :chase 1.8
 :enemies [{:type :pinky :count 3 :lives 2}
           {:type :baron :count 3 :lives 4}
           {:type :mancubus :count 2}]}   ; :lives omitted → catalog default
```

### Hand-authored arenas (`:layout`)

`[" ###### " " #....# " " #..@.# " " #....D " " ###### "]` parses via `map/parse-layout`:

| Char | Meaning |
|---|---|
| `#` / `.` | wall / floor |
| `@` | player spawn |
| `D` / `B` / `R` / `X` | unlocked / blue / red / boss-locked door |
| `S` | secret wall (press F to reveal) |
| `T` | switch (toggles target cells via `:switches` config) |

`:layout` supplies all doors + locks directly; skips `random-grid`, `seed-doors`, `lock-the-door`. Enemy spawn still applies.

Switches: `:switches [{:at [cx cy] :targets [[tx ty] ...]}]`. F near `:at` flips targets wall↔floor.

### Adding a new room

Append one map literal to `levels`. Adding a new enemy type = append one entry to `enemies/enemy-types` (see [monsters.md](monsters.md)).

## `config-for`

```phel
(defn config-for [n]
  (get levels (php/max 0 (php/min (php/- num-levels 1) (php/- n 1)))))
```

Level N config (1-indexed). Clamps out-of-range to nearest valid.

## `build-world`

Signature: `(build-world level-num lives backpack-level diff owned)` → new world state.

Per build: grid (hand-authored or random), player spawn + angle, enemies from mixed specs. Pickups seeded:
- Heart: only if `lives < max-lives` (avoid wasted pickups).
- Armor (50%), berserk (1/8), invuln (1/12), soulsphere (1/10), backpack (L2+, 1/5).
- 3 armor shards per level. Keycard (if locked, not `:boss`). Shotgun (L2) / chaingun (L3) if not owned.
- Ammo boxes: `max(2, ceil(total_hp / 8))` where `total_hp = sum(count * lives)`.

Stamps: `:enemy` (primary type fallback), `:level-name`, `:difficulty`, `:intro-secs` (1.5s).

`run-levels` (in `commands/play.phel`) overlays cross-level state: active weapon + mag/reserve, backpack level, minimap + audio toggles, `:god?` + `:armory?` flags.

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

## Replay with same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` and reuses on capital `R` from an end screen. All randomness (grid, spawn, doors, enemies) draws from the same PRNG, so sequences are deterministic.
