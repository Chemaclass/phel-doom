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
- `fov-proj-dist`: width-aware projection distance for ray spread; clamps FOV at 90° past 140 cols (see Angular offset below)

## DDA: grid-aligned traversal

Step grid-line to grid-line instead of at fixed intervals. Two per-axis side-distances track the next x/y crossing. Loop advances the nearer side, lands in the next cell, updates that axis's delta by `|1/dir|`. Result: ~5-8 cell crossings per ray instead of ~35 fixed steps (see [performance.md](performance.md)).

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

Returns raw (uncorrected) distance. Detailed tuple `[dist side hx hy]` is computed inline in `do-cast`:

| Field | Meaning |
|---|---|
| `side` | 0: x-line (vertical face); 1: y-line (horizontal face) for directional shading |
| `hx, hy` | Hit cell coords for texture variation |

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

Each column's ray angle is `atan(col-offset / fov-proj-dist)`. Making the terminal wider expands FOV without scaling walls. A linear sweep would scale walls with width - wrong.

FOV is clamped at 90°. `fov-proj-dist` returns the flat `proj-dist` below `fov-clamp-width` (= `2 * proj-dist` = 140 cols), so narrow terminals widen naturally (80 cols ~60°, 120 cols ~81°). At or above 140 cols it scales `proj-dist` up with width, pinning the horizontal FOV at 90° so ultrawide terminals gain horizontal resolution instead of bowing out into edge fisheye. Wall-height projection still uses the flat `proj-dist`, so the clamp never touches wall scale.

### Fish-eye correction

Edge rays travel further than central rays to reach the same wall plane. Multiply by `cos(offset)` to project onto the player's forward axis. One multiply per column; without it: barrel distortion.

## Performance

DDA averages ~5-8 cell crossings per ray instead of ~35 fixed steps. Hot loop uses direct PHP ops (`php/+`, `php/<`) and `:pgrid` (nested PHP array).

## Caching (two memo atoms)

Two private atoms memoize input-determined data, preserving referential transparency:

- `offset-cache`: per-column FOV offsets (depends only on width, not state). Built once per width.
- `pause-cast-cache`: single-slot copy consulted only while paused (player x/y/angle + grid frozen, so cast is identical to previous frame). Active frames never touch it, so pause overlays and help menu are free.

## Why `core/`

Pure deterministic logic: given grid, position, and angle, always same output. The two memo caches are input-determined (see Caching), so calls remain pure. Tests verify distance accuracy, side bits, hit-cell coords, and array lengths.
