# Raycaster

`src/core/engine.phel`. Per-column wall distances via grid-aligned DDA traversal.

For each screen column, fire a ray from the player at an angle offset from facing. Walk the grid until the ray hits a non-floor cell. The distance sets that column's wall height (Wolfenstein-style 2D ray march, no 3D math).

## Tunables

- `max-depth` (12.0): the ray stops here. Beyond it renders sky and floor.
- `proj-dist` (70.0): perspective constant in screen cells. Controls wall scale.
- `fov-proj-dist`: width-aware projection distance for the ray spread. Clamps FOV at 100° (`fov-max-deg`) on wide terminals. See [Angular offset](#angular-offset-not-linear-sweep).
- `dda-inf` (1e9): finite sentinel for an axis-aligned ray direction. Avoids PHP's `INF` edge cases.

## DDA: grid-aligned traversal

Step grid line to grid line, not at fixed intervals. Two per-axis side distances track the next x and y crossing. Each step advances the nearer one, lands in the next cell, and adds that axis's `|1/dir|` delta. A ray takes ~5-8 cell crossings instead of ~35 fixed steps.

```phel
(let [stepx  (if (php/< dirx 0.0) -1 1)
      deltax (if (php/=== dirx 0.0) dda-inf (php/abs (php// 1.0 dirx)))
      sidex0 (if (php/< dirx 0.0)
               (php/* x-to-lo deltax)    ; distance to the cell's low x edge
               (php/* x-to-hi deltax))]  ; ... or high x edge
  ...)                                   ; same for y
```

The player's cell and its edge offsets are hoisted out of the per-column loop. The march runs in statement position and writes `[dist hit side hx hy]` into one reused PHP-array register, so it compiles to a plain `while` with no per-column closure (issue #345, see [performance.md](performance.md)). The map is read through `:pgrid`, a nested PHP array.

## `cast-ray`: one ray

Returns the raw (uncorrected) distance only. Used by the hitscan (`combat`) and the enemy line-of-sight probe (`enemy_ai`), which only need the distance.

## `cast-frame`: all rays at once

```phel
(cast-frame world width scale)
;; => {:dists :hits :sides :hxs :hys :wallxs :floordxs :floordys}
```

Casts `width / scale` rays and returns parallel PHP arrays, one entry per output column. With `scale` > 1 each sample fills `scale` neighbouring columns.

| Key | Meaning |
|---|---|
| `dists` | fish-eye corrected wall distance |
| `hits` | cell value at the hit (0 if the ray escaped to `max-depth`) |
| `sides` | 0 = vertical face, 1 = horizontal face (side shading) |
| `hxs`, `hys` | hit cell coordinates (texture variation) |
| `wallxs` | wall-hit fraction in [0, 1): the texture U coordinate |
| `floordxs`, `floordys` | floor-cast basis: ray direction / cos(offset) |

A floor cell at per-row perpendicular distance `dperp` sits at world `player + dperp * (floordx, floordy)`, so the renderer needs no per-cell trig.

## Angular offset, not linear sweep

Each column's ray angle is `atan(col-offset / fov-proj-dist)`. A wider terminal widens the FOV without scaling walls. A linear sweep would scale walls with width.

Below `fov-clamp-width` (~167 cols, where the natural FOV hits 100°) `fov-proj-dist` returns the flat `proj-dist`, so narrow terminals widen naturally (80 cols ~60°, 120 cols ~81°, 140 cols ~90°). At or above it, the distance scales with width and pins the FOV at 100°. Ultrawide terminals gain horizontal resolution instead of edge fisheye, which sets in past ~110°. Wall height still uses the flat `proj-dist`.

## Fish-eye correction

Edge rays travel further than central rays to reach the same wall plane. Multiplying by `cos(offset)` projects onto the player's forward axis. One multiply per column. Without it: barrel distortion.

## Projection primitive

`src/core/projection.phel` holds the pure vertical-projection kernel shared by the wall paths:

```phel
(wall-px num dist)                  ; projected height of a num-unit surface
(project-height pd vh dist eye-z z) ; screen row (float) where height z lands
(pitch-rows pitch vh)               ; integer horizon shear for a pitch fraction
```

- `wall-px` = `num / ((max 0.3 dist) * char-aspect)`. `num` is `proj-dist` for a one-unit wall, or `n * proj-dist` for an n-sub-row half-block slice. The 0.3 floor stops a surface in the player's own cell projecting to infinity. The cell-resolution path (`compute-wall-shades`) and the half-block path (`build-wall-sub-bounds`) both call it, so they agree to the last bit.
- `project-height` = `vh/2 - (z - eye-z) * (wall-px pd dist)`. The horizon sits at `vh/2`. The flat wall is `eye-z = 0.5`, top `z = 1`, bottom `z = 0`.
- `char-aspect` (2.0) lives here too, so the kernel stays pure `core/` with no `io/` dependency.

## Look up/down (pitch): horizon shear

Looking up or down is a vertical shear of the horizon, not a re-projection, so it costs no extra rays. The player carries `:pitch` in `[-1, 1]` (clamped by `state/clamp-pitch`). `pitch-rows` = `round(pitch * pitch-cap * vh)`, with `pitch-cap` = 0.4, gives an integer scene-row offset `pr`. Positive pitch (look up) slides the horizon down the screen, showing more sky.

`frame->string` computes `pr` once and adds it everywhere the scene centres on `vh/2`:

- wall tops in `compute-wall-shades` (`top = (vh - wall-h)/2 + pr`)
- sub-row seam bounds in `build-wall-sub-bounds` (`+ pr*n`)
- floor-cast distance tables `build-floor-dperp` / `build-floor-dperp-sub`
- sky and floor gradients in `frame-math` (the gradient cache keys on `(vh, pr)`)
- enemy sprite feet rows, so feet, shadow and overlays shear with the floor

The crosshair stays fixed: it is a weapon sight, not part of the world. Every offset is additive and 0 at `pitch = 0`, so a level gaze renders byte-for-byte like the no-pitch path (pinned by `render-cache-test/test-frame-bytes-pinned`).

### Head bob: a second term into `pr` (#411)

The walk-cycle head bob adds another horizon shear on top of pitch. `bob-rows` = `round(intensity * bob-cap * vh * sin(phase))`, with `bob-cap` = 0.05. `phase` is the world's `:bob-phase`, advanced by ground distance in `physics/apply-physics` and settled to 0 at rest. `intensity` comes from the View bob setting (default 0, off). A resting or bob-off frame is byte-identical to no bob. The bob never reaches the hit gate: `combat/aim-pr` uses true pitch only, so the nod cannot move where a shot lands.

## Sprite anchoring and hitscan

Enemy billboards stand on their feet: the renderer places each sprite on its projected floor row and draws the body upward by its pixel height. Shadow, face glyph and floating HP digit derive from that row.

Hitscan reuses the same projection. A shot connects when the fixed screen-centre crosshair lands inside the drawn body. Looking up slides a sprite down past the centre, looking down lifts it: a short far billboard slips off the crosshair, a tall near one stays caught.

## Caching

Two private atoms memoize input-determined data:

- `offset-cache`: per-column FOV offsets and their cosines, built once per width.
- `pause-cast-cache`: single-slot copy of the last cast, read only while paused (player and grid frozen). Active frames never touch it, so pause overlays and the help menu cost no cast.

Neither changes a result for given inputs, so the casts stay referentially transparent. That is why the engine lives in `core/`: tests check distances, side bits, hit cells and array lengths against literal grids.
