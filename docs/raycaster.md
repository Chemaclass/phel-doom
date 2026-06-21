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
  ...returns {:dists :hits :sides :hxs :hys :wallxs :floordxs :floordys
              :step-dists :step-fzs :step-sides :step-hxs :step-hys
              :ceil-dists :ceil-czs :ceil-sides})
```

Cast `width / scale` rays; return the parallel PHP arrays (one per output column).
- `dists`: fish-eye corrected wall distance
- `hits`: cell value at hit (0 if escaped to max-depth)
- `sides`: 0 = vertical, 1 = horizontal (side-shading)
- `hxs, hys`: hit cell coordinates
- `wallxs`: wall-hit fraction in [0, 1) - the texture U coordinate (frac of world-y on a vertical face, world-x on a horizontal face, from the raw perpendicular distance)
- `floordxs, floordys`: floor-cast basis = ray direction / cos(offset). A floor cell at per-row perpendicular distance `dperp` sits at world `player + dperp * (floordx, floordy)`, so the renderer needs no per-cell trig (two mul-adds + a frac for the texture sample)
- `step-dists, step-fzs, step-sides, step-hxs, step-hys`: per-cell floor-height riser side-channel (#232, see below). Each entry is nil per column when the ray crossed no raised floor, so a flat world leaves them all-nil (additive contract).
- `ceil-dists, ceil-czs, ceil-sides`: per-cell ceiling-height drop side-channel (#235, see below). Each entry is nil per column when the ray crossed no ceiling that drops below the viewer's ceiling, so a flat (all-1.0) ceiling leaves them all-nil (additive contract).

## Per-cell floor heights (#232)

A second per-cell grid, `:floor-pgrid` (a PHP `float[][]` twin of `:pgrid`, same shape, all `0.0` by default), gives each cell the world `z` its floor sits at. The DDA march carries one extra accumulator, `step-acc`: scanning outward it records the FIRST floor cell it crosses whose height rises above the player's own floor (`:floor-z`, today always 0). That first riser is pinned (the nearest one occludes farther steps) and surfaced as the additive `:step-*` arrays:

| Field | Meaning |
|---|---|
| `step-dists` | fish-eye corrected distance to the riser (or nil) |
| `step-fzs`   | the riser cell's floor height (world z) |
| `step-sides` | 0/1 face of the crossed boundary (EW shading, like walls) |
| `step-hxs, step-hys` | integer coords of the riser cell |

The accumulator is computed as nested `if` in the loop's tail position (never `and`, never a `let`-binding statement-form), so it compiles closure-free and the flat all-zero floor never trips the `fh > player-floor-z` test - the cast stays allocation-equivalent to the pre-#232 path (verified by diffing the compiled `out/` do-cast: still 5 closures, none new in the DDA loop).

The renderer (`compute-wall-shades` + the px1 cell loop, see [rendering.md](rendering.md)) turns each riser into a vertical **riser face** plus a **cap** (the step top surface), painted into the floor band below the main wall (the nearer wall always wins its own rows). The cap rows are claimed before the floor-cast clause so the ground texture does not also paint them. Since #236 the cap is itself a textured floor sample (`floor-cap-px`): the same stone + fog as the ground, projected at the cap's height (the ground distance scaled by `(eye-z - fz)/eye-z`), so a step top reads as continuous stone rather than a flat patch. A flat world leaves every `:step-*` entry nil, so the riser/cap branches are dead and the frame is byte-identical (pinned by `render-cache-test/test-frame-bytes-pinned`). Z physics (stepping up onto the riser) lands in #233.

## Per-cell ceiling heights (#235)

The exact mirror of the floor riser, on the ceiling axis. A third per-cell grid, `:ceil-pgrid` (a PHP `float[][]` twin of `:pgrid`, same shape, all `1.0` by default - the ceiling at the top of a one-unit wall), gives each cell the world `z` its ceiling sits at. The DDA march carries a SECOND accumulator alongside `step-acc`, `ceil-acc`: scanning outward it records the FIRST ceiling cell it crosses whose height DROPS below the viewer's own ceiling (`viewer-ceil-z`, today always 1.0). A height above 1.0 lifts the ceiling (a tall atrium - just extra headroom, no hanging edge, so the accumulator does NOT fire); a height below 1.0 drops it (a low tunnel / hanging ceiling). That first drop is pinned (the nearest one occludes farther ones) and surfaced as the additive `:ceil-*` arrays:

| Field | Meaning |
|---|---|
| `ceil-dists` | fish-eye corrected distance to the ceiling drop (or nil) |
| `ceil-czs`   | the dropped cell's ceiling height (world z, < viewer ceiling) |
| `ceil-sides` | 0/1 face of the crossed boundary (EW shading, like walls) |

Like `step-acc`, the ceiling accumulator is computed as nested `if` in the loop's tail position (never `and`, never a `let`-binding statement-form), reading the cell's ceiling height through the same `let` already present for the floor height, so it compiles closure-free and the flat all-1.0 ceiling never trips the `ch < viewer-ceil-z` test - the cast stays allocation-equivalent to the pre-#235 path (verified by diffing the compiled `out/` `engine.php`: identical `function`-token count to HEAD, no new closure in the DDA loop).

The renderer (`compute-wall-shades` + the px1 cell loop, see [rendering.md](rendering.md)) turns each drop into a vertical **hanging face** plus a flat-shaded **cap** (the ceiling underside), hanging from the top of the view: the face top is the viewer-ceiling plane (z 1.0) projected at the drop distance, the boundary row is the dropped-ceiling plane at the same distance, and the cap recedes back to the main wall top. It is painted into the ceiling band above the main wall (the nearer wall always wins its own rows), claimed before the sky-cast clause so the sky does not also paint it. A flat ceiling leaves every `:ceil-*` entry nil, so the hanging-ceiling branches are dead and the frame is byte-identical (pinned by `render-cache-test/test-frame-bytes-pinned`). Levels opt in via an optional `:ceil-heights` map; none ship yet, so the world stays flat-ceilinged. Textured ceiling caps follow with the floor caps in #236.

## Two key details

### Angular offset, not linear sweep

Each column's ray angle is `atan(col-offset / fov-proj-dist)`. Making the terminal wider expands FOV without scaling walls. A linear sweep would scale walls with width - wrong.

FOV is clamped at `fov-max-deg` (100°, the widescreen sweet spot - roomy without warp). `fov-proj-dist` returns the flat `proj-dist` below `fov-clamp-width` (~167 cols, derived so the natural FOV reaches 100° there), so narrow terminals widen naturally (80 cols ~60°, 120 cols ~81°, 140 cols ~90°). At or above the clamp width it scales `proj-dist` up with width, pinning the horizontal FOV at 100° so ultrawide terminals gain horizontal resolution instead of bowing out into edge fisheye (which set in past ~110°). Wall-height projection still uses the flat `proj-dist`, so the clamp never touches wall scale.

### Fish-eye correction

Edge rays travel further than central rays to reach the same wall plane. Multiply by `cos(offset)` to project onto the player's forward axis. One multiply per column; without it: barrel distortion.

## Projection primitive

`src/core/projection.phel` holds the pure vertical-projection kernel shared by the wall paths (and, ahead, variable floor/ceiling heights, pitch, eye-height):

```phel
(wall-px num dist)                 ; projected pixel height of a num-unit
                                   ; surface at distance dist
(project-height pd vh dist eye-z z); screen row (float) where world height
                                   ; z lands
(pitch-rows pitch vh)              ; integer horizon shear (scene rows) for
                                   ; a look up/down fraction
(sprite-feet-row pd svh dist       ; integer screen row where an enemy's
                 eye-z fz pr)      ; FEET stand (the projected cell floor)
```

- `wall-px num dist` = `num / ((max 0.3 dist) * char-aspect)`. `num` is `proj-dist` for a one-unit wall, or `n * proj-dist` for an n-sub-row half-block slice. The 0.3 floor stops a surface in the player's own cell projecting to an infinite slice. Both the cell-resolution wall path (`compute-wall-shades`) and the half-block sub-pixel path (`build-wall-sub-bounds`) call it, so they agree to the last bit.
- `project-height pd vh dist eye-z z` = `vh/2 - (z - eye-z) * (wall-px pd dist)`. The horizon (z = eye-z) sits at `vh/2`; points above the eye rise, below sink. Today's flat wall is the special case `eye-z = 0.5` with `z = 1` (top) and `z = 0` (bottom). Variable heights pass other `z`; jump/crouch pass other `eye-z`.
- `sprite-feet-row pd svh dist eye-z fz pr` = `round(project-height pd svh dist eye-z fz) + pr`. The screen row where an enemy billboard's FEET stand: the projection of its cell floor surface (world height `fz`) plus the pitch shear. On flat ground (`fz = 0`, `eye-z = 0.5`) this is the same row the floor texture meets the wall, so the sprite stands ON the floor. `project-height` at `z = fz` already folds in the raised floor, so callers must NOT also subtract a separate floor offset (doing so double-counts the lift). See "Sprite anchoring" below.
- `char-aspect` (2.0) lives here too, as the canonical projection constant alongside `proj-dist`, so the kernel stays pure `core/` with no `io/` dependency.

## Look up/down (pitch): horizon shear

Looking up/down is a pure **vertical shear of the horizon**, not a re-projection: it costs no extra rays. The player carries `:pitch`, a fraction in `[-1, 1]` (1 = full up, -1 = full down, clamped by `state/clamp-pitch`, no wrap). `pitch-rows pitch vh` = `round(pitch * pitch-cap * vh)` turns it into an **integer scene-row offset** `pr`, where `pitch-cap` = 0.4, so the horizon travels at most +/-0.4 of the viewport height. Positive pitch (look up) yields positive `pr`, sliding the horizon DOWN the screen (more sky), negative slides it up.

`frame->string` computes `pr` once and adds it to every site that centres on `vh/2`, so the whole scene shears as one rigid band:

- wall tops in `compute-wall-shades` (`top = (vh - wall-h)/2 + pr`; `bot` derives from `top`)
- the sub-row seam bounds in `build-wall-sub-bounds` (`+ pr*n`, n sub-rows per scene cell)
- the floor-cast distance tables `build-floor-dperp` / `build-floor-dperp-sub` (horizon `vh/2 + pr`, sub-row `vh + 2*pr`)
- the sky/floor gradients and their code twins in `frame-math` (each gradient builder takes an optional `horizon-offset`; the gradient cache keys on `(vh, pr)`)
- enemy sprite anchors (`sprite-feet-row` carries the same `pr`, so the feet, the grounding shadow, and the face / HP-flash overlays all shear together with the floor; see "Sprite anchoring")

The crosshair stays fixed (it is a weapon sight, not part of the world). Because every offset is **additive and 0 at `pitch = 0`**, a level gaze renders byte-for-byte identically to the no-pitch path (pinned by `render-cache-test/test-frame-bytes-pinned`).

## Sprite anchoring (feet on the floor)

Enemy billboards are anchored by their **feet**, not their centre (issue #297). The renderer stands each sprite on `sprite-feet-row` and draws the body UPWARD by its pixel height `h`:

```
feet-row = (sprite-feet-row scene-pd svh dist eye-z fz pr)   ; on the floor
e-top    = feet-row - h                                       ; head
body     = rows [e-top, feet-row]
```

`fz` is the enemy's cell floor height (read from `:floor-pgrid`, 0 on flat ground). A raised cell (the L5 dais `fz 0.8`, the L7 ledge `fz 1.05`) projects `feet-row` higher up the screen, so the monster stands ON its platform; the raise lives entirely inside `project-height`, so the renderer never adds a second floor offset. The grounding shadow, the face glyph, and the floating HP digit all derive from this one `feet-row`, so they track the feet on flat AND raised ground.

The **old** anchor centred the billboard on the horizon (`(svh - h)/2 + pr - floor-off`), which left the feet hanging one row above the projected floor at most distances - the reported "enemies float" bug. The feet anchor lands the feet exactly on the floor surface row at every distance.

### Hitscan agreement

`enemy/vertical-hit?` reuses the SAME `sprite-feet-row`, so the vertical aim gate and the drawn pixels cannot disagree (issues #243 / #291 / #297). A shot connects when the FIXED screen-centre crosshair (`svh/2` - it does not shear with pitch) lands inside the drawn body:

```
hit?  =  (feet-row - h) <= svh/2 <= feet-row
```

Because `feet-row` carries `pr` but the crosshair does not, looking up slides a sprite DOWN past the centre and looking down lifts it UP, so a short far billboard slips off the crosshair (vertical aim) while a tall near one stays caught. On a raised cell the lift moves the body above the centre at level aim, so the player looks up to put the crosshair back on the drawn sprite.

### Cross-tier occlusion (issue #302)

Feet anchoring (#297/#300) gives an enemy on another tier the right vertical PLACEMENT; cross-tier occlusion is the visibility half. An enemy billboard is a transparent sprite clipped per column by a depth gate. Before #302 that gate was the full-height WALL buffer (`dists[c]`) alone, so the partial-height tier geometry - the floor risers (#232) and hanging ceilings (#235) - was invisible to it: an enemy tucked behind a nearer step could draw THROUGH it, and one on a higher tier could clip wrong against the edge.

The clip now also intersects each sprite column against the NEARER tier band in that column. The pure helper is `clip-sprite-span` in `core/projection.phel`:

```
(clip-sprite-span e-top e-bot step-d step-from ceil-d ceil-bots d)
;; -> [top bot]  the visible rows, or
;; -> nil        when a nearer tier fully covers the column
```

- `step-d`/`step-from` are the column's nearest floor-riser distance (`step-dists[c]`) and the riser band's on-screen TOP row (`shades-step-from[c]`). A riser NEARER than the sprite (`step-d < d`) hides every row at or below `step-from`, so the feet clamp to `min(e-bot, step-from)` - the near riser face plus the near-tier floor in front of it block the lower body.
- `ceil-d`/`ceil-bots` are the column's nearest ceiling-drop distance (`ceil-dists[c]`) and the ceiling band's on-screen BOTTOM lip (`shades-ceil-bots[c]`). A drop NEARER than the sprite (`ceil-d < d`) hides every row above the lip, so the head clamps to `max(e-top, ceil-bots)`.
- A farther or absent tier is ignored. The band values are read only when the matching distance is present, so the sentinel `svh` a riserless / ceilingless column carries never reaches the `max`/`min` (the ceiling `max` would otherwise swallow the whole span). When the two clamps cross (`top >= bot`) the sprite is fully occluded and the column is skipped.

So an enemy on a higher tier shows over a platform edge (its feet project above the nearer riser's top, nothing to clip), one standing below behind a nearer step has its legs cut, and one fully behind the step vanishes - exactly where the line of sight is geometrically clear. The clip only INTERSECTS the projected span; it never re-derives the projection. A FLAT level carries nil for `step-dists`/`ceil-dists` in every column, so both guards are false, the span is returned unchanged, and the render is byte-identical (pinned by `render-cache-test/test-frame-bytes-pinned`).

Scope (px1, single nearest tier): the cast keeps only the NEAREST riser + ceiling per column, so an enemy sandwiched between two near tiers is clipped against the nearer one alone (no multi-tier stacking). The pixel-doubled cast (`compact-cast-2`) drops the tier arrays, so px2 keeps the old wall-only gate. The grounding shadow / face / HP-flash overlays still reuse the wall `dists` gate and can bleed past a riser (cosmetic fast-follow). See [rendering.md](rendering.md) for where the clip sits in the zone pass.

## Performance

DDA averages ~5-8 cell crossings per ray instead of ~35 fixed steps. Hot loop uses direct PHP ops (`php/+`, `php/<`) and `:pgrid` (nested PHP array).

## Caching (two memo atoms)

Two private atoms memoize input-determined data, preserving referential transparency:

- `offset-cache`: per-column FOV offsets (depends only on width, not state). Built once per width.
- `pause-cast-cache`: single-slot copy consulted only while paused (player x/y/angle + grid frozen, so cast is identical to previous frame). Active frames never touch it, so pause overlays and help menu are free.

## Why `core/`

Pure deterministic logic: given grid, position, and angle, always same output. The two memo caches are input-determined (see Caching), so calls remain pure. Tests verify distance accuracy, side bits, hit-cell coords, and array lengths.
