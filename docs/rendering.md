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
| `...render.sprites` | `sprites.phel` | Item / projectile / tracer billboards + Freedoom death & blood-FX painters, and the `sprites-enabled?` gate. |
| `...render.main` | `main.phel` | The `frame->string` pipeline, `render!`, perf snapshot. |
| `...render.screens` | `screens.phel` | Full-screen overlays: start menu, settings page, death / victory end screens. |

Dependency direction is acyclic: `buffer -> palette -> frame-math -> {hud, paint, sprites} -> {main, screens} -> facade` (`paint` also calls `sprites-enabled?` from `sprites`). The hot per-cell loop lives in `emit-scene-px1` / `emit-scene-px2` (the px1 / pixel-doubled scene emitters lifted out of `frame->string` in #350), which `frame->string` calls once per frame; these plus `compute-wall-shades` stay co-located in `main`. Cross-namespace calls compile to direct PHP static calls and the buffer macros inline, so the split adds no hot-path overhead.

Entry point: `render! [world stats cols rows]` - cursor home, pick impact flash or normal frame, flush.

```phel
(print "\e[H")                      ; cursor home
(if (php/> (get stats :flash-secs) 0.0)
  (print (pain-flash-frame ...))    ; hit flash overlay (dark red, #465)
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
  + (side == 0 ? 3 : 0)           ; vertical faces brighter
  + light-bias)                   ; per-cell room light (#418, opt-in)
```

The gamma 0.6 curve brightens mid-range; the `+3` bonus for vertical faces reads as directional lighting. Walls, sky, and floor all index the same 24-step grayscale `shade-table` (no colour) so the place reads neutral.

Room lighting (#418, the `:light` setting, off by default) folds one more term: `light-bias` is the hit cell's value in the world's derived `:light-grid` (see `core/light`), a per-cell shade offset (+ = lit pool, - = darker). The lookup is one `php/aget` per COLUMN at the ray's hit cell (`:hxs`/`:hys`), never per texel, so it rides the same single-lookup-per-column budget; `tex-level` is `idx` so the wall TEXTURE fog tracks it for free. When the setting is off the term is `+0` and the frame is byte-identical. Doors are excluded (they stay bright as a nav cue). One lookup per column; consecutive same-shade cells RLE-coalesce.

Doors render as a baked procedural amber door texture (see "Textured doors" below); the boss door stays at its bright shade. Locked messages ("NEED BLUE KEY", "KILL THE BOSS") painted separately.

## Half-block edge anti-aliasing

Wall top/bottom: `▀` (upper half block) mixes wall BG with sky/floor FG:

```
Top:    \e[48;5;<wall>;38;5;<sky-at-row>m▀      (wall BG, sky FG)
Bottom: \e[48;5;<floor-at-row>;38;5;<wall>m▀    (floor BG, wall FG)
```

Sky and floor codes are sampled from gradients at the seam row, not flat constants. Flat codes produced dark dots. `build-horizon-gradient` (fed a code table) and `build-themed-gradient-codes` pre-bake code-only twins of the string gradients per frame.

These whole-cell edge bands apply to non-textured columns (boss door, blood-band, glyph-mode enemy columns, or with textures/subpixel off). Textured columns - stone walls and doors alike - trace their wall top/bottom at sub-row precision instead - see the next section.

## Sub-row wall seams (diagonal wall edges)

Textured, non-glyph-enemy columns place the wall top/bottom in SUB-rows (half a terminal row, the ▀ sub-pixel unit) via `build-wall-sub-bounds` and mix sky / wall / floor codes inside the boundary cells, so a receding wall's silhouette steps in half-row diagonals instead of whole-cell stairs - the wall/floor junction reads like the floor texture's own perspective diagonals instead of a bright staircase of edge cells. The seam carries a graduated dark border tracing the exact diagonal: the wall's bottom-most sub-row drops near-black (`seam-darken-16`), the sub-row above and the floor's first sub-row pull several steps darker (`seam-darken-8`), and a lighter lip marks the wall/sky limit (`seam-darken-5`). The accents are hue-true darken LUTs, not plain code subtraction, so they work on the door texture's colour-cube texels too (see "Textured doors"). Interior wall cells keep a straight sample fast path; only the one or two boundary cells per column pay the per-sub-row resolution.

The same mixer runs at both render scales: 2 sub-rows per cell at full detail, 4 per 2-terminal-row scene cell in pixel-doubled mode - the identical half-row absolute precision. At full detail it requires subpixel mode (`PHEL_DOOM_NO_SUBPIXEL=1` falls back to the whole-cell edge bands above). Costs ~15% render time at full detail (the per-cell mix-column checks), well inside the auto-calibration budget. The `Low detail` setting (`:fast-walls` in stats; dev/bench override `PHEL_DOOM_FLAT_WALLTEX=1`) paints the wall AND floor INTERIOR as a single flat sample per cell while keeping the wall seam mixer running, so silhouettes stay sub-pixel and only the interior textures go chunky - reclaiming ~11-26% render time and ~31-40% bytes/frame on large screens. Off by default (byte-identical to the shipped render); see [settings.md](settings.md).

## Distance-shaded sky and floor

Per-row shade by distance from horizon (`vh/2`): rows near horizon darkest (atmospheric haze), overhead/feet brightest. Sky and floor share the gradient, pre-baked per viewport height in `build-horizon-gradient`.

## Atmospheric fog tint (tinted + filmic)

Distance fog on the textured walls and the themed floor fades toward a near-neutral light-grey haze tint (rgb 112/112/120, re-quantizes to grey ~118 at the far end) instead of pure black, and runs the brightness through a normalised ACES-ish filmic tone curve (toe keeps shadow contrast, shoulder rolls off near-wall highlights). Aerial perspective: distant surfaces converge on the same grey haze (bright codes roll down toward it, codes darker than the haze lift up toward it) so depth reads as "hazy/far" rather than just "dark", and mid-tones gain contrast so the scene reads lit rather than linearly dimmed.

The tint is deliberately near-neutral. The 256-colour palette cannot express a "barely cool" mid-grey: the grey ramp is dense, so anything near neutral snaps onto it and loses the hue, and anything bluer jumps to cube (1,1,2) = rgb 95/95/135, which reads as an out-of-place blue band through far openings rather than haze. Neutral grey is the honest desaturation.

The truecolor (24-bit) path has no such quantization, so it is NOT bound to that neutral compromise (#419): its fog fades toward a separate cooler haze target (`fog-rgb-tc` = rgb 104/110/130) instead of reusing the 256 neutral `fog-rgb`. Same luminance (avg ~115), but a real cool bias (blue 130 vs red 104) - subtle enough to read as atmospheric haze rather than the blue band the 256 cube would snap it into. The 256 path is unchanged; only truecolor mode (`:truecolor` setting / `PHEL_DOOM_TRUECOLOR`) shows the cooler tint.

All of this is baked at load: `fade-256-fog` (in `frame-math`) lerps each code toward the fog tint in true RGB and re-quantizes to the nearest 256-colour code via `palette/nearest-256`, so the rebuilt `tex-fade-table` / `build-themed-gradient(-codes)` LUTs cost the hot path nothing extra - still one nested `aget` per cell. The floor gradient's base code is per-level (#417): `frame->string` resolves the level's `:theme` via `palette/theme-floor-code` and threads it into the memoized gradient bundle, which is keyed on the base code so the floor LUT rebakes only on level change, never per frame. `PHEL_DOOM_FLAT_FOG=1` restores the legacy linear fade-to-black (A/B fallback, same pattern as `NO_SUBPIXEL` / `FLAT_WALLS`). The grayscale-ramp sky gradient and the enemy/seam fades are unchanged.

## Enemy sprite paint

Two modes, chosen by `PHEL_DOOM_NO_SPRITES` (same flag as the weapon view; sprites on by default).

**Sprite mode (default):** enemies render as baked Freedoom (BSD) billboards. `enemy_sprites_data` holds a native-resolution xterm-256 grid per sprite-id (`{:w :h :px}`, -1 transparent); `enemy-sprite/sprite-for-type` maps each `:type` to one (pinky + spectre reuse `:demon`). Box width comes from the sprite's NATIVE aspect (`half-width = round(h * sw / sh)`, terminal cells being ~2:1 tall) so the monster is never squished by the glyph hitbox. The zone pass stashes per covered column (depth-gated `d < dists[c]`) the billboard box + sprite ref in `e-stop/e-sbot/e-sx/e-spx/e-sw/e-sh` WITHOUT clobbering the wall `tops/bots`, so transparent pixels show the real wall behind. A column fully behind a wall paints nothing - and does not update `edists`, so a hidden enemy neither occludes a pickup behind it nor drops a grounding shadow. The hot row loop computes the wall/sky/floor base cell, then overlays `enemy-sprite-cell`, which stacks TWO sprite sub-pixels per cell via a half-block (`▀` fg=top bg=bottom) for 2x the vertical resolution; an edge cell with one opaque sub-pixel renders a solid `█` of that colour (clean silhouette, no halo against any background). `sprite-col-x` (column to sprite-x) is precomputed once per column; only the sub-pixel `sy` pair is per-cell. The crosshair centre-cell resolver mirrors the same priority.

**Mip levels:** each baked sprite gets a load-time mip chain (`sprite-mips`: half and quarter resolution). m1 (half res) is a standard box-filter with min-opaque=2 (a 2x2 block stays transparent unless at least two sources are opaque). m2 (quarter res) applies three additional load-time passes to counteract the readability loss that double box-filtering inflicts on small on-screen billboards:

1. `min-opaque=1` on the second half-mip call - any single opaque source in a 2x2 block produces an opaque output texel, preserving thin features (horns, limbs, head) that a strict 2-of-4 rule would erase at quarter resolution.
2. Luminance contrast-stretch (`contrast-stretch`, min-range=40) - double averaging compresses the texel luminance range toward mid-gray; stretching it back to 0-255 restores the light/dark separation so a far enemy reads as a figure rather than a uniform blob.
3. Silhouette edge darkening (`silhouette-darken`, frac=0.40) - every opaque texel bordering a transparent neighbour (4-connected) is darkened 40% toward black, cutting a 1-pixel dark outline around the figure that reads as a readable silhouette at 4-8 terminal rows.

All three passes run once at load; zero per-frame cost. m1 is unchanged. The zone pass calls `sprite-for-type-lod` with the billboard's on-screen sub-row count (2 per cell): a source >= 3x taller than the box samples m2, >= 1.5x samples m1 (tested as `sh*2 >= 3*sub-rows` to avoid float), else native. Tighter thresholds than a naive 2x/4x split keep native only when oversampling ratio is below 1.5x, cutting mid-distance speckle. Sampling uses center-of-footprint coordinates (`intdiv(sub*sh + h2/2, h2)`) rather than truncating floor, removing the top-left-corner bias that caused alternating bright/dark texel columns. Mid and far monsters sample the enhanced pre-filtered image; near monsters keep the native level byte-identical.

**Distance fog:** the zone pass quantizes the combined fade (`(dist/max-depth)²` capped 0.65, plus wound tint) to one of the 24 `sprite-fade` levels and stashes it per column in `e-fade`. The `sfade` index fed into that LUT uses half-strength distance fog for sprites: `(1 - body_fade * 0.5) * 23`, so the darkening applied to sprite texels is halved compared to walls. This keeps shading bands readable on dark-toned sprites (Freedoom imp body lum ~88) at mid/far range where full fog would crush them back toward black. The 0.65 cap on `body_fade` ensures a monster at max range stays at least 35% lit; the half-strength sprite LUT ensures the textured pixel path applies only ~15-30% additional darkening at those distances. A far monster still sinks into atmospheric haze; a wounded one reads darker/dirtier via the damage tint (wound contribution is NOT halved, so gameplay readability of health state is preserved). `blit-sprite-into` applies the same depth-keyed fade to corpses, blood splats, fireballs, and near-LOD pickup sprites; close blits land on the identity level so colours stay readable.

**Baked palette:** `enemy_sprites_data.phel` stores native-resolution xterm-256 grids produced by `tools/bake-enemy-sprites.phel`. The bake tool maps Freedoom PLAYPAL entries through three stages for enemy sprites: (1) per-channel gamma=0.50 (square-root) lift via `tone-lift` - this pushes dark-brown shadow bands (source lum ~15-40) into distinguishable code territory while preserving hue; (2) warm-bias redirect via `warm-bias-code` - if the tone-lifted result still lands on the gray ramp AND the source pixel has r-b >= 12 (indicating a warm olive/brown origin), the code is redirected to the nearest xterm-256 cube code with r_index > b_index (genuinely warm, not neutral-gray); this converts the imp's dominant dark-brown body pixels (source lum 7-35, r-b +16 to +36) from gray ramp codes to olive-brown cube codes (58 = rgb(95,95,0), 94 = rgb(135,95,0)), raising warm cube coverage from ~31% to ~80% of opaque pixels; (3) a gray-ramp shift of +3 steps via `gray-shift` for any ramp codes that survive stages 1-2 (purely neutral grays such as stone/concrete). Pickup sprites use a separate `rgb->256-pickup` path that applies only the gamma lift - no warm-bias and no gray-ramp-shift - because item art is already in the bright lum 88-168 range where both transforms would wash or distort the colors. The `rgb->256` base function finds the nearest code by squared-distance against actual cube levels (0, 95, 135, 175, 215, 255) and the 24-step grayscale ramp. An earlier version assumed evenly-spaced levels (0, 51, 102, ...) which systematically mis-quantized brown/tan source colors into gray-green codes, producing color-confetti.

**Pickup sprites:** all 17 pickup types (hearts, armor, armor-shards, ammo, berserk, invuln, soulsphere, backpack, three keycard colours, five weapon pickups, chainsaw) are rendered as baked Freedoom item billboards via `paint-pickups-into` in `paint.phel`. The sprite path fires whenever `ph >= max(2, 2*lodr)` where `ph = min(16*lodr, 0.55*sprite_h)` - any distance at which the billboard is >= 2 rows tall. A higher floor would fall back to flat coloured quads at ordinary gameplay range. Below that threshold the legacy coloured-glow fallback renders a compact quad with a centre icon glyph, giving a readable colour cue at extreme range. `blit-sprite-into` is reused unchanged; pickup sprites use the same half-strength fog (cap 0.65, `df*0.5` before LUT index) as corpses and fireballs. Sprite data lives in the `pickup-sprites` map inside `enemy_sprites_data.phel`, baked at longest-side 18px via area-averaged downscale through `rgb->256-pickup` (gamma=0.50 tone-lift only, NO gray-ramp-shift). The gray-ramp-shift is intentionally omitted for pickups: item sprites are already bright art (lum 88-168 after gamma lift) and the +3-step shift used for dark enemy bodies would push them toward near-white (lum 168), washing out all internal shading and making every item render as a pale rectangle. Enemy sprites continue to use `rgb->256-lifted` (gamma + shift) to push their dark-brown shadow bands into the visible range.

**Glyph mode (`PHEL_DOOM_NO_SPRITES=1`):** the legacy path. Per enemy: fade `t = (dist/max-depth)²` capped at 0.85, then shade head/body/legs via `fade-256` on color codes. Body glyph (e.g. `▒`) varies per type. Writes `eheads/ebodys/elegss` + overwrites `tops/bots/mids/lowers` for per-row zone selection. Cyberdemon uses `boss-col-paint` to carve a silhouette (sprite mode samples the real cyber sprite instead). Pickups fall back to coloured glow+glyph in this mode.

`project-enemy` scale factor (1.0 default, 2.0 for `:cyber`): multiplies half-width and height proportionally. Anchored vertically by the FEET on the projected floor (below), then drawn upward by the sprite height.

**Feet anchoring.** The renderer stands each billboard on its feet, not centred on the horizon. The enemy zone pass projects the flat floor row `round(svh/2 + 0.5*wall-px) + pr` and sets the body to span from head to feet on that row. The projection is written inline via `wall-px` (not a `project-height` call) to keep the built-file closure count at its documented baseline. The grounding shadow drops on the foot row; the face glyph and floating HP digit ride the same anchor. `scene-pd` is halved in pixel-doubled mode, so the projection scales automatically. The golden hashes in `render-cache-test/test-frame-bytes-pinned` are unchanged because the golden fixture has no enemy on-screen.

Aggro blink at distance < 1.8 units (glyph mode).

**Death + projectiles (sprite mode):** kills and enemy fireballs render as Freedoom billboards too, blitted into the top-priority `blood-paint` overlay via `blit-sprite-into` (same half-block sampler + native-aspect width + wall/enemy occlusion). On a kill, `combat/push-blood-fx` tags the fx with the dead enemy's `:type`; `death-frame` maps the fx ttl (1.0 just-killed -> 0.0 gone) to a collapse->corpse frame from `death-sprites` (revenant has no Freedoom death frames -> falls back to the blood shade). Enemy fireballs sample `projectile-sprites :fireball`. `PHEL_DOOM_NO_SPRITES=1` keeps the blood-shade death stages and the orange-glow fireball.

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

`render-scale` is a uniform 1 at every terminal size: one ray per output column, exact 1:1 cast, crisp walls. The pixel-doubled path does not go through it - `frame->string` passes `2` to `cast-frame` directly, casting half the rays and painting each across a 2x2 block (see [Pixel-doubling](#pixel-doubling)).

## Textured walls

Plain stone walls are sampled from the baked Freedoom flat `wall-tex` (WALL70_2, 64x64, in `wall_texture_data.phel`). Per wall-body cell: `u` = `wallxs[col] * 64` (the ray's wall-hit fraction from the cast), `v` = row-within-wall * 64 / wall-height. The texture code is fogged by the column's 0..23 shade level through `tex-fade-table` (a prebaked 24x256 fade LUT, tinted + filmic toward the cool haze - see "Atmospheric fog tint") and resolved to a ready cell via `bg-cell-cache` - one nested `aget`, no per-cell `fade-256` or string alloc, so texturing costs ~2% over flat shading.

The boss door and blood-band columns are NOT textured (`tex-level = -1`): they keep their flat shade so the boss nav glyph / the red hit-wash stay clean. `PHEL_DOOM_FLAT_WALLS=1` forces flat-shaded stone (and the striped flat door).

## Texture filter: distance mips for walls (issue #462)

Opt-in **Texture filter** setting (default off, `PHEL_DOOM_TEXMIP=1` to force). A far wall projects a handful of screen rows out of 64 texels, so it point-samples a different texel per frame as the player moves - that is the speckle on distant stone. With the filter on, each column picks a pre-filtered level (`wall-tex-mips`: 64 / 32 / 16 / 8, box-filtered at load with the sprite path's `half-mip`) whose density matches its projected height, using the sprite LOD's oversampling thresholds.

The size travels per column in a `tex-sz` buffer beside the `tex-px` array reference, and `u` is rescaled into the chosen level once in the setup loop, so no per-cell site touches it and the sample expression becomes `(min tszm1 (intdiv (* rel tsz) whs)) * tsz + u`. With the filter off every column is size 64 and every one of those expressions reduces to the literal arithmetic it always held - the default golden hash is unchanged, byte for byte.

Two traps worth keeping written down. The level is chosen against the wall's height in SUB-rows (2 per scene cell, 4 pixel-doubled), because that is the unit the per-cell sampler divides by; picking from cell rows mips the pixel-doubled scene two steps off. And the flag must be resolved by a plain function call rather than an `if` or `or` in `frame->string`'s binding list, which closure-compiles and moves the tracked closure count.

Doors keep the native 64 unconditionally: they are nav cues and want to stay crisp.

Measured on the L1 fixture at 200x50, counting how often the background colour changes between adjacent cells (a speckle proxy): the wall band drops from 82.5% to 79.9%, and the frame is ~1.2% smaller because the runs coalesce better. Frame time is unchanged either way (interleaved, both 120x30 and 240x60, mixed signs). **The floor is not mipped yet and is where most of the surface area is** - 3342 floor cells against 1082 wall cells in that frame, unchanged at 72.7% churn. That is the bigger half of #462 and it is still open.

## Secret wall tell (issue #469)

A secret wall's column samples the stone texture with a half-tile `u` offset (`secret-tex-offset` 32 of 64), so the pattern runs visibly out of phase with the walls beside it - Doom's own misaligned-texture cue. Visible when you look for it, invisible when you do not.

Secrets otherwise looked and cast exactly like ordinary walls, so the only way to find one was to walk the level pressing F at every surface, while secrets are worth 30% of the run rank. Nothing about the cast or the collision changes: a secret still reads as solid until it is opened. Per column, in the setup loop, and only when the hit cell is a secret - a level without one renders byte-identically.

## Textured doors

Door columns (unlocked + keycard-locked, map cells 2/3/4/9) run through the same texture path as the stone walls, sampling `door-tex-px` instead of `wall-tex-px` - `compute-wall-shades` stores the per-column texel array in a `tex-px` buffer, so the hot loops bind one extra aget and stay texture-agnostic. The texture is a procedural 64x64 amber metal door baked at load: dark rust border + red-rust frame ring, six vertical planks (alternating amber fills, highlight/shadow edges, dark grooves) split by a horizontal mid rail - the classic two-panel DOOM door silhouette, scaled by perspective like any texture.

Door texels are xterm-256 colour-CUBE codes (not grayscale ramp), which two pieces of machinery must respect:

- `tex-fade-table` fog already fades cube codes hue-true (toward the neutral grey haze tint via `fade-256-fog`, or toward black under `PHEL_DOOM_FLAT_FOG=1`).
- The sub-row seam accents darken through `seam-darken-16/-8/-5` LUTs (in `frame_math`) instead of plain `code - n` arithmetic: subtracting from a cube code jumps hue (amber 166 - 16 = green 150). For grayscale-ramp codes the LUTs reproduce plain subtraction exactly.

Door fog is the wall formula with two nav-cue exceptions: the level floors at 8 (a door never fades to black) and ignores the near-death haze. The door rides the fog level steady-brighter (`door-tex-boost`, a constant +3 levels) instead of swapping paint strings. The door holds its bright frame rather than throbbing (see [Calm 3D view](#calm-3d-view-no-decorative-blinks)), which keeps it findable down the arena without flashing. Blood-band door columns keep the flat striped `door-shade-now` (the seam mixer's sky/floor codes are grayscale-only), as do glyph-enemy columns and all-flat fallback modes.

## Textured floor (floor-casting)

The ground plane is cast per cell instead of drawn as a flat gradient. A floor cell `p` pixels below the horizon (`vh/2`) sits at perpendicular distance `k / p` (`build-floor-dperp`, per-row), where `k = floor-cast-k` is the fixed eye-height constant (`proj-dist * 0.5 / char-aspect`, the eye at z = 0.5 over the flat floor); the world floor point is `player + dperp * (floordxs[col], floordys[col])` - the `floordxs/floordys` basis (ray direction / cos(offset)) comes from the cast, so there is no per-cell trig. `frac` of the world point -> texture (u, v); the same stone texture as the walls is sampled, fogged by the row's `floor-level` (pulled `floor-darken` = 4 steps darker than a wall at the same distance, so the ground reads as shadowed and the grazing-angle texel aliasing calms down). Blood columns keep the red gradient; `PHEL_DOOM_FLAT_FLOOR=1` restores the flat floor. Cost ~+12% (no-JIT local; the angular ray model rules out the linear per-row floor-step shortcut, so it stays a per-cell mul-add).


## Look up/down (pitch shear)

Camera pitch (arrow keys or mouse, issue #243) is rendered as a pure **vertical shear of the horizon**, not a re-projection, so it costs no extra rays. `frame->string` computes the integer scene-row offset `pr = projection/pitch-rows((:pitch player), vh)` once and adds it to every site that centres on `vh/2` (wall tops, sub-row seam bounds, the floor-cast distance tables, the sky/floor gradients, and the enemy/face/HP-flash anchors), so the whole scene slides as one rigid band - look up pushes the horizon down (more sky), look down pulls it up. The crosshair stays fixed (it is a weapon sight). Because every offset is additive and 0 at `pitch = 0`, a level gaze renders byte-for-byte like the no-pitch path (pinned by `render-cache-test/test-frame-bytes-pinned`). Full math and the list of shear sites: [raycaster.md](raycaster.md#look-updown-pitch-horizon-shear).

**Head bob (#411)** rides the same `pr`. When the View bob setting is on, `pr` (and its full-resolution twin `pr-full`) gains a second additive term, `projection/bob-rows((:bob-phase world), intensity, vh)`, so walls, floor, sky and enemies nod together on the walk cycle. `:bob-phase` is distance-driven in `core/physics.phel` and settles to 0 at rest; `bob-rows` is `round(intensity * bob-cap * vh * sin(phase))` with `bob-cap` = 0.05 (a subtle 1-2 row nod, far below `pitch-cap`). Both `intensity = 0` (setting off, the default) and `phase = 0` (at rest) return exactly 0, so a bob-off or standing frame stays byte-identical. The bob is deliberately NOT added to the combat hit gate (`combat/aim-pr` keeps true pitch), so a cosmetic nod never moves where a shot lands.

**Weapon bob (#412)** shares the same `:bob-phase` and View bob intensity, applied to the viewmodel anchor in `paint-weapon-sprite` instead of the horizon. Two terms fold into the sprite's existing `shift`/`c0`: `projection/weapon-bob-rows` = `round(intensity * weapon-bob-cap * vh * abs(sin(phase)))` (`weapon-bob-cap` = 0.04) drops the gun on each footfall (`abs(sin)` = a downward bowl, so the gun dips but never rises above rest, unlike the symmetric head-bob), and `projection/weapon-bob-cols` = `round(intensity * weapon-sway-cap * vw * sin(phase))` (`weapon-sway-cap` = 0.02) sways it left/right. The muzzle flash tracks both. `c0` is clamped so the sway never runs the sprite off-screen. Same byte-identical contract: `intensity = 0` or `phase = 0` yields 0 in both axes, so a resting / bob-off frame draws the gun exactly where the no-bob path did.

**Weapon-fire extralight (#413)** briefly brightens the room the frame or two after a shot, the feasible stand-in for a dynamic muzzle point-light (epic #408). `frame->string` subtracts `combat/fire-extralight((:fire-anim stats), duration)` from the near-death `haze-shift`, so the net shift can go NEGATIVE and pull walls toward the bright end of the 24-step shade table. `fire-extralight` returns `muzzle-extralight-steps` (4) while `fire-anim` sits in the first `muzzle-flash-fraction` (0.25) of its animation and 0 otherwise, so the flash lasts ~1-2 frames rather than the whole recoil, and is 0 when idle (resting frame stays byte-identical). Because a negative shift can push a shade index above 23, `compute-wall-shades` clamps `idx` to `[0, 23]`; without the upper clamp the index runs past the shade table and the frame breaks. It cannot collide with the pain-flash: a damage frame short-circuits to `pain-flash-frame` before `frame->string` runs. Sky and floor stay untouched, exactly as the near-death haze leaves them.


## Half-block sub-pixel rendering (floor / walls / sky)

A terminal cell carries only two colours (one fg, one bg), so the realism ceiling is set by how finely we subdivide each cell, not by adding colours. The floor, wall body, and sky each emit a `▀` upper-half-block whose **top colour is the fg and bottom colour is the bg** - two full-colour sub-pixels stacked per cell, 2x vertical resolution with no quantization (since cells are ~2:1 tall, the sub-pixels read as square). This is the standard high-fidelity terminal-image technique (chafa/timg/viu).

- **Floor:** `build-floor-dperp-sub` / `build-floor-level-sub` are the per-SUB-ROW (2·vh) twins of the cell-res arrays, with the horizon at sub-row `vh` and `floor-cast-k-sub = 2·floor-cast-k`. Each cell samples two ground points (top sub-row = farther, bottom = nearer) and packs both faded texels into one `▀`.
- **Wall body:** two texture-V samples down the column (same U, same fog level), stacked.
- **Sky:** `build-sky-halfblock` pre-bakes one `▀` per row stacking two horizon-gradient sub-rows. The pair is row-constant so sky rows still RLE-coalesce into a single run.

The dominant cost is the per-cell string build. `halfblock` (in `frame_math`) memoizes each `top*256+bot` pair into a ready paint string in a raw php-array def (`half-cell-cache`): the hot path is one `aget` after warmup, no concat. `top == bot` collapses to a single-colour BG cell (`\e[48;5;Cm `) - identical render, fewer bytes, and it RLE-coalesces with flat neighbours. Net **~+2% CPU** over the one-colour-per-cell path. Bytes rise ~50-70% on big screens (more SGR-dense cells, less coalescing) - cap with `--max-cols`. `PHEL_DOOM_NO_SUBPIXEL=1` forces one colour per cell for floor/wall/sky (A/B perf, or a font without the `▀` glyph).

(Caveat for `def-`: it does NOT accept a string docstring - the string is stored AS the value. `half-cell-cache` keeps its doc in a `;;` comment for this reason.)

### macOS Terminal.app compatibility

`▀` half-blocks render pixel-tight in iTerm2, kitty, WezTerm and Ghostty, but **macOS Terminal.app draws block / box glyphs with anti-aliasing and inter-row line gaps**, so the half-block illusion breaks into visible horizontal **row seams** in the 3D view and gappy HUD borders (#332). The colour path is fine: the renderer is 256-colour only (`\e[38;5;Nm` / `\e[48;5;Nm`), which Terminal.app supports, so the gap is glyph rendering, not colour depth.

**Auto-off on Terminal.app (#332).** On startup `load-settings` reads `$TERM_PROGRAM`; on `Apple_Terminal` a player who has never saved a `Sub-pixel` choice gets it defaulted **off** (`io/input.halfblock-seams?` -> `core/settings.resolve-subpixel`), so the scene is readable out of the box instead of seam-shredded. The in-game toggle still works and, once saved, wins on every terminal. Precedence: `PHEL_DOOM_NO_SUBPIXEL=1` (force off, applied at the render seam) > `PHEL_DOOM_SUBPIXEL=1` (force on) > saved choice > Terminal.app auto-off > default on. iTerm2 / kitty / WezTerm / Ghostty keep sub-pixel on.

To run full fidelity on Terminal.app instead of the auto-off:

1. **Line spacing 1.0**: Preferences -> Profiles -> Text - set **line spacing to 1.0** (the default above 1.0 is what opens the row gaps) and use a tight monospace font (SF Mono, Menlo, Fira Code). This removes most seams with Sub-pixel left on.
2. **Re-enable Sub-pixel**: turn the `Sub-pixel` setting back on (persists, see [settings.md](settings.md)) or run with `PHEL_DOOM_SUBPIXEL=1`. The `subpixel?` gate in `frame->string` ANDs the setting with `PHEL_DOOM_NO_SUBPIXEL`.

iTerm2 / kitty / WezTerm / Ghostty need none of this.

## Pixel-doubled mode (auto, big screens on slow machines)

When the game-loop's startup calibration finds full detail too slow for a smooth framerate on a big screen (cell area beyond 200x45 - a terminal at or below that size always keeps full detail; see `docs/game-loop.md`), `frame->string` gets `:px2? true` in stats: the scene renders at half resolution (svw x svh) and each scene cell paints a 2x2 terminal block - quarter the per-cell work, still the whole terminal. Key invariants:

- **Same framing, no zoom.** The cast runs at the FULL width with `scale 2` (full-width FOV tables, one ray per two columns) and is compacted to scene width by `compact-cast-2`; wall heights, enemy projection and the billboard painters all take an explicit `pd` (= `proj-dist / 2`) so on-screen sizes match full detail exactly.
- **Sub-row wall seams.** The same sub-row seam mixer as full detail (see "Sub-row wall seams" above), at 4 sub-rows per scene cell inside the 4-sample pack - identical half-row absolute precision, so the diagonal silhouettes do not get chunkier when the mode kicks in.
- **Half-block row pairs, full vertical fidelity.** The sky / floor / wall branches sample FOUR vertical sub-texels per scene cell (packed into one 32-bit int by a single branch dispatch) and compose the output row pair as two ▀ cells (`halfblock` memo) - the same 2-sub-pixels-per-terminal-row density as the full-detail path, so vertical colour detail does not drop when the mode kicks in. Only the horizontal axis is doubled.
- **Sprites keep their detail.** `enemy-sprite-quad` returns the raw 2x2 texel quad and the emitter spreads it over the real 2x2 block; transparent texels fall back to the base pair per quadrant.
- **Emission.** The upper row streams into `parts`; the lower row accumulates in a per-row buffer appended after the upper row's newline. Runs of identical cells coalesce with a continuation glyph that matches the cell - a bare `▀` for half-block cells (the SGR fg/bg persists across characters) or a space for BG cells. Composite glyph cells (doors, edges, pickups) are pushed literally twice so glyphs survive the doubling. Text/HUD overlays (crosshair, compass, weapon sprite, minimap) keep full-resolution coordinates; the scene-coordinate painters (`paint-door-face`, `paint-face-overlay`) take a pixel-scale factor instead.

## Responsive help panel

H/ESC info menu width-adaptive: max 44 chars, min 36. Drops CONTROLS section first, then COMPASS HINT on squeeze.

## Hostile reticle (issue #458)

The crosshair paints steady red while `stats :hostile?` is set, which `frame-stats` fills from `combat/target-in-sights?` (see [combat.md](combat.md#hostile-reticle-issue-458)). Kill, wound and muzzle-flash attributes still win over it - newer information. No blink.

## Attack poses (issue #463)

Each monster has a second baked frame - the pose it holds during its wind-up - selected in the zone pass when the projection's `:state` is `:attacking`. One frame per type meant a monster about to swing looked exactly like one standing still, so the `!` telegraph was carrying the whole read on its own.

`attack-sprites` is a separate map beside `enemy-sprites` rather than a restructure of it: that map IS the rest pose, so leaving it untouched keeps its consumers, its mip chain and the golden frames exactly as they are, and a type without a baked attack frame simply keeps resting. `attack-mips` runs the same box filter, m2 contrast-stretch and silhouette-darken, so a winding-up monster at distance reads like a resting one.

Freedoom does not follow Doom's frame letters for every actor: the revenant and archvile walk on A/B/C (combo-named with their mirrored rotations) and attack later in the alphabet, and the archvile's attack frames are rotation-0 - one sprite for every angle. The bake tool verifies each name against the WAD directory and reports anything missing instead of dropping it silently.

Cost, measured: `enemy_sprites_data.phel` 486 KB -> 621 KB, phar 4.081 -> 4.106 MB (+24 KB - the grids compress well), cold start 162 -> 190 ms for the extra load-time mip chains. The walk cycle is deliberately NOT baked: a two-frame rest/walk alternation at terminal resolution risks reading as silhouette flicker at mid range, which is the shimmer the sprite mips exist to kill.

## Attack telegraph (issue #457)

A steady `!` one row above the head of any enemy in the `:attacking` state, in the type's head colour on a dark BG. Casters freeze for a 0.6-0.8s windup before the bolt launches and melee monsters for 0.3-0.8s before the swing, which is what makes dodging a skill - but in sprite mode there was nothing to read: the billboard is one baked frame and `paint-face-overlay` is skipped, so a far cacodemon about to fire looked exactly like a dormant one.

`paint-attack-telegraphs` filters the enemy bundle the zone pass already built (`project-enemy-pd` carries `:state` at no extra cost), so at full detail it is one pass over an existing list. Pixel-doubled mode re-projects at `svw` because the scene casts with a halved numerator - see below. Held for the whole windup with no pulse, tracking the pitch shear, and scaled by the sprite's own `:scale` so the boss's mark sits above its 2x head rather than on its chest.

Depth-gated by `enemy-front-visible-at?` like the face glyph, and for the same reason: `collect-enemy-projs` projects every alive enemy in the frustum with no occlusion test, so an ungated mark would float over the wall an enemy is winding up behind - a free wallhack pointing at the next ambush. Scene-space contract as well: `vw` / `vh` / `dists` / `edists` / `pr` are scene cells and `sc` scales the emitted terminal coordinates.

Pixel-doubled mode needs the SCENE projection numerator, not the full one: the px2 scene casts and places sprite bodies with `scene-pd = 0.5 * proj-dist`, so a bundle projected at `svw` with the full numerator puts an off-centre enemy at roughly twice its real horizontal offset - and the depth gate then samples `dists` / `edists` at that drifted column. `collect-enemy-projs-pd` takes the numerator for exactly this, and BOTH px2 overlays (the attack telegraph and the face glyph, issue #477) use it.

Measured drift before the fix, at a 120-column terminal pixel-doubled: an enemy 1 world unit off axis had its glyph 12 terminal columns from its body, and at 3 units 34 columns - far enough to sit on a different enemy or off screen. It only ever showed in glyph mode, since sprite mode skips the face overlay entirely, which is why no golden frame caught it.

Two overlaps are deliberate. A wounded attacker's HP digit targets the same cell; the telegraph paints later, so the `!` wins during the windup and the digit resumes after - the windup is the more urgent read. And a point-blank attacker's mark can land on HUD row 1 or 2, which is better than hiding the cue on the enemy about to hit you.

## First-run key hints (issue #467)

One dim, steady line along the bottom of the viewport for the first fifteen seconds of level 1: `WASD move   mouse / arrows look   SPACE fire   F use   TAB help`. A first-time player landed in L1 with no reminder of the controls at all - the help panel exists but has to be discovered, and the objective splash says what to do, never how.

L1 only (every later level is reached by someone who already walked through a door), and it retires early the moment the player has moved, turned and fired, since after that it is furniture. `:hint-secs` decays with the other feel timers; `note-hint-progress` is a no-op once the strip is down, which is every frame of the rest of the game. Suppressed under `vh` 12 and clipped to the viewport width. Quick-saves drop it - somebody loading a save is past needing it.

## Message line (issue #456)

One left-aligned row at row 3 naming what just happened: `Picked up a heart.`, `Picked up the BLUE keycard.`, `You got the SHOTGUN!`, `A secret is revealed!`, or the weapon and its ammo on a slot switch. Before it, every pickup was the same door tink plus the item vanishing, so a first-timer could not tell a shard from an ammo box or know a keycard was now held.

The model is two flat world fields, `:msg-text` and `:msg-secs` (`state/push-msg`, 2.0s), decayed with every other feel timer in `combat/decay-timers`. `paint-message` gates on `message-visible?`: text present, timer running, `vh >= 8`. Held steady for its whole ttl with no blink (calm 3D view), clipped with `mb_substr` to the viewport width so a long name cannot wrap into the scene, and byte-identical to the old frame when there is nothing to say. Quick-saves drop both fields - a save must not load mid-message.

## Why so many overlay passes

Walls/sky/floor/enemies go into one string via the row loop. HUD, minimap, crosshair use absolute cursor positioning escapes (`\e[r;cH`) to paint anywhere. Alternate screen buffer + cursor-home redraw overwrites in place: no flicker, no scroll, no full clear.

See [performance.md](performance.md).

## Calm 3D view (no decorative blinks)

The 3D view is deliberately calm: it carries no decorative blinks or strobes. Cues are either omitted (pure decoration, no information) or held steady while their state is live, so the information stays without the flicker. This is the default for everyone, not a per-setting toggle.

Removed entirely (decorative, carried no information):

- The lights `paint-flicker` overlay (dark scanlines on alternate rows). Its physics driver `tick-flicker` and the `:flicker-active-secs` / `:flicker-cooldown` state were removed too.
- The blinking door-eye `paint-door-face` (an SGR-5 hardware-blink red `ʘ` on door columns). Its driver `tick-door-face` and the `:door-face-active-secs` / `:door-face-cooldown` state were removed too. The door is already marked by its steady-bright shade + glyph and the minimap door marker.
- The jump-scare glyph swap in `paint-face-overlay` (an SGR-5 hardware-blink magenta skull painted on alive enemies during a scare window). The resting / `:face-attack` faces already carry the same information. The `tick-scare` driver stays because its other half (`:silence-tick?`) still gates an audio cue; only the visual skull was dropped.

Held steady (info kept, on/off pulse dropped):

- Doors and the boss door (`door-bright?` / `door-tex-boost`) stay on their bright frame. The aggro-head danger cue (`enemy-aggro-head-string` via `aggro-bright?`) stays on its full-brightness head colour.
- `paint-heartbeat-vignette` is a steady dim-red edge in the last ~2 hearts (no per-frame heartbeat-phase throb). `paint-berserk-tint` holds the deep-crimson border (no bright/dim swap).
- The HUD labels `paint-low-ammo`, `paint-rear-warning`, `paint-reload-reminder` (the `reload-reminder-visible?` cadence gate was removed) and the powerup banners `paint-timed-badge` -> berserk/invuln stay visible the whole time their state is active.
- The `JAMMED` chip in `paint-heat-bar` and the low-health hearts strip in `paint-hearts-hud` are steady bright (no on/off blink).

There is NO `\e[5` terminal hardware-blink SGR anywhere in `src/io/render/` any more.

Kept as-is (deliberate, not a random blink):

- Single-shot feedback - the directional `paint-hit-vignette`, the kill flash, the `paint-empty-click` CLICK prompt, and the crosshair hit-marker (`paint-crosshair` swaps the `+` for a `✗`/`×` while `stats[:hit-fx]` is live, see [combat.md](combat.md)). These are one-shot confirmations of an event, not ambient strobes.
- Interactive-pickup throb (hearts/ammo/spheres/keycards/etc.) - a gentle two-shade glow that draws the eye to an item, not an on/off blink.

The calm behaviour above is the default for everyone and gates no render branch. All of this is a once-per-frame overlay branch, so the per-cell hot loop is untouched.

## Accessibility: colorblind palettes

The minimap keycard (`k`) and door (`▌`) markers are the only minimap glyphs distinguished by COLOUR alone (the blue/red/yellow triad shares one glyph each); every other marker carries a distinct glyph already (shape-not-colour, CHANGELOG 0.3.0). `palette/colorblind-markers` remaps just that triad for the `:colorblind` Settings mode (`:none` keeps the defaults):

- `:deuteran` / `:protan` (red-green) -> sky-blue (39) / orange (208) / white (231).
- `:tritan` (blue-yellow) -> blue (33) / red (196) / white (231).

Each triad is separated by BRIGHTNESS (preserved under every CVD type) as well as hue, and the same 256-code is applied to a key and its matching door so "match key colour to door colour" still holds. `minimap-rows` reads the mode from `(:settings world)` and selects the six markers ONCE per frame (overlay-only), so the per-cell hot loop is untouched. `cb-triad` uses `def-` with a `;;` comment (not a string docstring, which `def-` would store as the value).

## Minimap panel (frame + inset)

The minimap is a once-per-frame overlay blitted via absolute cursor positioning; the 3D per-cell loop emits flat sky for the cells the overlay will overdraw (a row-constant `mini-lim`, not per-cell work), so the panel is free on the hot path.

`layout` returns the content origin (`:map-col` / `:map-row`) and width (`:map-mw`). The content is wrapped in a box-drawing panel by `minimap-frame` (`hud.phel`): a top border carrying a cyan `MAP` title strip, each content row flanked by `│`, and a bottom border, all in a dim grey border colour so the chrome reads as a deliberate HUD element rather than glyphs floating over the world. The panel is inset one row from the top edge (row 1 margin, row 2 top border, content from row 3) and stays flush to the right edge: the right border occupies what would otherwise be an edge-butting glyph column. There is no right-edge margin because the per-row 3D skip runs from a left column to end-of-row, so reserving a right margin would leak flat sky there.

The skip is a rectangle, not a half-plane: `mini-row-lo`/`mini-row-hi` (scene rows) bound it vertically so the top-margin row and everything below the panel render the real 3D scene, and `mini-col0` bounds it on the left. The same rectangle is mirrored into scene-cell coordinates (`mini-srow-lo`/`mini-srow-hi`/`mini-scol0`) for the pixel-doubled path. When the map is hidden the bounds collapse to sentinels that never match, so the skip is a no-op.

## Minimap fog-of-war (issue #67)

Cells stay hidden behind `minimap-unseen` until the player visually crosses them. `mark-visible-cells` runs once per frame: scans `visit-radius = 8` bounding box, runs Bresenham `los-clear?` per cell, stamps `:visited` PHP array (keyed by `y * width + x`).

`minimap-rows` reads `:visited` and paints `minimap-unseen` for unseen blocks. Pickup glyphs only paint if visited.

`:full-map?` (set by `--full-map` / `-f` CLI flag) marks all cells visited; useful for level editors and screenshots.

## Weapon viewmodel sprites (Freedoom)

The first-person gun (`paint-weapon-hud`) uses baked Freedoom (BSD) viewmodels. `tools/bake-weapon-sprites.phel` decodes the Doom picture lumps from a Freedoom WAD, maps the palette to xterm-256, downsamples to a small bottom-strip height, and writes `src/io/render/weapon-sprites-data` (a per-weapon `{:w :h :px}` grid, -1 = transparent). License-clean, no binary asset in the repo; classic-DOOM weapons only (no super shotgun).

`paint-weapon-sprite` pairs two pixel rows per half-block cell (`▀`/`▄`), bottom-anchored, reusing the reload drop + recoil kick. `weapon-row-string` keeps it cheap: fully transparent cells collapse to one cursor-forward (live floor shows through, no halo), half-lit cells back their transparent half with the row's floor colour, and a colour SGR is emitted only when it changes from the previous cell. Worst-case overlay (chaingun/BFG) is about 1.3 ms and 6 KB per frame; the env probe is memoised so there is no per-frame `getenv`.

## Asset attribution

Weapon sprites, weapon-fire sounds, and enemy billboard sprites are derived from [Freedoom](https://freedoom.github.io/) (`freedoom1.wad` + `freedoom2.wad`), distributed under the 3-clause BSD license. They are baked into `src/` data files by the scripts under `tools/` (`bake-weapon-sprites`, `bake-weapon-sounds`, `bake-enemy-sprites`); re-bake from a Freedoom WAD rather than hand-editing.
