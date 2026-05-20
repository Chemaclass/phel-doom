# Raycaster

Lives in `src/modules/core/engine.phel`. Computes per-column wall
distances by stepping rays through the grid.

## What raycasting is

For each screen column, fire a ray from the player into the world
along an angle slightly offset from the player's facing. Walk it
forward in small steps until it hits a non-floor cell. The distance
travelled = how far that column's wall is from the player → wall
height for that column.

This is the original DOOM / Wolfenstein technique. No 3D math, just
2D ray-marching with a perspective scale.

## Tunables

```phel
(def max-depth 12.0)   ; rays stop after this many world units
(def step      0.35)   ; how far each ray step advances
(def proj-dist 70.0)   ; perspective constant; see below
```

`max-depth` caps how far walls can be drawn — beyond this the column
just paints sky/floor. `step` trades accuracy for ray-cost; smaller =
sharper wall placement, more iterations per ray.

## `cast-ray-hit` — one ray

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

Returns a 5-tuple per ray:

| Index | Meaning |
|---|---|
| `dist` | Travelled distance (not yet fish-eye corrected) |
| `hit-cell` | Cell value the ray landed on (0 = escaped to max-depth) |
| `hx, hy` | Integer cell coords of the hit cell |
| `side` | 0 if the ray crossed an x-axis boundary last (vertical wall face), 1 if a y-axis boundary (horizontal face) |

The `side` value is the key to **Wolfenstein-style directional
shading** — render layer darkens vertical-face columns by one shade
step, so corners read as corners. `(hx, hy)` feeds a per-cell hash
in the renderer that adds subtle mottling so a long corridor isn't
one flat band.

## `cast-frame` — all rays at once

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

Returns five parallel PHP arrays, one entry per screen column. The
renderer indexes them by column.

## Two subtleties

### Angular offset, not horizontal sweep

```phel
offset = atan((col - center) / proj-dist)
```

Each column has its own ray angle, computed as the arctangent of the
column's horizontal offset from the centre divided by `proj-dist`.
This gives a **constant wall scale** regardless of viewport width:
making the terminal wider expands the field of view (you see more of
the world), but a wall 5 cells away still looks the same height.

A naïve raycaster sweeps angles linearly across an FOV — that grows
walls proportionally to viewport width, which feels wrong when you
resize a terminal.

### Fish-eye correction

```phel
(php/* d (php/cos offset))
```

A straight wall in front of the player will hit further-away columns
at greater raw distances simply because rays at the edge of the FOV
have to travel further to reach the same wall plane. Multiplying by
`cos(offset)` projects the distance onto the player's forward axis,
flattening the wall back to a straight line.

Without this, walls bow outward toward the screen edges (the
"fish-eye" effect). One multiplication per column makes them flat.

## Per-ray cost

Roughly `max-depth / step` = 12 / 0.35 ≈ 35 iterations per ray. At
180 columns that's ~6300 iterations per frame just for the cast
phase. Hot enough that we use direct PHP ops (`php/+`, `php/<`,
`php/aget`) inside the loop instead of Phel's polymorphic equivalents.

Could be ~5× faster with grid-aligned DDA (jump cell-to-cell instead
of stepping), but the simpler step-march is fast enough at terminal
resolutions and easier to reason about. See [performance.md](performance.md)
for the rest of the hot-loop tricks.

## Why the raycaster lives in `core/`

It's a pure function: `(pgrid, x, y, angle) → distance`. No state,
no IO, deterministic. Test files in `tests/modules/core/engine-test.phel`
exercise it with literal grids.
