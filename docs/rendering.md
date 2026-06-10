# Rendering

The render layer composes one ANSI string per frame and writes it to stdout. Side-effecting IO layer.

`src/io/render.phel` is a thin public facade: it re-exports the stable surface (`render!`, `clear-screen`, `read-perf-snapshot`, the screen entry points, plus `direction-char` / `project-enemy` / `enemy-front-visible-at?` / `reload-reminder-visible?` / `build-blood-cols` / `help-menu-rows` for tests). Callers require `phel-doom.io.render` and never reach into the sub-namespaces directly.

The implementation lives under `src/io/render/`:

| Namespace | File | Responsibility |
|-----------|------|----------------|
| `...render.buffer` | `buffer.phel` | Hot-loop php-array macros (`buf-mk` / `buf-set` / `buf-get` / `buf-push`). |
| `...render.palette` | `palette.phel` | ANSI colour/glyph string constants + shade lookup tables. Pure data. |
| `...render.frame-math` | `frame_math.phel` | Gradients, sprite scaling, enemy projection, visibility tests. Pure helpers. |
| `...render.hud` | `hud.phel` | Minimap, F3 debug line, help menu, settings panel. |
| `...render.paint` | `paint.phel` | Transient overlay effects (face, crosshair, vignettes, badges, pistol HUD). |
| `...render.main` | `main.phel` | The `frame->string` pipeline, `render!`, perf snapshot, end / menu screens. |

Dependency direction is acyclic: `buffer -> palette -> frame-math -> {hud, paint} -> main -> facade`. The hot per-cell loop (`frame->string` + `compute-wall-shades`) stays co-located in `main`; cross-namespace calls compile to direct PHP static calls and the buffer macros inline, so the split adds no hot-path overhead.

Entry point: `render! [world stats cols rows]` - cursor home, pick impact flash or normal frame, flush.

```phel
(print "\e[H")                      ; cursor home
(if (php/> (get stats :flash-secs) 0.0)
  (print (white-flash-frame ...))   ; hit flash overlay
  (print (frame->string ...)))
(php/flush)
```

## frame->string pipeline

Base: raycast frame (run-length encoded). Overlays paint on top via absolute cursor positioning (`\e[r;cH`).

```
cast-frame            -> dists, sides, hxs, hys
build wall shades     -> shades-normal, shades-top-edge, shades-bot-edge per col
project enemies       -> eheads, ebodys, elegss (fade-shaded)
project pickups       -> blood-paint overlay buffer
project blood FX      -> blood-paint overlay buffer
layout                -> minimap scale/position
main row loop:        -> base frame (wall/sky/floor, enemy priority, blood overlay)
concat via php/implode
overlays (cursor-positioned):
  - bottom HUD tagline
  - F3 debug row (if :debug?)
  - minimap + fog-of-war
  - enemy faces (depth-culled)
  - crosshair, kill-streak, compass
  - game-info strip (level, kills, weapon, ammo, keys, diff)
  - health + armor HUD
  - weapon viewmodel (`paint-weapon-hud`): a baked Freedoom (BSD) sprite when the active weapon has one and it fits the viewport, else the hand-built ASCII silhouette (`paint-pistol-hud`); `PHEL_DOOM_NO_SPRITES=1` forces ASCII
  - muzzle flash (when firing)
  - dry-fire CLICK (out of ammo)
  - reload reminder (cadence)
  - HP digits (wounded multi-life enemies)
  - pause menu (if paused)
```

## Per-column shade composition

```
shade-idx = clamp(0, 23,
  gamma(distance-to-shade(dist))  ; base by distance, gamma 0.6 curve
  + (side == 0 ? 3 : 0))          ; vertical faces brighter
```

The gamma 0.6 curve brightens mid-range; the `+3` bonus for vertical faces reads as directional lighting. Walls, sky, and floor all index the same 24-step grayscale `shade-table` (no colour, no per-room tinting) so the place reads dark and neutral. One lookup per column; consecutive same-shade cells RLE-coalesce.

Doors: `door-shade` (orange for unlocked, blue/red for keycards, bright red for boss-lock). Half-block edges mix door with sky/floor. Locked messages ("NEED BLUE KEY", "KILL THE BOSS") painted separately.

## Half-block edge anti-aliasing

Wall top/bottom: `▀` (upper half block) mixes wall BG with sky/floor FG:

```
Top:    \e[48;5;<wall>;38;5;<sky-at-row>m▀      (wall BG, sky FG)
Bottom: \e[48;5;<floor-at-row>;38;5;<wall>m▀    (floor BG, wall FG)
```

Sky and floor codes are sampled from gradients at the seam row, not flat constants. Flat codes produced dark dots. `build-horizon-gradient-codes` and `build-themed-gradient-codes` pre-bake code-only twins of the string gradients per frame.

## Distance-shaded sky and floor

Per-row shade by distance from horizon (`vh/2`): rows near horizon darkest (atmospheric haze), overhead/feet brightest. Sky and floor share the gradient, pre-baked per viewport height in `build-horizon-gradient`.

## Enemy sprite paint

Two modes, chosen by `PHEL_DOOM_NO_SPRITES` (same flag as the weapon view; sprites on by default).

**Sprite mode (default):** enemies render as baked Freedoom (BSD) billboards. `enemy_sprites_data` holds a native-resolution xterm-256 grid per sprite-id (`{:w :h :px}`, -1 transparent); `enemy-sprite/sprite-for-type` maps each `:type` to one (pinky + spectre reuse `:demon`). Box width comes from the sprite's NATIVE aspect (`half-width = round(h * sw / sh)`, terminal cells being ~2:1 tall) so the monster is never squished by the glyph hitbox. The zone pass stashes per covered column (depth-gated `d < dists[c]`) the billboard box + sprite ref in `e-stop/e-sbot/e-sx/e-spx/e-sw/e-sh` WITHOUT clobbering the wall `tops/bots`, so transparent pixels show the real wall behind. The hot row loop computes the wall/sky/floor base cell, then overlays `enemy-sprite-cell`, which stacks TWO sprite sub-pixels per cell via a half-block (`▀` fg=top bg=bottom) for 2x the vertical resolution; an edge cell with one opaque sub-pixel renders a solid `█` of that colour (clean silhouette, no halo against any background). `sprite-col-x` (column to sprite-x) is precomputed once per column; only the sub-pixel `sy` pair is per-cell. The crosshair centre-cell resolver mirrors the same priority.

**Glyph mode (`PHEL_DOOM_NO_SPRITES=1`):** the legacy path. Per enemy: fade `t = (dist/max-depth)²` capped at 0.85, then shade head/body/legs via `fade-256` on color codes. Body glyph (e.g. `▒`) varies per type. Writes `eheads/ebodys/elegss` + overwrites `tops/bots/mids/lowers` for per-row zone selection. Cyberdemon uses `boss-col-paint` to carve a silhouette (sprite mode samples the real cyber sprite instead).

`project-enemy` scale factor (1.0 default, 2.0 for `:cyber`): multiplies half-width and height proportionally. Centred vertically with feet at horizon.

Aggro blink at distance < 1.8 units (glyph mode).

**Death + projectiles (sprite mode):** kills and enemy fireballs render as Freedoom billboards too, blitted into the top-priority `blood-paint` overlay via `blit-sprite-into` (same half-block sampler + native-aspect width + wall/enemy occlusion). On a kill, `combat/push-blood-fx` tags the fx with the dead enemy's `:type`; `death-frame` maps the fx ttl (1.0 just-killed -> 0.0 gone) to a collapse->corpse frame from `death-sprites` (revenant has no Freedoom death frames -> falls back to the blood shade). Enemy fireballs sample `projectile-sprites :fireball`. `PHEL_DOOM_NO_SPRITES=1` keeps the old blood-shade death stages and the orange-glow fireball.

## Face overlay (post-pass)

Per-enemy face glyph (`:enemy-face` or `:enemy-face-alt` on sin wave) at centre column, upper-third row. Depth-culled: paint only if enemy dist < wall dist.

## Floating item sprites

Pickups (health, armor, ammo, powerups, keycards, weapon drops) render as small Freedoom (BSD) billboards via `blit-billboard-scaled` into `blood-paint` (`paint-pickups-into`, keyed by `pickup-sprites`). `PHEL_DOOM_NO_SPRITES=1` falls back to the coloured glow + centre glyph.

## blood-paint overlay buffer

Blood splatters and pickups paint into a PHP array (indexed `row*vw + col`). Inner loop reads first, so overlays override walls/floors/enemies.

Grounding shadow and face glyph need depth-culling: paint only if in front of wall AND nearest enemy at column. `enemy-front-visible-at?` gates both.

## Run-length encoding

Consecutive same-color cells coalesce: one escape + N spaces (terminal repeats BG). Cuts output 5-10x on monochrome rows. State machine tracks `prev` + `run`, flushes on color change.

## Render-scale: uniform crisp walls

`render-scale` is a uniform 1 at every terminal size: one ray per output column, exact 1:1 cast, crisp walls. The old big-screen perf mode (cast once per 2 cols and replicate, for a chunky look on wide terminals) has been removed. `cast-frame` still accepts a `scale` argument so the replication path stays available, it is just always called with 1.

## Textured walls

Plain stone walls are sampled from the baked Freedoom flat `wall-tex` (WALL70_2, 64x64, in `wall_texture_data.phel`). Per wall-body cell: `u` = `wallxs[col] * 64` (the ray's wall-hit fraction from the cast), `v` = row-within-wall * 64 / wall-height. The texture code is fogged by the column's 0..23 shade level through `tex-fade-table` (a prebaked 24x256 fade LUT) and resolved to a ready cell via `bg-cell-cache` - one nested `aget`, no per-cell `fade-256` or string alloc, so texturing costs ~2% over flat shading.

Doors, the boss door, and blood-band columns are NOT textured (`tex-level = -1`): they keep their flat shade so nav glyphs / the red hit-wash stay clean. Wall-top/bottom `▀` seams are unchanged. `PHEL_DOOM_FLAT_WALLS=1` forces the old flat-shaded stone.

## Textured floor (floor-casting)

The ground plane is cast per cell instead of drawn as a flat gradient. A floor cell `p` pixels below the horizon (`vh/2`) sits at perpendicular distance `floor-cast-k / p` (`build-floor-dperp`, per-row); the world floor point is `player + dperp * (floordxs[col], floordys[col])` - the `floordxs/floordys` basis (ray direction / cos(offset)) comes from the cast, so there is no per-cell trig. `frac` of the world point → texture (u, v); the same stone texture as the walls is sampled, fogged by the row's `floor-level` (pulled `floor-darken` = 4 steps darker than a wall at the same distance, so the ground reads as shadowed and the grazing-angle texel aliasing calms down). Blood columns keep the red gradient; `PHEL_DOOM_FLAT_FLOOR=1` restores the flat floor. Cost ~+12% (no-JIT local; the angular ray model rules out the linear per-row floor-step shortcut, so it stays a per-cell mul-add).

## Half-block sub-pixel rendering (floor / walls / sky)

A terminal cell carries only two colours (one fg, one bg), so the realism ceiling is set by how finely we subdivide each cell, not by adding colours. The floor, wall body, and sky each emit a `▀` upper-half-block whose **top colour is the fg and bottom colour is the bg** - two full-colour sub-pixels stacked per cell, 2x vertical resolution with no quantization (since cells are ~2:1 tall, the sub-pixels read as square). This is the standard high-fidelity terminal-image technique (chafa/timg/viu).

- **Floor:** `build-floor-dperp-sub` / `build-floor-level-sub` are the per-SUB-ROW (2·vh) twins of the cell-res arrays, with the horizon at sub-row `vh` and `floor-cast-k-sub = 2·floor-cast-k`. Each cell samples two ground points (top sub-row = farther, bottom = nearer) and packs both faded texels into one `▀`.
- **Wall body:** two texture-V samples down the column (same U, same fog level), stacked.
- **Sky:** `build-sky-halfblock` pre-bakes one `▀` per row stacking two horizon-gradient sub-rows. The pair is row-constant so sky rows still RLE-coalesce into a single run.

The cost that killed the earlier full-frame attempt was the per-cell string build. `halfblock` (in `frame_math`) memoizes each `top*256+bot` pair into a ready paint string in a raw php-array def (`half-cell-cache`): the hot path is one `aget` after warmup, no concat. `top == bot` collapses to a single-colour BG cell (`\e[48;5;Cm `) - identical render, fewer bytes, and it RLE-coalesces with flat neighbours. Net **~+2% CPU** over the one-colour-per-cell path. Bytes rise ~50-70% on big screens (more SGR-dense cells, less coalescing) - cap with `--max-cols`. `PHEL_DOOM_NO_SUBPIXEL=1` forces the legacy one-colour-per-cell floor/wall/sky (A/B perf, or a font without the `▀` glyph).

(Caveat for `def-`: it does NOT accept a string docstring - the string is stored AS the value. `half-cell-cache` keeps its doc in a `;;` comment for this reason.)

## Pixel-doubled mode (auto, slow machines)

When the game-loop's startup calibration finds full detail too slow for a smooth framerate (see `docs/game-loop.md`), `frame->string` gets `:px2? true` in stats: the scene renders at half resolution (svw x svh) and each scene cell paints a 2x2 terminal block - quarter the per-cell work, still the whole terminal. Key invariants:

- **Same framing, no zoom.** The cast runs at the FULL width with `scale 2` (full-width FOV tables, one ray per two columns) and is compacted to scene width by `compact-cast-2`; wall heights, enemy projection and the billboard painters all take an explicit `pd` (= `proj-dist / 2`) so on-screen sizes match full detail exactly.
- **Row-pair split instead of ▀.** The sky / floor / wall branches sample both vertical sub-texels per scene cell (packed into one `top*256+bot` int by a single branch dispatch) and paint the top sample on the upper output row, the bottom on the lower - the same two vertical samples the half-block path packs into one cell.
- **Sprites keep their detail.** `enemy-sprite-quad` returns the raw 2x2 texel quad and the emitter spreads it over the real 2x2 block; transparent texels fall back to the base pair per quadrant.
- **Emission.** The upper row streams into `parts` with the usual cell + N-spaces RLE (solid BG cells only); the lower row accumulates in a per-row buffer appended after the upper row's newline. Composite glyph cells (doors, edges, pickups) are pushed literally twice so glyphs survive the doubling. Text/HUD overlays (crosshair, compass, weapon sprite, minimap) keep full-resolution coordinates; the scene-coordinate painters (`paint-door-face`, `paint-face-overlay`) take a pixel-scale factor instead.

## Responsive help panel

H/ESC info menu width-adaptive: max 44 chars, min 36. Drops CONTROLS section first, then COMPASS HINT on squeeze.

## Why so many overlay passes

Walls/sky/floor/enemies go into one string via the row loop. HUD, minimap, crosshair use absolute cursor positioning escapes (`\e[r;cH`) to paint anywhere. Alternate screen buffer + cursor-home redraw overwrites in place: no flicker, no scroll, no full clear.

See [performance.md](performance.md).

## Minimap fog-of-war (issue #67)

Cells stay hidden behind `minimap-unseen` until the player visually crosses them. `mark-visible-cells` runs once per frame: scans `visit-radius = 8` bounding box, runs Bresenham `los-clear?` per cell, stamps `:visited` PHP array (keyed by `y * width + x`).

`minimap-rows` reads `:visited` and paints `minimap-unseen` for unseen blocks. Pickup glyphs only paint if visited.

`:full-map?` (set by `--full-map` / `-f` CLI flag) marks all cells visited; useful for level editors and screenshots.

## Weapon viewmodel sprites (Freedoom)

The first-person gun (`paint-weapon-hud`) uses baked Freedoom (BSD) viewmodels. `tools/bake-weapon-sprites.phel` decodes the Doom picture lumps from a Freedoom WAD, maps the palette to xterm-256, downsamples to a small bottom-strip height, and writes `src/io/render/weapon-sprites-data` (a per-weapon `{:w :h :px}` grid, -1 = transparent). License-clean, no binary asset in the repo; classic-DOOM weapons only (no super shotgun).

`paint-weapon-sprite` pairs two pixel rows per half-block cell (`▀`/`▄`), bottom-anchored, reusing the reload drop + recoil kick. `weapon-row-string` keeps it cheap: fully transparent cells collapse to one cursor-forward (live floor shows through, no halo), half-lit cells back their transparent half with the row's floor colour, and a colour SGR is emitted only when it changes from the previous cell. Worst-case overlay (chaingun/BFG) is about 1.3 ms and 6 KB per frame; the env probe is memoised so there is no per-frame `getenv`.

## Asset attribution

Weapon sprites, weapon-fire sounds, and enemy billboard sprites are derived from [Freedoom](https://freedoom.github.io/) (`freedoom1.wad` + `freedoom2.wad`), distributed under the 3-clause BSD license. They are baked into `src/` data files by the scripts under `tools/` (`bake-weapon-sprites`, `bake-weapon-sounds`, `bake-enemy-sprites`); re-bake from a Freedoom WAD rather than hand-editing.
