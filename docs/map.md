# Map / grid

Lives in `src/modules/core/map.phel`. Owns the grid data shape, cell
semantics, random-map generation, and lookup helpers.

## Cells

```phel
(def cell-floor   0)  ; walkable empty
(def cell-wall    1)  ; solid wall, blocks rays and player
(def cell-door    2)  ; passable trigger, blocks rays only
```

Every grid cell is one of these ints. Constants are exported so no
other module ever writes raw `0/1/2` literals — `(= cell-door
(cell g x y))` reads like its purpose.

## Lookup helpers

```phel
(cell  grid x y)   ; returns the cell value; out-of-bounds = cell-wall
(wall? grid x y)   ; true for cell-wall only (doors are passable!)
(door? grid x y)   ; true for cell-door
```

`wall?` is the player-collision predicate. Doors return false here
because walking into a door is the level-advance trigger; the
raycaster has its own predicate that blocks rays on cell-door so
doors remain visually solid until traversed.

## Random map generation

```phel
(random-grid w h n-blocks)
```

Steps:

1. Build a bordered base: outer ring of `cell-wall`, interior of
   `cell-floor`.
2. Loop `n-blocks` times: pick a random interior `(x, y)` and a
   random 1×1 or 2×2 block size, paint those cells as `cell-wall`.
3. Border is preserved (never overwritten).

The caller (`build-world` in `core/level.phel`) picks `n-blocks`
per level so changing room size doesn't drag obstacle density with
it.

## Door seeding

```phel
(seed-doors grid n)
```

Converts `n` random interior wall cells into doors. A candidate cell
must (a) currently be a wall AND (b) sit next to at least one floor
cell — without that check a door can get hidden inside a 2×2 wall
blob and the room becomes inescapable (this was a real bug that
shipped once). Gives up after 400 attempts when the interior runs
out of candidates.

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

Picks until it finds a `cell-floor`. The bordered grid guarantees at
least one floor cell exists so the loop terminates.

## Out-of-bounds reads

```phel
(cell [[1 1 1] [1 0 1]] 99 99)  → cell-wall
(cell [[1 1 1] [1 0 1]] -1 0)   → cell-wall
```

Treating off-map as wall means the raycaster never has to range-
check before reading: it just keeps stepping until it sees a non-
floor cell (or hits max-depth). Saves a branch per ray step.
