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
- `fov-proj-dist`: width-aware projection distance for ray spread; clamps FOV at 100° (`fov-max-deg`) on wide terminals (see Angular offset below)

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
  ...returns {:dists :hits :sides :hxs :hys :wallxs :floordxs :floordys :spans})
```

Cast `width / scale` rays; return the parallel PHP arrays (one per output column).
- `dists`: fish-eye corrected wall distance
- `hits`: cell value at hit (0 if escaped to max-depth)
- `sides`: 0 = vertical, 1 = horizontal (side-shading)
- `hxs, hys`: hit cell coordinates
- `wallxs`: wall-hit fraction in [0, 1) - the texture U coordinate (frac of world-y on a vertical face, world-x on a horizontal face, from the raw perpendicular distance)
- `floordxs, floordys`: floor-cast basis = ray direction / cos(offset). A floor cell at per-row perpendicular distance `dperp` sits at world `player + dperp * (floordx, floordy)`, so the renderer needs no per-cell trig (two mul-adds + a frac for the texture sample)
- `spans`: flat riser-event stream for floor heights (see Multi-span cast below); empty on flat frames

## Multi-span cast: floor risers

Issue #369 (epic #375): the DDA no longer treats the first hit as the whole story. While marching, each cell boundary where the floor height (`:pfz`, see map.md) RISES emits one span event - the visible riser face between the two tiers - and the march continues to the real wall (or max-depth) exactly as before. The classic 8 arrays keep holding the final wall hit, which is always the LAST span of a column; on a flat map the stream is empty and the arrays alone describe the frame.

`:spans` is one flat PHP array, stride 8 per event:

| slot | field | meaning |
|---|---|---|
| +0 | col | the ray's BASE output column (one event per ray; with scale > 1 the render layer fans out, same as wall samples) |
| +1 | d-corr | fish-eye corrected distance to the riser boundary |
| +2 | z0 | floor height of the cell being left (riser bottom) |
| +3 | z1 | floor height of the cell being entered (riser top) |
| +4 | side | 0 = x-line, 1 = y-line - same convention as `sides` |
| +5 | hx, +6 hy | integer coords of the entered (higher) cell |
| +7 | wallx | texture U in [0, 1) at the crossing, same formula as `wallxs` |

Guarantees and rules:

- **Rise-only.** Step-downs are backfaces (invisible from above) and never emit. The march still tracks the current cell height across drops, so a down-then-up profile emits the second riser with the correct `z0`.
- **Ordering.** Events arrive in ascending distance within a ray and ascending base col across rays - render can scan the stream once.
- **Occlusion.** A riser behind a wall/door/secret never emits: blocking cells exit the march before the height check.
- **No early-out.** The march always reaches the wall/max-depth; deciding that stacked risers fill a screen column needs projection (eye height, pitch), which is render's knowledge (#370). Authorable heights cap at fz 0.75 (layout digits 1-3), so no riser can fill a column by itself.
- **Cost.** Zero on flat worlds: `new-world` / `rebuild-pgrid` stamp a build-time `:fz-flat?` flag, and do-cast selects the legacy 4-var march (no fz reads, no extra loop var) when it is set - measured, the always-on span march cost +13-16% cast time on flat maps. Tiered worlds run the span march: one subscript + float compare per continue step, plus the event push at each rise.

## Two key details

### Angular offset, not linear sweep

Each column's ray angle is `atan(col-offset / fov-proj-dist)`. Making the terminal wider expands FOV without scaling walls. A linear sweep would scale walls with width - wrong.

FOV is clamped at `fov-max-deg` (100°, the widescreen sweet spot - roomy without warp). `fov-proj-dist` returns the flat `proj-dist` below `fov-clamp-width` (~167 cols, derived so the natural FOV reaches 100° there), so narrow terminals widen naturally (80 cols ~60°, 120 cols ~81°, 140 cols ~90°). At or above the clamp width it scales `proj-dist` up with width, pinning the horizontal FOV at 100° so ultrawide terminals gain horizontal resolution instead of bowing out into edge fisheye (which set in past ~110°). Wall-height projection still uses the flat `proj-dist`, so the clamp never touches wall scale.

### Fish-eye correction

Edge rays travel further than central rays to reach the same wall plane. Multiply by `cos(offset)` to project onto the player's forward axis. One multiply per column; without it: barrel distortion.

## Projection primitive

`src/core/projection.phel` holds the pure vertical-projection kernel shared by the wall paths:

```phel
(wall-px num dist)                 ; projected pixel height of a num-unit
                                   ; surface at distance dist
(project-height pd vh dist eye-z z); screen row (float) where world height
                                   ; z lands
(pitch-rows pitch vh)              ; integer horizon shear (scene rows) for
                                   ; a look up/down fraction
```

- `wall-px num dist` = `num / ((max 0.3 dist) * char-aspect)`. `num` is `proj-dist` for a one-unit wall, or `n * proj-dist` for an n-sub-row half-block slice. The 0.3 floor stops a surface in the player's own cell projecting to an infinite slice. Both the cell-resolution wall path (`compute-wall-shades`) and the half-block sub-pixel path (`build-wall-sub-bounds`) call it, so they agree to the last bit.
- `project-height pd vh dist eye-z z` = `vh/2 - (z - eye-z) * (wall-px pd dist)`. The horizon (z = eye-z) sits at `vh/2`; points above the eye rise, below sink. The flat wall is the case `eye-z = 0.5` with `z = 1` (top) and `z = 0` (bottom).
- `char-aspect` (2.0) lives here too, as the canonical projection constant alongside `proj-dist`, so the kernel stays pure `core/` with no `io/` dependency.

## Look up/down (pitch): horizon shear

Looking up/down is a pure **vertical shear of the horizon**, not a re-projection: it costs no extra rays. The player carries `:pitch`, a fraction in `[-1, 1]` (1 = full up, -1 = full down, clamped by `state/clamp-pitch`, no wrap). `pitch-rows pitch vh` = `round(pitch * pitch-cap * vh)` turns it into an **integer scene-row offset** `pr`, where `pitch-cap` = 0.4, so the horizon travels at most +/-0.4 of the viewport height. Positive pitch (look up) yields positive `pr`, sliding the horizon DOWN the screen (more sky), negative slides it up.

`frame->string` computes `pr` once and adds it to every site that centres on `vh/2`, so the whole scene shears as one rigid band:

- wall tops in `compute-wall-shades` (`top = (vh - wall-h)/2 + pr`; `bot` derives from `top`)
- the sub-row seam bounds in `build-wall-sub-bounds` (`+ pr*n`, n sub-rows per scene cell)
- the floor-cast distance tables `build-floor-dperp` / `build-floor-dperp-sub` (horizon `vh/2 + pr`, sub-row `vh + 2*pr`)
- the sky/floor gradients and their code twins in `frame-math` (each gradient builder takes an optional `horizon-offset`; the gradient cache keys on `(vh, pr)`)
- enemy sprite anchors (the flat z=0 feet row carries the same `pr`, so the feet, the grounding shadow, and the face / HP-flash overlays all shear together with the floor; see "Sprite anchoring")

The crosshair stays fixed (it is a weapon sight, not part of the world). Because every offset is **additive and 0 at `pitch = 0`**, a level gaze renders byte-for-byte identically to the no-pitch path (pinned by `render-cache-test/test-frame-bytes-pinned`).

## Sprite anchoring (feet on the floor)

Enemy billboards are anchored by their **feet**, not their centre. The renderer stands each sprite on a projected row and draws the body UPWARD by its pixel height `h`. On flat ground the feet land exactly on the floor surface row at every distance. The grounding shadow, the face glyph, and the floating HP digit all derive from this row anchor.

### Hitscan agreement

Hitscan reuses the same foot-row projection, so the vertical aim gate and the drawn pixels stay in sync. A shot connects when the FIXED screen-centre crosshair (`svh/2` - it does not shear with pitch) lands inside the drawn body. Looking up slides a sprite DOWN past the centre and looking down lifts it UP, so a short far billboard slips off the crosshair (vertical aim) while a tall near one stays caught.

## Performance

DDA averages ~5-8 cell crossings per ray instead of ~35 fixed steps. Hot loop uses direct PHP ops (`php/+`, `php/<`) and `:pgrid` (nested PHP array).

## Caching (two memo atoms)

Two private atoms memoize input-determined data, preserving referential transparency:

- `offset-cache`: per-column FOV offsets (depends only on width, not state). Built once per width.
- `pause-cast-cache`: single-slot copy consulted only while paused (player x/y/angle + grid frozen, so cast is identical to previous frame). Active frames never touch it, so pause overlays and help menu are free.

## Why `core/`

Pure deterministic logic: given grid, position, and angle, always same output. The two memo caches are input-determined (see Caching), so calls remain pure. Tests verify distance accuracy, side bits, hit-cell coords, and array lengths.
