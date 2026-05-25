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
```

Every cell is one of these ints. Constants exported so no module uses raw `0/1/2/3/4/5` literals. `(= cell-door (cell g x y))` reads as purpose.

`lock-colours` maps locked-door cell values to keycard keywords:
```phel
{3 :blue   4 :red   5 :boss}
```

`:boss` is a synthetic "colour" — no physical keycard item ever spawns for it; the kw is granted automatically by `combat/maybe-unlock-boss-door` when the boss is killed on a `:door-lock :boss` level.

## Lookup helpers

```phel
(cell  grid x y)   ; cell value; out-of-bounds = cell-wall
(wall? grid x y)   ; true for cell-wall only (doors are passable!)
(door? grid x y)   ; true for cell-door
```

`wall?` is the player-collision predicate. Doors return false because walking into a door is the level-advance trigger. The raycaster has its own predicate that blocks rays on cell-door so doors stay visually solid until traversed.

## Random map generation

```phel
(random-grid w h n-blocks)
```

1. Bordered base: outer ring `cell-wall`, interior `cell-floor`.
2. Loop `n-blocks` times: random interior `(x, y)`, random 1×1 or 2×2 block, paint cells `cell-wall`.
3. Border preserved (never overwritten).

`build-world` picks `n-blocks` per level so room size and obstacle density are independent.

## Door seeding

```phel
(seed-doors grid n)
```

Converts `n` random interior wall cells into doors. Candidate must (a) currently be a wall and (b) sit next to at least one floor cell. Without the floor-neighbour check a door can hide inside a 2×2 wall blob and lock the room (real bug that shipped once). Gives up after 400 attempts.

```phel
(defn- has-floor-neighbour? [grid x y]
  (or (= cell-floor (cell grid (- x 1) y))
      (= cell-floor (cell grid (+ x 1) y))
      (= cell-floor (cell grid x (- y 1)))
      (= cell-floor (cell grid x (+ y 1)))))
```

## Player spawn

```phel
(random-spawn grid)  → [x y]   floats at the centre of a random open cell
```

Picks until it finds a `cell-floor`. Bordered grid guarantees one exists; loop terminates.

## Out-of-bounds reads

```phel
(cell [[1 1 1] [1 0 1]] 99 99)  → cell-wall
(cell [[1 1 1] [1 0 1]] -1 0)   → cell-wall
```

Off-map = wall means the raycaster skips range checks: keeps stepping until a non-floor cell (or max-depth). One branch saved per ray step.
