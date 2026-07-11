# Map / grid

`src/core/map.phel`. Grid data shape, cell semantics, random-map generation, lookup helpers.

## Cells

```phel
(def cell-floor     0)  ; walkable empty
(def cell-wall      1)  ; solid wall, blocks rays and player
(def cell-door      2)  ; unlocked door: passable trigger, blocks rays only
(def cell-door-blue 3)  ; blue-keyed door: blocks until player holds :blue keycard
(def cell-door-red  4)  ; red-keyed door: blocks until player holds :red keycard
(def cell-door-boss 5)  ; boss-locked door: blocks until player kills the boss (grants synthetic :boss keycard)
(def cell-secret    6)  ; hidden passage: looks + blocks like a wall until the player reveals it with F
(def cell-switch-off 7) ; inactive switch: blocks like a wall, F-press flips to cell-switch-on + mutates target cells
(def cell-switch-on  8) ; activated switch: same blocking + a second F-press reverts to cell-switch-off + targets
(def cell-door-yellow 9) ; yellow-keyed door: blocks until player holds :yellow keycard
```

Every cell is one of these ints. Constants exported so no module uses raw `0/1/2/3/4/5/9` literals. `(= cell-door (cell g x y))` reads as purpose.

`lock-colours` maps locked-door cell values to keycard keywords:

```phel
{3 :blue  4 :red  5 :boss  9 :yellow}
```

`:boss` is a synthetic "colour" - no physical keycard spawns for it; the kw is granted automatically by combat when the boss dies on a `:door-lock :boss` level.

## Lookup helpers

```phel
(cell  grid x y)      ; cell value; out-of-bounds = cell-wall
(wall? grid x y)      ; true for cell-wall, cell-secret, switches (player-collision)
(door? grid x y)      ; true for any door variant (locked or not)
(secret? grid x y)    ; true for unrevealed secret
(switch? grid x y)    ; true for switch (either state)
(switch-on? grid x y) ; true for activated switch
(passable? grid keys x y) ; true if player can walk into (x,y) given held keys
```

`wall?` / `passable?` use the same lock colour resolution, so the player can't walk through locked doors but the raycaster still blocks rays on them (stay visually solid until traversed).

## Random map generation

```phel
(random-grid w h n-blocks)
```

1. Bordered base: outer ring `cell-wall`, interior `cell-floor`.
2. Loop `n-blocks` times: random interior `(x, y)`, random 1×1 or 2×2 block, paint cells `cell-wall`.
3. Border preserved (never overwritten).

`build-world` picks `n-blocks` per level so room size and obstacle density are independent.

## Random interior walls

```phel
(scatter-walls grid [sx sy] n)
```

Scatters `n` random 1×1-2×2 wall blobs into a grid's interior for varied room layouts, then `seal-pockets` walls off any floor the blobs cut off from spawn, so the playable area stays ONE connected region (pickups, enemies and the exit are never stranded; the spawn cell is kept clear). Seeded via `rng`. `build-world` applies it to hand-authored rooms (procgen already gets blobs from `random-grid`); a level that pins `:switches` keeps its authored geometry untouched.

## Exit placement

```phel
(place-exit grid [sx sy])
```

Drops exactly ONE exit door at a random wall cell reachable from the spawn `(sx, sy)`, so every level (hand-authored or procgen) gets a different exit the player must find. Floods the floor reachable from spawn, then turns a random wall touching that floor into a door - **any** wall, an interior pillar or a border edge, so the way out can be anywhere the player can reach (never pinned to the screen sides). Seeded via `rng` (same seed produces the same door). `build-world` then applies the level's `:door-lock` via `lock-the-door`.

## Player spawn

```phel
(random-spawn grid)  → [x y]   floats at the centre of a random open cell
```

Retries until a floor cell is found. Bordered grid always has at least one.

## Secret walls

Sources: hand-authored (`:layout` char `S`) or procgen-seeded (divider walls in random grids).

**Divider wall**: 1-cell-thick interior wall with floor on both horizontal OR vertical sides. `seed-secrets grid n` converts up to `n` of them to `cell-secret` via deterministic top-left scan. `build-world` skips locked levels to prevent shortcut bypassing keycard doors. Default: 2 per level.

API:
```phel
(secret? grid x y)        ; true for unrevealed secret
(reveal-secret grid x y)  ; swap to cell-floor (no-op if not secret)
(count-secrets grid)      ; total per-level
(seed-secrets grid n)     ; convert divider walls to cell-secret
```

Visual cue: none (DOOM-style). Discovery by bumping. `F`-press near a secret calls `reveal-secret` and drops reward stash (ammo box + armor shard + rotating trophy) via `level/place-secret-reward`. World tracks `:secrets-total` (count) + `:secrets-found` (bumps); debug HUD: `secrets X/Y`.

## Switches

Hand-authored only (`:layout` char `T`). Level config supplies targets:

```phel
:layout    ["#..T............T..#" ...]
:switches  [{:at [3 14]  :targets [[7 10]]}
            {:at [16 14] :targets [[12 10]]}]
```

`F`-press near a switch calls `toggle-switch(grid switches x y)`:
1. Swap switch cell `off` ↔ `on`.
2. Flip every target cell `wall` ↔ `floor` (doors skipped).
3. Resync raycaster's cached grid view.

Minimap: dim `T` (off) / bright `T` (on).

## Out-of-bounds reads

```phel
(cell [[1 1 1] [1 0 1]] 99 99)  → cell-wall
(cell [[1 1 1] [1 0 1]] -1 0)   → cell-wall
```

Off-map = wall means the raycaster skips range checks: keeps stepping until a non-floor cell (or max-depth). One branch saved per ray step.
