# Level system

10-level progression catalog + `build-world` factory. `src/core/level.phel`.

## Levels at a glance

| # | Name | Type | Enemies |
|---|---|---|---|
| 1 | imps | random | 4 imps |
| 2 | demons | hand-authored flat chamber | 5 demons + 2 imps + shotgun |
| 3 | cacodemons | hand-authored flat chamber | 4 cacos + 2 demons + 2 imps + chaingun |
| 4 | barons | hand-authored flat chamber + blue lock | 3 barons + 3 demons |
| 5 | cyberdemons | hand-authored flat chamber + red lock | 5 cyberdemons + 2 imps |
| 6 | spectres | hand-authored flat chamber | 4 spectres + 2 imps + 1 caco |
| 7 | revenants | hand-authored flat chamber + yellow lock | 4 revenants + 2 demons + 1 baron |
| 8 | archvile court | hand-authored flat chamber | 2 archviles + 3 cacos + 2 mancubi |
| 9 | the brood | random mix | 3 pinkies + 3 barons + 2 mancubi |
| 10 | the final | hand-authored boss arena | 1 cyberdemon boss (50 HP) + 2 imps (max 1 alive) |

## Catalog

L1: single-type procgen tutorial (imps only). L2-L8: hand-authored flat chambers, each seeded with random interior walls (`:walls` count) so the room disposition varies every run. L9: mixed-monster procgen (melee secondary salted per level). L10: hand-authored boss arena with secrets + switches (designed - no random walls, since switch targets are hand-placed).

Non-locked procgen levels seed up to 2 secret passages (see [map.md](map.md)) that drop reward stashes on reveal. Locked levels (L4) and hand-authored layouts (L2, L3, L4, L5, L6, L7, L8, L10) skip seeding to prevent keycard bypass and keep the authored geometry explicit.

```phel
(def levels
  [{:size [22 16] :walls 12 :enemy :imp   :enemies 4 :chase 0.8 :name "imps"}
   ;; L2: hand-authored flat chamber.
   {:enemy :demon :chase 1.0 :name "demons"
    :enemies [{:type :demon :count 5} {:type :imp :count 2}]
    :layout l2-layout}
   ;; L3: hand-authored flat chamber.
   {:enemy :caco :chase 1.2 :name "cacodemons"
    :enemies [{:type :caco :count 4} {:type :demon :count 2} {:type :imp :count 2}]
    :layout l3-layout}
   {:size [44 28] :walls 55 :enemy :baron :chase 1.4 :name "barons" :door-lock :blue
    :enemies [{:type :baron :count 3} {:type :demon :count 3}]}
   ;; L5: hand-authored flat chamber + red lock.
   {:enemy :cyber :chase 1.6 :name "cyberdemons" :door-lock :red
    :enemies [{:type :cyber :count 5} {:type :imp :count 2}]
    :layout l5-layout}
   ;; L6-L8: hand-authored flat chambers.
   ;; L10: :layout + :switches, :door-lock :boss.
   ...])
```

Chase speed climbs monotonically L1-L9 (`0.8 1.0 1.2 1.4 1.6 1.7 1.8 1.9 2.0`); L10 eases to `1.6` (single-boss arena). L2-L9 mix a melee secondary into the headline type to prevent single-type monotony; L1 stays pure imps as a tutorial. L6-L7 each carry one caster (caco/baron) to maintain ranged pressure. Every enemy gets a depth-scaled `:aggression` cooldown multiplier (see [monsters.md](monsters.md)). Mixed specs omitting `:lives` inherit catalog HP.

Required fields:

| Field | Meaning |
|---|---|
| `:size`     | `[width height]` of grid in cells |
| `:walls`    | Random interior wall-blob count - scattered into procgen rooms AND hand-authored `:layout` rooms (skipped only when `:switches` is set) |
| `:enemy`    | Catalog kw - see [monsters.md](monsters.md) for the type list |
| `:enemies`  | Int (count of `:enemy`) OR vector of mixed specs (see below) |
| `:chase`    | Chase AI speed (units/sec) |
| `:name`     | HUD + intro-splash label |

Optional:

| Field | Meaning |
|---|---|
| `:enemy-lives` | Override the catalog's `:default-lives` (single-type entries only) |
| `:door-lock`   | `:blue` / `:red` / `:yellow` - adds a matching keycard pickup and locks the exit |
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

`[" ###### " " #....# " " #..@.# " " #....# " " ###### "]` parses via `map/parse-layout`:

| Char | Meaning |
|---|---|
| `#` / `.` | wall / floor |
| `@` | player spawn |
| `S` | secret wall (press F to reveal) |
| `T` | switch (toggles target cells via `:switches` config) |

`:layout` supplies GEOMETRY + spawn (+ secrets / switches) only; it authors neither the interior walls nor the exit. `map/scatter-walls` seeds `:walls` random interior wall blobs into each hand-authored room (skipped on `:switches` levels) and seals any cut-off pocket so the floor stays connected; `map/place-exit` then drops exactly one exit door at a random reachable wall - interior pillar or border edge - on EVERY level, and `lock-the-door` applies the `:door-lock`. So the room disposition AND the way out are randomised per run, and finding the exit is part of the game. Enemy spawn still applies.

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
- Heart: only if `lives < max-lives`.
- Armor (50%), berserk (1/8), invuln (1/12), soulsphere (1/10), backpack (L2+, 1/5).
- 3 armor shards per level.
- Keycard if locked (not `:boss`); weapon drops if not owned: shotgun (L2), chaingun (L3), chainsaw (L4), rocket (L5), incinerator (L6), BFG (L7).
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
