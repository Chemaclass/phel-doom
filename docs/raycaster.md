# Raycaster

`src/core/engine.phel`. Per-column wall distances via grid-aligned DDA traversal.

For each screen column, fire a ray from the player at an angle offset from facing. Walk the grid until hitting a non-floor cell. Distance sets that column's wall height (DOOM/Wolfenstein 2D ray-march, no 3D math).

## Tunables

```phel
(def max-depth 12.0)
(def proj-dist 70.0)
```

- `max-depth`: ray stops at 12 units (beyond renders sky/floor)
- `proj-dist`: 70 cell perspective constant (controls wall scale)

## DDA: grid-aligned traversal

Step from grid-line to grid-line, not at fixed intervals. Two per-axis side-distances track distance to the next x/y crossing. Loop advances the nearer one, lands in the next cell, updates that axis's side-distance by `delta = |1/dir|`. Result: ~5-8 cell crossings per ray instead of ~35 fixed steps (see [performance.md](performance.md)).

```phel
(let [dirx   (php/cos angle)
      diry   (php/sin angle)
      cx0    (php/intval (php/floor px))
      cy0    (php/intval (php/floor py))
      stepx  (if (php/< dirx 0.0) -1 1)
      stepy  (if (php/< diry 0.0) -1 1)
      deltax (if (php/=== dirx 0.0) dda-inf (php/abs (php// 1.0 dirx)))
      deltay (if (php/=== diry 0.0) dda-inf (php/abs (php// 1.0 diry)))
      sidex0 (if (php/< dirx 0.0)
               (php/* (php/- px cx0) deltax)
               (php/* (php/- (php/+ cx0 1.0) px) deltax))
      sidey0 (if (php/< diry 0.0)
               (php/* (php/- py cy0) deltay)
               (php/* (php/- (php/+ cy0 1.0) py) deltay))]
  ...)
```

`dda-inf` (1e9): finite sentinel when ray direction is axis-aligned. Avoids PHP's `INF` edge cases.

## `cast-ray`: one ray

Returns distance (raw, not fish-eye corrected). For detailed return with side/coords, use inline DDA in `do-cast`.

Return tuple `[dist side hx hy]` available in `do-cast` for renderer:

| Field | Meaning |
|---|---|
| `side` | 0: x-line (vertical face); 1: y-line (horizontal face) - enables side-shading |
| `hx, hy` | Hit cell coords - feeds per-cell mottling hash to avoid flat bands |

## `cast-frame`: all rays at once

```phel
(defn cast-frame [world ^int width ^int scale]
  ...returns {:dists :hits :sides :hxs :hys})
```

Cast `width / scale` rays; return 5 parallel PHP arrays (one per output column).
- `dists`: fish-eye corrected wall distance
- `hits`: cell value at hit (0 if escaped to max-depth)
- `sides`: 0 = vertical, 1 = horizontal (side-shading)
- `hxs, hys`: hit cell coordinates

## Two key details

### Angular offset, not linear sweep

```phel
offset = atan((col - center) / proj-dist)
```

Each column's ray angle is `atan(col-offset / proj-dist)`. Constant wall scale on resize: making the terminal wider expands FOV (see more world) without changing wall heights. Linear FOV sweep would scale walls proportionally to width - feels wrong.

### Fish-eye correction

```phel
(php/* d (php/cos offset))
```

Edge rays travel further to reach the same wall plane than central rays. Multiply by `cos(offset)` to project onto the player's forward axis, flattening the wall. Without it: fish-eye barrel distortion. One multiply per column.

## Performance

DDA averages ~5-8 cell crossings per ray instead of ~35 fixed steps. Cast phase: ~1.55 ms at 180 cols (24% faster than step-march). Hot loop uses direct PHP ops (`php/+`, `php/<`) and `:pgrid` (nested PHP array), not Phel vectors.

## Why `core/`

Pure deterministic logic: `(pgrid, x, y, angle) -> distance`. No state, IO, or time-dependence. Tests (`tests/core/engine-test.phel`) verify distance accuracy, side bits, hit-cell coords, and array lengths.
