# Level system

10-level progression catalog + `build-world` factory. `src/core/level.phel`.

## Levels at a glance

| # | Name | Type | Enemies |
|---|---|---|---|
| 1 | imps | random | 4 imps |
| 2 | demons | hand-authored verticality (staircase + platform + pit) | 5 demons + 2 imps + shotgun |
| 3 | cacodemons | hand-authored verticality (descending trench) | 4 cacos + 2 demons + 2 imps + chaingun |
| 4 | barons | random + blue lock | 3 barons + 3 demons |
| 5 | cyberdemons | hand-authored verticality (central dais) + red lock | 5 cyberdemons + 2 imps |
| 6 | spectres | hand-authored verticality (3-tier room, 4 open-sided stairs, east-west axis) | 4 spectres + 2 imps + 1 caco |
| 7 | revenants | hand-authored verticality (3-tier room, 4 open-sided stairs, north-south axis) + yellow lock | 4 revenants + 2 demons + 1 baron |
| 8 | archvile court | hand-authored verticality (3-tier court, 4 open-sided stairs, offset runs) | 2 archviles + 3 cacos + 2 mancubi |
| 9 | the brood | random mix | 3 pinkies + 3 barons + 2 mancubi |
| 10 | the final | hand-authored boss arena | 1 cyberdemon boss (50 HP) + 2 imps (max 1 alive) |

## Catalog

L1: single-type procgen tutorial (imps only). L2 / L3 / L5 / L6 / L7 / L8: hand-authored verticality (see [Verticality levels](#verticality-levels-floor-heights--ceil-heights) below) - L2 the showcase (staircase + raised platform + sunken pit), L3 a descending trench, L5 a central dais, L6 a spacious three-tier room stacked east-west, L7 a spacious three-tier room stacked north-south, L8 the grand three-tier court with offset stair runs. L4 / L9: mixed-monster procgen (melee secondary salted per level). L10: hand-authored arena with secrets + switches.

Non-locked procgen levels seed up to 2 secret passages (see [map.md](map.md)) that drop reward stashes on reveal. Locked levels (L4) and hand-authored layouts (L2, L3, L5, L6, L7, L8, L10) skip seeding to prevent keycard bypass and keep the authored geometry explicit.

```phel
(def levels
  [{:size [22 16] :walls 12 :enemy :imp   :enemies 4 :chase 0.8 :name "imps"}
   ;; L2: hand-authored verticality showcase (staircase + platform + pit).
   {:enemy :demon :chase 1.0 :name "demons"
    :enemies [{:type :demon :count 5} {:type :imp :count 2}]
    :layout showcase-layout           ; flat 24x18 chamber
    :floor-heights showcase-floor-heights
    :ceil-heights  showcase-ceil-heights}
   ;; L3: hand-authored verticality (descending trench).
   {:enemy :caco :chase 1.2 :name "cacodemons"
    :enemies [{:type :caco :count 4} {:type :demon :count 2} {:type :imp :count 2}]
    :layout l3-layout :floor-heights l3-floor-heights}
   {:size [44 28] :walls 55 :enemy :baron :chase 1.4 :name "barons" :door-lock :blue
    :enemies [{:type :baron :count 3} {:type :demon :count 3}]}
   ;; L5: hand-authored verticality (central dais) + red lock.
   {:enemy :cyber :chase 1.6 :name "cyberdemons" :door-lock :red
    :enemies [{:type :cyber :count 5} {:type :imp :count 2}]
    :layout l5-layout :floor-heights l5-floor-heights}
   ;; L6: mixed procgen. L7: hand-authored verticality (3-tier room, 4
   ;; open-sided stairs) + yellow lock. L8-L9: mixed procgen.
   ;; L10: :layout + :switches, :door-lock :boss.
   ...])
```

Chase speed climbs monotonically L1-L9 (`0.8 1.0 1.2 1.4 1.6 1.7 1.8 1.9 2.0`); L10 eases to `1.6` (single-boss arena). L2-L9 mix a melee secondary into the headline type to prevent single-type monotony; L1 stays pure imps as a tutorial. L6-L7 each carry one caster (caco/baron) to maintain ranged pressure. Every enemy gets a depth-scaled `:aggression` cooldown multiplier (see [monsters.md](monsters.md)). Mixed specs omitting `:lives` inherit catalog HP.

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
| `:door-lock`   | `:blue` / `:red` / `:yellow` - adds a matching keycard pickup and locks the exit |
| `:layout`      | Hand-authored ASCII grid (vector of strings) - bypasses `random-grid` |
| `:floor-heights` | `{[x y] height}` map of per-cell floor `z` (#232) - raised cells render a step riser + cap, lowered cells a pit. Used by L2 / L3 / L5 / L7 (the verticality levels); omitted everywhere else (flat floor, byte-identical render) |
| `:ceil-heights` | `{[x y] height}` map of per-cell ceiling `z` (#235, default 1.0) - cells with `z < 1.0` render a hanging ceiling + cap (a low tunnel); `z > 1.0` lifts the ceiling (a tall atrium, not drawn). Used by L2's low lintel; omitted everywhere else (flat ceiling, byte-identical render) |
| `:handrails` | Set of directed `[hx hy lx ly]` downward-edge keys (#299) - blocks an entity from stepping OFF that edge (a fenced lip); an unrailed off-edge drop is a fall costing 1 life per tier (see [Handrails + fall damage](#handrails--fall-damage-299)). Used by L7; omitted everywhere else (no rails) |

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
| `D` / `B` / `R` / `Y` / `X` | unlocked / blue / red / yellow / boss-locked door |
| `S` | secret wall (press F to reveal) |
| `T` | switch (toggles target cells via `:switches` config) |

`:layout` supplies all doors + locks directly; skips `random-grid`, `seed-doors`, `lock-the-door`. Enemy spawn still applies.

Switches: `:switches [{:at [cx cy] :targets [[tx ty] ...]}]`. F near `:at` flips targets wall↔floor.

### Verticality levels (`:floor-heights` / `:ceil-heights`)

Four levels turn the variable-height feature (floor heights #232, ceiling heights #235, Z physics #233) ON for players: L2, L3, L5 and L7. Each is a flat `:layout` plus a separate `{[x y] z}` height map (not special layout chars), so every raised / lowered cell is guaranteed to land on a known floor cell (a procgen room could drop a step onto a wall). Each is authored to be DISTINCT, and each keeps its catalog identity (name, enemy mix, chase, lock, weapon drop) so the difficulty curve and progression are unchanged - only the geometry is now authored.

Shared rules: every rise the player climbs is at or below `physics/step-up-max` (0.4) so a flight auto-climbs as the player walks into it; pits drop one step-up per tier so the player falls in under gravity (`tick-fall`) and walks back out; the exit door + any keycard stay reachable on flat ground around each feature; only ceilings `< 1.0` render (a hanging tunnel, never a lift); an enemy on a raised cell rises to stand on it (#234 floor-anchor).

**L2 - showcase (#237)** (`showcase-floor-heights` / `showcase-ceil-heights`), a flat 24x18 chamber:

| Feature | Cells | Height `z` |
|---|---|---|
| Staircase (4 steps, climbs north) | cols 8-13, rows 8 -> 5 | 0.3, 0.6, 0.9, 1.2 |
| Platform plateau (vantage) | cols 8-13, rows 2-4 | 1.2 (top-stair height, continuous) |
| Sunken pit | cols 4-7, rows 12-13 | -0.4 |
| Low ceiling lintel (stair foot) | cols 8-13, row 9 | 0.7 (a hanging ceiling) |

**L3 - descending trench** (`l3-floor-heights`), a flat 28x24 chamber. A sunken corridor crosses the room's middle; the player walks DOWN into it and climbs back out the far side. Flanking columns (cols 1-4, 23-26) stay flat so the trench can always be skirted to the east exit `D`.

| Feature | Cells | Height `z` |
|---|---|---|
| Trench rim (one tier down) | cols 5-22, rows 9 + 13 | -0.4 |
| Trench bottom (deeper tier) | cols 5-22, rows 10-12 | -0.8 |

**L5 - central dais** (`l5-floor-heights`), a flat 30x26 chamber. A raised square plateau stands dead-centre (a vantage in the cyberdemon arena), reached by a two-step ramp on its south face. The flat ground rings the dais so the red exit `R` + keycard stay reachable without climbing.

| Feature | Cells | Height `z` |
|---|---|---|
| Ramp (2 steps, south face) | cols 13-16, rows 13 + 12 | 0.4, 0.8 |
| Dais plateau (vantage) | cols 12-17, rows 8-11 | 0.8 (ramp-top height, continuous) |

**L6 - three-tier room, four open-sided stairs, east-west axis (#310)** (`l6-floor-heights`), a spacious flat 42x26 chamber. The spectre level gets the same multi-tier treatment as L7 (below) but rotated onto the EAST-WEST axis, so the campaign reads as a varied multi-level space instead of one showcase: where L7 stacks three tiers NORTH (climb up the rows through horizontal divider rows), L6 stacks them WEST (climb left through two vertical divider columns, cols 28 and 13). Each divider is pierced by two stair mouths (rows 5-9 and 16-20), so four three-cell-tall staircases with OPEN flanks connect the tiers: lower stairs A / B climb tier 0 -> tier 1 through the col-28 mouths, upper stairs C / D climb tier 1 -> tier 2 through the col-13 mouths. A tier is reachable ONLY by walking up a run. The bottom (east) tier holds the spawn and the unlocked exit `D` (east wall, row 12), reachable with zero climbs (L6 has no keycard). L6 has no railed lips - all four stair flanks are open fall-offs (a one-tier, 1-life drop). It reuses the same binary-exact 0.375 ladder as L7 (see the note below). No `:ceil-heights` (the room is open: flat 1.0 ceiling).

| Feature | Cells | Height `z` |
|---|---|---|
| Tier 0 (east, spawn floor) | cols 29-40 | 0.0 (default) |
| Tier 1 (middle plateau) | cols 14-27 | 0.75 |
| Tier 2 (west plateau) | cols 1-12 | 1.5 |
| Lower stair A core (climbs west) | cols 29 -> 27, rows 6-8 | 0.0, 0.375, 0.75 |
| Lower stair B core | cols 29 -> 27, rows 17-19 | 0.0, 0.375, 0.75 |
| Upper stair C core | cols 14 -> 12, rows 6-8 | 0.75, 1.125, 1.5 |
| Upper stair D core | cols 14 -> 12, rows 17-19 | 0.75, 1.125, 1.5 |
| Open stair flanks (fall-off sides) | beside each core | drop to the tier below |

**L7 - three-tier room, four open-sided stairs (#298)** (`l7-floor-heights`), a spacious flat 42x26 chamber. One open arena is split into three stacked floor tiers by two solid divider walls (rows 6 and 16), each pierced by two stair mouths. Four three-cell-wide staircases with OPEN flanks (no side walls, so you can fall off a run, #299) connect the tiers: lower stairs A / B climb tier 0 -> tier 1 through the row-16 mouths, upper stairs C / D climb tier 1 -> tier 2 through the row-6 mouths. A tier is reachable ONLY by walking up a run (the dividers are solid wall between the mouths). The yellow exit `Y` sits on the bottom tier so it stays reachable with zero climbs. No `:ceil-heights` (the room is open: flat 1.0 ceiling).

The step rise is `0.375` (= 3/8) rather than `0.4`: it is exactly representable in binary floating point, so a stacked run never accumulates rounding drift that could nudge an adjacent riser above `step-up-max` and silently block the climb (e.g. `0.4 * 3 = 1.2000000000000002`, whose `0.4` gap to `1.6` trips the strict `> step-up-max` gate). Keeping every authored `z` a k/8 multiple guarantees the whole staircase stays walkable up and down to every tier.

| Feature | Cells | Height `z` |
|---|---|---|
| Tier 0 (bottom, spawn floor) | rows 17-24 | 0.0 (default) |
| Tier 1 (middle plateau) | rows 7-15 | 0.75 |
| Tier 2 (top plateau) | rows 1-5 | 1.5 |
| Lower stair A core (climbs north) | cols 8-10, rows 16 -> 14 | 0.0, 0.375, 0.75 |
| Lower stair B core | cols 25-27, rows 16 -> 14 | 0.0, 0.375, 0.75 |
| Upper stair C core | cols 6-8, rows 6 -> 4 | 0.75, 1.125, 1.5 |
| Upper stair D core | cols 29-31, rows 6 -> 4 | 0.75, 1.125, 1.5 |
| Open stair flanks (fall-off sides) | beside each core | drop to the tier below |
| West stair-C plateau lips (railed) | `l7-handrails` (10 edges) | step-off blocked |

**L8 - three-tier archvile court, four open-sided stairs, offset runs (#310)** (`l8-floor-heights`), the largest multi-tier room: a grand flat 50x30 chamber. A wide southern court pit (the spawn floor) climbs NORTH up two galleries to a throne band, split into three stacked tiers by two solid divider rows (rows 11 and 5), each pierced by two stair mouths. Four three-cell-wide staircases with OPEN flanks connect the tiers: lower stairs A / B climb tier 0 -> tier 1 through the row-11 mouths (cols 10-16 + 33-39), upper stairs C / D climb tier 1 -> tier 2 through the row-5 mouths (cols 14-20 + 29-35). Unlike L7's roughly-aligned runs, L8's lower and upper stairs sit at DIFFERENT columns, so reaching the throne means climbing a lower run, crossing the gallery, then climbing an upper run - a longer court ascent. A tier is reachable ONLY by walking up a run. The unlocked exit `D` sits on the court (bottom) tier (east wall, row 20), reachable with zero climbs (L8 has no keycard). It reuses the same binary-exact 0.375 ladder as L7 (see the L7 note above). No railed lips (all four stair flanks are open fall-offs). No `:ceil-heights` (the room is open: flat 1.0 ceiling).

| Feature | Cells | Height `z` |
|---|---|---|
| Tier 0 (court, spawn floor) | rows 12-28 | 0.0 (default) |
| Tier 1 (gallery plateau) | rows 6-10 | 0.75 |
| Tier 2 (throne plateau) | rows 1-4 | 1.5 |
| Lower stair A core (climbs north) | cols 11-13, rows 11 -> 9 | 0.0, 0.375, 0.75 |
| Lower stair B core | cols 34-36, rows 11 -> 9 | 0.0, 0.375, 0.75 |
| Upper stair C core | cols 15-17, rows 5 -> 3 | 0.75, 1.125, 1.5 |
| Upper stair D core | cols 30-32, rows 5 -> 3 | 0.75, 1.125, 1.5 |
| Open stair flanks (fall-off sides) | beside each core | drop to the tier below |

L1 stays flat (it is the golden-frame render fixture), and the catalog stays 10 levels with the boss arena last.

### Handrails + fall damage (#299)

A tier or stair edge can carry a **handrail**: a low barrier you see over but can't pass, so an entity cannot step OFF that downward edge. Where there is no rail, walking off an edge with a drop bigger than `step-up-max` (0.4) is a **fall** to the tier below (the eye eases down under `tick-fall` gravity) that costs **1 life per tier dropped**. Both the player (`physics/try-move`) and enemies (`enemy/try-step`) obey the same rule; an enemy can die from the fall.

- **Representation.** A level config's optional `:handrails` is a set of directed `[hx hy lx ly]` edge keys (high cell -> low cell). `build-world` threads it onto the world as `:handrails`; absent -> empty set, so every level but L7 is unaffected. The edge is directed and per-edge, so railing the plateau lip leaves the open stair side fall-off-able and never blocks climbing back UP the same cells.
- **What counts as a fall.** Only a single move whose floor drops by MORE than `step-up-max`. A deliberate stair descent (each L7 tread is 0.375, below the limit) is a normal step-down, never a fall - no damage. The L7 tier gap is 0.75, so a one-tier off-edge drop costs 1 life and a two-tier drop (1.5) costs 2 (`physics/fall-tiers` = `round(drop / tier-gap)`, min 1). Fall damage is environmental: armor does not absorb it and it arms no i-frames.
- **L7 layout.** Only the WEST upper-staircase (C) plateau lips are railed (`l7-handrails`), so you can't tumble off the top plateau onto the west stair flanks. The EAST staircase (D) plateau lips are left OPEN, so a step off the east lip is a real one-tier fall. All four stair cores stay un-railed, so every staircase is fully walkable up and down and the exit + yellow key (bottom tier) stay reachable. A railed edge blocks only its own direction; a chasing enemy whose straight step is railed can still slide off an unrailed neighbouring edge, so a lip is fully fenced only when each of its downward edges is listed.

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
