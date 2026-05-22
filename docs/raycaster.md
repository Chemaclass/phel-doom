# Raycaster

`src/modules/core/engine.phel`. Per-column wall distances via a grid-aligned DDA traversal.

## What raycasting is

For each screen column, fire a ray from the player along an angle offset from facing. Walk forward through the grid until it hits a non-floor cell. Distance travelled sets that column's wall height.

Original DOOM / Wolfenstein technique. No 3D math, 2D ray-marching with a perspective scale.

## Tunables

```phel
(def max-depth 12.0)   ; rays stop after this many world units
(def proj-dist 70.0)   ; perspective constant; see below
```

`max-depth` caps how far walls draw; beyond paints sky/floor.

## DDA: grid-aligned traversal

Each ray steps from one grid-line crossing to the next instead of marching a fixed `step` distance. Two per-axis side-distances track "how far until the ray crosses the next x-line / y-line"; the loop advances whichever is smaller, lands inside the next cell, and updates that axis's side-distance by `delta = |1/dir|`. ~5-8 iterations per ray on `default-grid` instead of ~35 with a 0.35-unit step-march (see [performance.md](performance.md), issue #2).

Key state per ray:

```phel
(let [dirx   (php/cos angle)
      diry   (php/sin angle)
      cx0    (php/intval (php/floor px))
      cy0    (php/intval (php/floor py))
      stepx  (if (php/< dirx 0.0) -1 1)
      stepy  (if (php/< diry 0.0) -1 1)
      deltax (if (php/=== dirx 0.0) dda-inf (php/abs (php// 1.0 dirx)))
      deltay (if (php/=== diry 0.0) dda-inf (php/abs (php// 1.0 diry)))
      ;; Distance from (px,py) to the next x-grid line and y-grid line.
      sidex0 (if (php/< dirx 0.0)
               (php/* (php/- px cx0) deltax)
               (php/* (php/- (php/+ cx0 1.0) px) deltax))
      sidey0 (if (php/< diry 0.0)
               (php/* (php/- py cy0) deltay)
               (php/* (php/- (php/+ cy0 1.0) py) deltay))]
  ...)
```

`dda-inf` is a finite sentinel (1e9) used when one axis of `dir` is exactly zero — keeps the comparisons clean without dragging in PHP's `INF`.

## `cast-ray-hit`: one ray

Returns the 5-tuple `[dist hit-cell side hx hy]`:

| Field | Meaning |
|---|---|
| `dist` | Travelled distance (not yet fish-eye corrected) |
| `hit-cell` | Cell value the ray landed on (0 if escaped to max-depth) |
| `side` | 0 if the last crossing was an x-line (vertical wall face), 1 if a y-line (horizontal face) |
| `hx, hy` | Integer cell coords of the hit cell |

`side` enables Wolfenstein-style directional shading: render darkens vertical-face columns by one shade step, so corners read as corners. `(hx, hy)` feeds a per-cell hash in the renderer that adds subtle brick mottling so a long corridor isn't one flat band.

## `cast-frame`: all rays at once

```phel
(defn cast-frame [world width]
  (let [...
        dists (php/array) hits (php/array) sides (php/array)
        hxs   (php/array) hys  (php/array)]
    (loop [col 0]
      (when (php/< col width)
        (let [offset (php/atan (/ (php/- col center) proj-dist))]
          (let [[d h side hx hy] (cast-ray-hit pgrid x y (php/+ angle offset))]
            (php/aset dists col (php/* d (php/cos offset)))   ; fish-eye correct
            (php/aset hits  col h)
            (php/aset sides col side)
            (php/aset hxs   col hx)
            (php/aset hys   col hy))
          (recur (php/+ col 1)))))
    {:dists dists :hits hits :sides sides :hxs hxs :hys hys}))
```

Five parallel PHP arrays, one entry per screen column. Renderer indexes by column.

## Two subtleties

### Angular offset, not horizontal sweep

```phel
offset = atan((col - center) / proj-dist)
```

Each column's ray angle is arctangent of column offset / `proj-dist`. Gives constant wall scale regardless of viewport width: making the terminal wider expands FOV (see more world), but a wall 5 cells away looks the same height.

A naïve raycaster sweeps angles linearly across an FOV. Walls then grow proportionally to viewport width, which feels wrong on resize.

### Fish-eye correction

```phel
(php/* d (php/cos offset))
```

A straight wall in front hits edge columns at greater raw distances because edge rays travel further to reach the same wall plane. Multiplying by `cos(offset)` projects onto the player's forward axis, flattening the wall.

Without this, walls bow outward at the edges (fish-eye). One multiply per column.

## Per-ray cost

DDA averages ~5-8 cell crossings before hitting a wall on `default-grid` — down from ~35 fixed steps. At 180 columns the cast phase clocks ~1.55 ms (was ~2.04 ms before DDA, ~24% faster). Hot enough that the loop still uses direct PHP ops (`php/+`, `php/<`, `php/aget`) and the cell lookup goes through `:pgrid` (a PHP-native nested array) instead of Phel persistent vectors.

## Why the raycaster lives in `core/`

Pure function: `(pgrid, x, y, angle) → distance`. No state, no IO, deterministic. `tests/modules/core/engine-test.phel` exercises with literal grids — distance accuracy, side bit, hit-cell coords, parallel-array lengths.
