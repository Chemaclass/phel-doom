# Raycaster

`src/modules/core/engine.phel`. Per-column wall distances via ray-stepping through the grid.

## What raycasting is

For each screen column, fire a ray from the player along an angle offset from facing. Walk forward in small steps until it hits a non-floor cell. Distance travelled sets that column's wall height.

Original DOOM / Wolfenstein technique. No 3D math, 2D ray-marching with a perspective scale.

## Tunables

```phel
(def max-depth 12.0)   ; rays stop after this many world units
(def step      0.35)   ; how far each ray step advances
(def proj-dist 70.0)   ; perspective constant; see below
```

`max-depth` caps how far walls draw; beyond paints sky/floor. `step` trades accuracy for cost: smaller = sharper, more iterations per ray.

## `cast-ray-hit`: one ray

```phel
(defn- cast-ray-hit [pgrid px py angle]
  (let [dx (php/* (php/cos angle) step)
        dy (php/* (php/sin angle) step)]
    (loop [dist 0.0 x px y py
           prev-cx (php/intval px)]
      (let [cx  (php/intval x)
            cy  (php/intval y)
            hit (cell-at pgrid cx cy)]
        (cond
          (php/>= dist max-depth) [max-depth 0 cx cy 0]
          (php/!== 0 hit)
          (let [side (if (php/!== cx prev-cx) 0 1)]
            [dist hit cx cy side])
          :else
          (recur (php/+ dist step) (php/+ x dx) (php/+ y dy) cx))))))
```

5-tuple per ray:

| Index | Meaning |
|---|---|
| `dist` | Travelled distance (not yet fish-eye corrected) |
| `hit-cell` | Cell value the ray landed on (0 = escaped to max-depth) |
| `hx, hy` | Integer cell coords of the hit cell |
| `side` | 0 if last crossing was x-axis (vertical wall face), 1 if y-axis (horizontal face) |

`side` enables Wolfenstein-style directional shading: render layer darkens vertical-face columns by one shade step, so corners read as corners. `(hx, hy)` feeds a per-cell hash in the renderer that adds subtle mottling so a long corridor isn't one flat band.

## `cast-frame`: all rays at once

```phel
(defn cast-frame [world width]
  (let [...
        dists (php/array) hits (php/array) hxs (php/array)
        hys (php/array) sides (php/array)]
    (loop [col 0]
      (when (php/< col width)
        (let [offset (php/atan (/ (php/- col center) proj-dist))]
          (let [[d h hx hy side] (cast-ray-hit pgrid x y (php/+ angle offset))]
            (php/aset dists col (php/* d (php/cos offset)))   ; fish-eye correct
            (php/aset hits  col h)
            (php/aset hxs   col hx)
            (php/aset hys   col hy)
            (php/aset sides col side))
          (recur (php/+ col 1)))))
    {:dists dists :hits hits :hxs hxs :hys hys :sides sides}))
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

`max-depth / step` = 12 / 0.35 ≈ 35 iterations per ray. At 180 columns that's ~6300 iterations per frame for the cast phase. Hot enough that the loop uses direct PHP ops (`php/+`, `php/<`, `php/aget`).

Could be ~5× faster with grid-aligned DDA (jump cell-to-cell), but step-march is fast enough at terminal resolutions and easier to reason about. See [performance.md](performance.md) for the rest.

## Why the raycaster lives in `core/`

Pure function: `(pgrid, x, y, angle) → distance`. No state, no IO, deterministic. `tests/modules/core/engine-test.phel` exercises with literal grids.
