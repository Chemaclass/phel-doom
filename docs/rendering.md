# Rendering

The render layer builds one ANSI string per frame from `world` and `stats` and writes it to stdout.

Callers require the facade `phel-doom.io.render` (`src/io/render.phel`), never a sub-namespace. It re-exports `render!`, `clear-screen`, `read-perf-snapshot`, the full-screen entry points, and helpers tests use (`direction-char`, `project-enemy`, `enemy-front-visible-at?`, `scene-rows`, `reload-reminder-visible?`, `build-blood-cols`, `help-menu-rows`).

| Namespace | File | Responsibility |
|-----------|------|----------------|
| `...render.buffer` | `buffer.phel` | Hot-loop php-array macros (`buf-mk` / `buf-set` / `buf-get` / `buf-push`). |
| `...render.palette` | `palette.phel` | Colour and glyph constants, shade tables, `nearest-256`, colorblind markers, floor themes. |
| `...render.frame-math` | `frame_math.phel` | Fog LUTs, gradients, half-block and quadrant cell caches, enemy projection, visibility tests. |
| `...render.enemy-sprite` | `enemy_sprite.phel` | Sprite LOD, mip chains, sprite fog, per-cell sprite sampling. |
| `...render.hud` | `hud.phel` | Minimap, F3 debug line, help, pause and settings menus. |
| `...render.paint` | `paint.phel` | Overlays: face glyph, crosshair, vignettes, badges, messages, weapon viewmodel. |
| `...render.sprites` | `sprites.phel` | Pickup, projectile and tracer billboards, death and blood FX, `sprites-enabled?`. |
| `...render.main` | `main.phel` | `frame->string`, the scene emitters, `render!`, perf snapshot. |
| `...render.screens` | `screens.phel` | Start menu, settings page, intermission, death and victory screens. |

`*_data.phel` files hold baked assets. Dependencies are acyclic (`buffer -> palette -> frame-math -> {enemy-sprite, hud, paint, sprites} -> {main, screens} -> facade`). Cross-namespace calls compile to static PHP calls and the buffer macros inline, so the split is free.

## How a frame is drawn

`render! [world stats cols rows]` re-asserts the hidden cursor (and mouse pointer while Mouse is on), moves the cursor home, prints `pain-flash-frame` (one dark red frame while `:flash-secs > 0`, #465) or `frame->string`, and flushes. During `:shake-secs` the home anchor shifts up to 2 columns. With F3 on it also times the frame for the perf snapshot. It uses `print`, never `php/fwrite`: a partial write silently truncates the frame (PR #54).

The alternate screen is redrawn in place from cursor home: no clear, no scroll, no flicker. The scene is one row-major string. Everything else paints on top with absolute cursor moves (`\e[r;cH`).

`frame->string` in order:

```
layout                -> viewport vw x vh, minimap placement
cast-frame            -> dists, hits, sides, wallxs, floordxs/floordys, hxs/hys
frame-gradients       -> memoized sky/floor gradients + floor-cast tables
compute-wall-shades   -> per column: tops/bots, edge cells, texture u/level/array/size
enemy zone pass       -> sprite boxes or glyph zones per column, edists
blood-paint buffer    -> death/blood FX, pickups, projectiles, tracers
build-wall-sub-bounds -> sub-row wall top/bottom per column
emit-scene-px1 / px2  -> wall band pass, then row loop; RLE; php/implode
overlays              -> HUD, minimap, crosshair, cues, weapon, menus
```

`frame-gradients` is one memo slot keyed on viewport height, pitch shear, sub-row height and floor theme, so it rebuilds on resize, pitch or bob change and level load only.

`emit-scene-px1` (full detail) first resolves each column's wall band into a flat `wall-cells` array, so the row loop reads a wall cell with one `aget` (#530). Row loop priority, highest first: `blood-paint`, enemy sprite, wall, sky or floor.

Overlays follow the numbered `p1`..`p20b` chain in `frame->string`: debug row, tagline and minimap first, then crosshair, vignettes, HUD strips, weapon, prompts, enemy HP digits, attack telegraphs, message and hint lines, and the pause, settings and help menus last. Each painter takes and returns `parts`, because PHP arrays pass by value.

**Run-length encoding.** Consecutive identical cells coalesce into one escape plus N spaces (or N `▀`, since SGR state persists). This cuts output 5-10x on flat rows.

## Half-block sub-pixel rendering (floor / walls / sky)

A terminal cell holds two colours, fg and bg. Fidelity comes from subdividing the cell, not from more colours. Floor, wall body and sky emit `▀` with the **top colour as fg and the bottom as bg**: two sub-pixels per cell, 2x vertical resolution. Cells are about 2:1 tall, so sub-pixels read as square (the chafa/timg/viu technique).

- **Floor:** `build-floor-dperp-sub` / `build-floor-level-sub` are per-sub-row twins of the cell tables (`floor-cast-k-sub = 2·floor-cast-k`). Each cell samples a farther (top) and nearer (bottom) ground point.
- **Wall body:** two texture-V samples down the column.
- **Sky:** `build-sky-halfblock` bakes one row-constant `▀` per row, so sky rows still coalesce.

`halfblock` memoizes each `top*256+bot` pair in `half-cell-cache`: one `aget` after warmup. `top == bot` collapses to a plain BG cell, which coalesces with flat neighbours. Measured at landing (PR #184): about +2% CPU, and 50-70% more bytes on big screens, so cap with `--max-cols`. `half-cell-cache` is a `def-`, which stores a string docstring AS the value, so its doc is a `;;` comment.

### macOS Terminal.app compatibility

iTerm2, kitty, WezTerm and Ghostty render `▀` pixel-tight. **Terminal.app anti-aliases block glyphs and leaves inter-row gaps**, so the scene shows horizontal seams and HUD borders look gappy (#332). Colour is fine: the default path is 256-colour, which Terminal.app supports.

On startup `load-settings` reads `$TERM_PROGRAM`. On `Apple_Terminal`, a player with no saved `Sub-pixel` choice gets it **off** (`io/input.halfblock-seams?` -> `core/settings.resolve-subpixel`). Precedence: `PHEL_DOOM_NO_SUBPIXEL=1` (force off) > `PHEL_DOOM_SUBPIXEL=1` (force on) > saved choice > Terminal.app auto-off > default on.

For full fidelity there: set Preferences -> Profiles -> Text **line spacing to 1.0** with a tight monospace font (SF Mono, Menlo, Fira Code), then turn `Sub-pixel` back on (see [settings.md](settings.md)).

## Per-column shade composition

Walls shade once per column in `compute-wall-shades`:

```
base = int(23 * (1 - min(1, dist / max-depth)) ^ 0.6)   ; gamma 0.6 lifts mid-range
idx  = clamp(0, 23, base + (side == 0 ? 3 : 0)          ; vertical faces brighter
                         + light-bias)                  ; room light (#418)
idx  = clamp(0, 23, idx - haze-shift)                   ; near-death haze, muzzle extralight
```

Walls and sky index a 24-step grayscale `shade-table`, so stone stays neutral and enemies pop. The floor carries a per-level theme tint (`palette/theme-floor-code`). `idx` doubles as the texture fog level.

- **Room light (#418)** (`:light` setting): `light-bias` is the hit cell's entry in the world's `:light-grid` (`core/light`, lamp pools on a coarse lattice). One `aget` per column at `hxs`/`hys`, never per texel. Off, the grid is nil and the frame is byte-identical.
- **Near-death haze:** `haze-shift` pulls walls toward black as lives run out. Sky and floor are untouched.
- **Weapon-fire extralight (#413),** the stand-in for a muzzle point-light (epic #408): `frame->string` subtracts `combat/fire-extralight` from `haze-shift`. It is `muzzle-extralight-steps` (4) during the first `muzzle-flash-fraction` (0.25) of `fire-anim`, else 0. The net shift can go negative, so `idx` clamps at 23 too: without that clamp the index runs past the table and the frame breaks. The pain flash short-circuits `frame->string`, so the two never meet.
- **Doors** skip room light and haze (see [Textured doors](#textured-doors)).

## Sky and floor gradients

Per-row shade by distance from the horizon: darkest at the horizon, brightest overhead and underfoot. `build-horizon-gradient` (sky) and `build-themed-gradient` (floor, faint odd-row stripe) bake paint strings; their code twins feed the seam mixer and edge cells.

## Atmospheric fog tint (tinted + filmic)

Fog on textured walls and floor fades toward a near-neutral grey haze (`fog-rgb` = 112/112/120, re-quantized to grey ~118), not black, along a normalised ACES-like filmic curve: the toe keeps shadow contrast, the shoulder rolls off highlights. Far surfaces converge on the haze, so depth reads "far" rather than "dark".

The 256-colour tint stays neutral because the palette has no "barely cool" mid-grey: near-neutral snaps onto the grey ramp, anything bluer jumps to cube 95/95/135, which read as a blue band through far openings. Truecolor has no such limit (#419): its target `fog-rgb-tc` = 104/110/130 has the same luminance and a real cool bias.

It all bakes at load. `fade-256-fog` lerps each code toward the tint in RGB and re-quantizes with `palette/nearest-256` into `tex-fade-table` (24 levels x 256 codes) and the themed gradients, so the hot path stays one nested `aget`. `sprite-fade` derives from the same table. `PHEL_DOOM_FLAT_FOG=1` restores the linear fade to black. The grayscale sky and the seam darkening are not tinted.

## Textured walls

Stone walls sample the baked Freedoom flat WALL70_2 (64x64, `wall_texture_data.phel`): `u = wallxs[col] * size` from the ray's hit fraction, `v = row-within-wall * size / wall-height`. The fog level picks a row of `tex-fade-table`, and `bg-cell-cache` / `halfblock` return a ready cell. Texturing measured about +2% over flat shading at landing.

`compute-wall-shades` stores per column the texel array (`tex-px`), its size (`tex-sz`), `tex-u`, `tex-level` and wall height, so the per-cell loops are texture-agnostic. `tex-level = -1` marks an untextured column: the boss door while the boss lives, and blood-band columns, which keep a flat shade so the red wash stays clean. `PHEL_DOOM_FLAT_WALLS=1` forces flat stone and the striped flat door.

### Textured doors

Door columns (map cells 2/3/4/9, and boss door 5 once the boss is dead) sample `door-tex-px`, a procedural 64x64 amber door baked at load: rust border and frame, six planks, a mid rail. Its texels are colour-cube codes, so seam accents darken through the `seam-darken-16/-8/-5` LUTs, not `code - n`: subtraction jumps hue (amber 166 - 16 = green 150). On grayscale codes the LUTs equal subtraction.

Door fog is the wall formula with nav-cue exceptions: the level floors at 8, ignores haze and room light, adds a steady `door-tex-boost` (+3), and always samples the native 64 level. Blood-band door columns keep the flat striped door, because the seam mixer's sky and floor codes are grayscale-only.

### Secret wall tell (issue #469)

A secret wall shifts `u` by half the sampled texture size, so its pattern runs out of phase with its neighbours: Doom's misaligned-texture cue. Cast and collision do not change, and a level without secrets renders byte-identically. Secrets are worth 30% of the run rank, and before this finding one meant pressing F on every wall.

### Texture filter: distance mips for walls (issue #462)

Opt-in `Texture filter` setting (`:texmip`; `PHEL_DOOM_TEXMIP=1` forces it), covering walls and, since #494, the floor. A far wall projects a few rows out of 64 texels and point-samples a different texel each frame: shimmer. With the filter on, a column samples a box-filtered level from `wall-tex-mips` (64/32/16/8, built with the sprite path's `half-mip`), dropping a level at 3x, 6x and 24x oversampling. Doors stay at 64.

The floor filters per row, since its distance is row-constant: `floor-mip-size` reads the row's `dperp` and picks from `floor-tex-mips`. `floor-code-at` (the seam sampler) uses the same level, so a boundary cell never mixes filtered and unfiltered floor. Near rows magnify the texture, so the filter only fires in the band under the horizon.

Measured on the L1 fixture at 200x50 (share of adjacent cells whose BG differs): walls 82.5% -> 79.1%, floor horizon band 81.7% -> 80.5%, near floor unchanged; frames 2.1% smaller, frame time unchanged. Off, every size is 64, so default golden hashes hold.

## Wall edges and sub-row seams

Textured columns place the wall top and bottom in SUB-rows (half a terminal row), set by `build-wall-sub-bounds`. Only the one or two boundary cells per column resolve per sub-row (the `seam-shade!` macro). A receding wall's silhouette steps in half-row diagonals that match the floor's perspective, instead of whole-cell stairs.

A graduated dark border traces that diagonal: the wall's bottom sub-row goes near-black (`seam-darken-16`), the sub-row above and the floor's first sub-row 8 steps darker, and a 5-step lip marks the wall/sky edge. Both scales run the same mixer at half-row precision (2 sub-rows per cell at full detail, 4 pixel-doubled). It measured about 15% of render time at full detail when it landed.

Untextured columns (boss door, blood band, glyph-mode enemy columns, textures or sub-pixel off) use whole-cell edge bands, taking the sky or floor code at that exact row:

```
Top:    \e[48;5;<wall>;38;5;<sky-at-row>m▀      (wall BG, sky FG)
Bottom: \e[48;5;<floor-at-row>;38;5;<wall>m▀    (floor BG, wall FG)
```

## Textured floor (floor-casting)

The ground is cast per cell. A floor cell `p` rows below the horizon sits at perpendicular distance `floor-cast-k / p` (`build-floor-dperp`), with `floor-cast-k = proj-dist * 0.5 / char-aspect` (eye at z = 0.5). The world point is `player + dperp * (floordxs[col], floordys[col])`, a basis from the cast, so there is no per-cell trig.

The floor samples `floor-tex-px`, the wall texture with contrast halved toward mid-grey (`floor-tex-soften` 0.5), because full-contrast cracks at grazing angles read as black speckle. It sits `floor-darken` (4) fog steps below a wall at the same distance, so the ground reads shadowed. Blood columns keep the red gradient. `PHEL_DOOM_FLAT_FLOOR=1` restores the flat floor. Cost measured about +12% (local, no JIT).

## Optional render modes

Only Sub-pixel defaults on. Every other mode is byte-identical to the shipped frame when off. `tests/io/render-flags-test.phel` pins the non-default paths.

| Setting | Env override | Effect | Scope |
|---------|--------------|--------|-------|
| Sub-pixel (`:subpixel`) | `PHEL_DOOM_NO_SUBPIXEL=1` / `PHEL_DOOM_SUBPIXEL=1` | `▀` cells. Off: one colour per cell. | px1 (px2 always pairs rows) |
| Low detail (`:fast-walls`) | `PHEL_DOOM_FLAT_WALLTEX=1` | Wall and floor interiors as one sample per cell; silhouettes stay sub-pixel. Measured ~11-26% less render time, ~31-40% fewer bytes on large screens. | px1 |
| Truecolor (`:truecolor`) | `PHEL_DOOM_TRUECOLOR=1` / `PHEL_DOOM_NO_TRUECOLOR=1` | 24-bit floor fog (`tex-fade-tc`, `halfblock-tc`) toward `fog-rgb-tc`, no cube banding. Walls stay 256-colour. | px1 floor |
| Quad detail (`:quad`) | `PHEL_DOOM_QUAD=1` / `PHEL_DOOM_NO_QUAD=1` | 2x2 quadrant glyphs (`quadblock`) on wall silhouette and floor cells, left/right samples lerped 0.25 toward each neighbour. Collapses to `▀` when left equals right. Needs Sub-pixel. | px1 |
| Texture filter (`:texmip`) | `PHEL_DOOM_TEXMIP=1` | Distance mips. | both |
| Room light (`:light`) | none | Per-cell light bias in the wall shade. | both |

px2 skips Truecolor and Quad: pixel doubling exists to save work. Dev-only A/B flags: `PHEL_DOOM_FLAT_WALLS`, `PHEL_DOOM_FLAT_FLOOR`, `PHEL_DOOM_FLAT_FOG`, `PHEL_DOOM_NO_SPRITES`. Measure any flag with `tools/bench-flags.sh`.

## Pixel-doubled mode (auto, big screens on slow machines)

When startup calibration finds full detail too slow on a screen larger than 200x45 cells, `stats` carries `:px2? true` (see [game-loop.md](game-loop.md)). The scene renders at half resolution (svw x svh) and each scene cell paints a 2x2 block: a quarter of the per-cell work. `render-scale` is a uniform 1 (one ray per column); px2 passes 2 to `cast-frame` directly.

- **Same framing.** The cast runs full width at scale 2 and `compact-cast-2` compacts it. Heights and billboards take `scene-pd = proj-dist / 2`, so on-screen sizes match full detail.
- **Full vertical fidelity.** Sky, floor and walls sample four vertical sub-texels per scene cell (packed into one int) and emit the row pair as two `▀` cells. Seams use 4 sub-rows per cell.
- **Sprites.** `enemy-sprite-quad` spreads the raw 2x2 texel quad over the real 2x2 block.
- **Emission.** The upper row streams into `parts`, the lower into a buffer appended after the newline. Composite glyph cells push twice. HUD overlays keep terminal coordinates. Scene-space painters (`paint-face-overlay`, `paint-attack-telegraphs`) take a pixel scale and a `collect-enemy-projs-pd` bundle with the scene numerator (see [Attack telegraph](#attack-telegraph-issue-457)).

## Look up/down, head bob, weapon bob

**Pitch (#243)** shears the horizon instead of re-projecting, so it casts no extra rays. `frame->string` computes `pr = projection/pitch-rows(pitch, vh)` once and adds it at every site centred on `vh/2`: wall tops, sub-row bounds, floor-cast tables, gradients, sprite and overlay anchors. The crosshair stays fixed. Math: [raycaster.md](raycaster.md#look-updown-pitch-horizon-shear).

**Head bob (#411)** adds `projection/bob-rows` to the same `pr` (and `pr-full`): `round(intensity * 0.05 * vh * sin(phase))`, a 1-2 row nod. `:bob-phase` is distance-driven in `core/physics.phel`. The bob stays out of the hit gate (`combat/aim-pr`), so a nod never moves where a shot lands.

**Weapon bob (#412)** moves the viewmodel in `paint-weapon-sprite` on the same phase: `weapon-bob-rows` (`abs(sin)`, cap 0.04, so the gun dips and never rises) and `weapon-bob-cols` (cap 0.02 sway, clamped on screen). The muzzle flash follows.

Every term is exactly 0 at `pitch = 0`, `intensity = 0` or `phase = 0`, so a level, resting or bob-off frame is byte-identical (`render-cache-test/test-frame-bytes-pinned`).

## Enemy sprite paint

`PHEL_DOOM_NO_SPRITES=1` swaps every Freedoom bitmap (enemies, pickups, projectiles, death frames, weapon) for the glyph path. The probe is memoised.

**Sprite mode (default).** `enemy_sprites_data.phel` holds an xterm-256 grid per sprite id (`{:w :h :px}`, -1 transparent). `enemy-sprite/sprite-type-map` maps `:type` to an id; pinky and spectre reuse `:demon`. Box width follows the native aspect, `half-width = round(h * sw / sh)`, and height scales by `:scale` (2.0 for `:cyber`).

The zone pass projects every enemy once (`collect-enemy-projs`) and paints back to front. Per covered column with `d < dists[c]` it stashes the box and sprite ref in `e-stop/e-sbot/e-sx/e-sxr/e-spx/e-sw/e-sh/e-fade` and leaves the wall `tops/bots` alone, so transparent texels show the wall. It records the nearest enemy per column in `edists`. A column behind a wall writes nothing, so a hidden enemy never occludes a pickup or triggers a depth-gated overlay.

`enemy-sprite-cell` samples a 2x2 texel footprint per cell. Opaque cells with horizontal variation get a quadrant glyph, others `▀`. An edge cell with one opaque sub-pixel becomes a solid `█`: clean silhouette, no halo. Sampling is centre-of-footprint (`intdiv(sub*sh + h2/2, h2)`), which removed a top-left bias that striped texel columns.

**Feet anchoring (#297).** Each billboard stands on the floor row `round(svh/2 + 0.5 * wall-px(scene-pd, d)) + pr` and extends upward. That uses `wall-px` inline, not `project-height`, to hold the built file's closure count. Face glyph, HP digit and telegraph share the anchor.

**Mips.** `sprite-mips` builds m1 (half res, a 2x2 block needs 2 opaque sources) and m2 (quarter res) at load. Double box filtering hurts small billboards, so m2 adds three passes: `min-opaque=1` (keeps horns and limbs), `contrast-stretch` (min range 40, restores the compressed luminance range) and `silhouette-darken` (0.40, a 1-pixel dark outline). `sprite-for-type-lod` picks m2 when the source is at least 3x the box height in sub-rows, m1 at 1.5x (`sh*2 >= 3*sub-rows`, no float), else native.

**Fog.** `body-fade = min(0.65, (d/max-depth)² + damage-ratio * 0.35)`, applied at half strength by `sprite-fade-index`, `(1 - fade * 0.5) * 23`. Sprites darken half as much as walls, so dark sprites (imp body lum ~88) keep their shading bands, and a max-range monster stays at least 35% lit. A wounded monster reads darker. `blit-sprite-into` gives corpses, splats, fireballs and pickups the same half-strength distance fade.

**Attack poses (#463).** A type with a baked attack frame shows it while `:state` is `:attacking`. `attack-sprites` sits beside `enemy-sprites`, so the rest pose, its mips and the golden frames stay untouched. `attack-mips` runs the same passes. Freedoom breaks Doom's frame letters for some actors (revenant and archvile walk on A/B/C; archvile attack frames are rotation 0), so the bake tool checks each name against the WAD and reports gaps. Measured at landing: sprite data 486 KB -> 621 KB, phar +24 KB, cold start 162 -> 190 ms.

**Glyph mode.** Head, body and legs zones shade via `fade-256` with the same capped fade, writing `eheads/ebodys/elegss` and overriding `tops/bots/mids/lowers`. The body glyph varies per type and alternates with `:body-glyph-alt` on `face-phase`, a 3 rad/s sine (~2 s cycle), so every enemy of a type pulses in sync. The cyberdemon carves a silhouette with `boss-col-paint`. Within `aggro-distance` (1.8) the head holds its full-brightness colour. Grounding shadows are glyph-only, painted after `edists` is complete so a far enemy's shadow never covers a near enemy (#86).

**Baked palette.** `tools/bake-enemy-sprites.phel` maps Freedoom PLAYPAL through `rgb->256` (nearest against the real cube levels and the grey ramp). Enemies use `rgb->256-lifted`: `tone-lift` (gamma 0.50, lifts dark-brown shadows), `warm-bias-code` (a grey result from a warm source, r-b >= 12, moves to the nearest warm cube code, taking warm coverage from ~31% to ~80% of opaque pixels), then `gray-shift` (+3 steps for neutral stone). Pickups use `rgb->256-pickup`, gamma lift only.

## Pickups, projectiles, death and blood FX

These paint into `blood-paint`, a php-array indexed `row*vw + col` that the row loop reads first. Each cell is gated against walls (`dists`) and nearer enemies (`edists`).

- **Pickups** (17 types: heart, armor, shards, ammo, berserk, invuln, soulsphere, backpack, three keycards, five weapon drops, chainsaw) blit Freedoom item billboards from `pickup-sprites` (longest side 18 px) whenever they are at least 2 rows tall (`ph = min(16*lodr, 0.55 * sprite-h)`, `lodr = pd / proj-dist`). Smaller, a coloured glow with a centre glyph, throbbing gently at a per-type frequency.
- **Kills:** `combat/push-blood-fx` tags the fx with the enemy `:type`, and `death-frame` maps its ttl to a collapse-to-corpse frame from `death-sprites`, plus a blood spurt for the first 0.45 s. The revenant has no death frames and keeps the blood shade.
- **Wounds** blit a small spurt from `blood-sprites` at the torso.
- **Projectiles** use `projectile-sprites :fireball`; shot tracers use `:bfg-ball` / `:rocket`.

Without sprites: ttl-tiered red blocks for deaths, an orange glow for fireballs, glow plus glyph for pickups.

## Overlays

### Face glyphs

Glyph mode only; Freedoom sprites already show a face. `paint-face-overlay` paints `:face` (alternating with `:face-alt`), or `:face-attack` within `aggro-distance`, at the upper third of the body, depth-gated by `enemy-front-visible-at?`.

### Attack telegraph (issue #457)

A steady `!` one row above the head of any enemy in `:attacking`, in warning amber (`telegraph-sgr`, the low-ammo colour) on a dark BG. Casters freeze 0.6-0.8 s before the bolt, melee monsters 0.3-0.8 s before the swing, and dodging depends on reading that. The first version used each type's head colour, a glyph-era colour unrelated to the sprite (the cacodemon's is cyan, its sprite red), so one amber replaced it.

`paint-attack-telegraphs` filters the zone pass's bundle (`:state` rides on it for free), holds for the whole windup, follows the pitch shear, and scales by `:scale` so the boss's mark clears its 2x head. It is depth-gated by `enemy-front-visible-at?`: `collect-enemy-projs` has no occlusion test, and an ungated mark over a wall is a free wallhack.

In px2 it needs the SCENE projection numerator. A bundle at `svw` with the full numerator put an off-centre enemy at about twice its offset and depth-tested the wrong column: on a 120-column terminal, 12 columns of drift at 1 world unit off axis, 34 at 3. Both px2 overlays (telegraph and face glyph, #477) use `collect-enemy-projs-pd`. Only glyph mode showed it, so no golden frame caught it.

Two overlaps are deliberate: the telegraph paints after a wounded attacker's HP digit and wins the windup, and a point-blank mark may land on HUD row 1 or 2 rather than hide.

### Crosshair

Style comes from the Crosshair setting; position is the mouse aim cell, or the screen centre with the mouse off. It paints on the BG of the cell under it: at the centre the cell the row loop captured, off-centre that column's flat wall shade. Colour precedence: kill (red `✗`), wound (yellow `×`), firing (yellow, one row up), hostile, idle. Hostile (#458) is steady red while `combat/target-in-sights?` holds (see [combat.md](combat.md#hostile-reticle-issue-458)).

### Message line and first-run hints

**Message line (#456).** Row 3, left-aligned: `Picked up the BLUE keycard.`, `You got the SHOTGUN!`, a slot switch. World fields `:msg-text` / `:msg-secs` (`state/push-msg`, 2.0 s), decayed in `combat/decay-timers`. `message-visible?` needs text, time left and `vh >= 8`. It clips at the minimap's left margin, since the panel also starts on row 3. Before it, every pickup was the same tink.

**Hint strip (#467).** One dim steady line at the bottom for up to 15 s on level 1: `WASD move   mouse / arrows look   SPACE fire   F use   H help`. It retires once the player has moved, turned and fired (`note-hint-progress`). Hidden under `vh` 12.

Quick-saves drop both.

### Minimap panel

The row loop emits flat sky for the rectangle the panel covers (`mini-col0`, `mini-row-lo`/`-hi`, and scene-cell twins for px2), so the panel costs the hot path nothing. Hidden, the bounds are sentinels that never match. `minimap-frame` draws a dim box with a cyan `MAP` title: row 1 margin, row 2 border, content from row 3, flush right. There is no right margin, because the skip runs to end of row and a margin would leak flat sky. `layout` (`frame_math.phel`) sizes the map at a third of the terminal width, capped at 40 columns and floored at 8, and picks the grid-to-cell step to fit.

**Fog-of-war (#67).** `engine/mark-visible-cells` stamps `:visited` (keyed `y * width + x`) for cells within `visit-radius` 8 that pass a Bresenham `los-clear?`. `minimap-rows` hides the rest, pickups included. `--full-map` / `-f` reveals all.

### Accessibility: colorblind palettes

Keycard `k` and door `▌` markers are the only minimap glyphs told apart by colour alone. `palette/colorblind-markers` remaps the triad for the `:colorblind` setting: `:deuteran` / `:protan` -> 39 / 208 / 231, `:tritan` -> 33 / 196 / 231. Each triad also separates by brightness, and a key and its door share a code. Selected once per frame.

### Weapon viewmodel

`paint-weapon-hud` paints a baked Freedoom viewmodel when the weapon has one, sprites are on and it fits; otherwise the ASCII silhouette (`paint-pistol-hud`). `tools/bake-weapon-sprites.phel` writes `weapon_sprites_data.phel` (no super shotgun). BFG, incinerator and rocket overlay a muzzle-flash sprite while firing. The hitscan guns do not, because a flash hid their recoil.

`paint-weapon-sprite` packs two pixel rows per cell (`▀`/`▄`), bottom-anchored, with reload drop, recoil and bob. `weapon-row-string` turns transparent runs into one cursor-forward, backs a half-lit cell with the row's floor colour, and emits SGR only on change. Measured worst case (chaingun, BFG): about 1.3 ms and 6 KB per frame.

### Responsive menus

The H info menu is 44 columns, shrinking to 36. Blocks are added in page order, which is priority order (RUN and PLAYER last longest, CONTROLS goes first), and the first block that does not fit ends the panel. A later, smaller block is never squeezed in: COMPASS HINT where WEAPONS should be reads as a missing table. Under 30 rows the spacers go. The pause menu drops its spacers under 14 rows.

`centred-box-string` is the backstop: it truncates a box taller than the viewport and keeps the closing row. A terminal clamps writes past its last line onto that line, so overflow rows stack (the old 28-row minimum did this on 80x24). `tests/io/screen-golden-test.phel` pins each screen's bytes, its row count, and monotonic shedding.

### Overlay coverage

`tests/io/render-cache-test.phel` pins a quiet frame. `tests/io/overlay-golden-test.phel` pins every overlay at once, one assertion each, so a broken hash names the one that moved; it catches paint-order and shared-cell interactions. Disabling the telegraph, message line or hint strip each fails it. Its scene mirrors `tools/shots/showcase.phel`, so you can look at a moved hash:

```bash
tools/frame-shot.sh tools/shots/showcase.phel /tmp/showcase.png
```

## Calm 3D view (no decorative blinks)

The 3D view has no decorative blinks or strobes, for everyone. Cues without information are removed; cues with information hold steady. `tests/io/calm-view-test.phel` pins the steady cues.

- **Removed:** the lights-flicker scanlines, the blinking SGR-5 door-eye, and the jump-scare skull in the face overlay, with their drivers and state. `enemy/tick-scare` stays for its audio half (`:silence-tick?`).
- **Held steady:** doors, the boss door and the minimap door glyph; the aggro head colour; the heartbeat edge (dim red at 4 HP or less); the berserk border; the low-ammo, rear-warning and reload labels (`reload-reminder-visible?` has no blink cadence); the berserk and invuln badges; the `JAMMED` chip; the hearts strip.
- **Kept:** single-shot feedback (hit vignette, kill flash, CLICK, crosshair hit-marker, see [combat.md](combat.md)) and the gentle two-shade pickup glow.

There is no `\e[5` hardware-blink SGR under `src/io/render/`. None of this touches the per-cell loop.

## Lessons

- Seam and edge cells need the gradient code at their row. Flat constants left dark dots.
- Quantize against the real xterm cube levels. Even spacing turned brown sprites into grey-green confetti.
- Keep 256-colour fog neutral. Near-neutral snaps to grey and anything bluer becomes a blue band.
- Do not gray-shift bright art. The +3 shift washed every pickup into a pale rectangle.
- Pick a mip level against sub-rows, not cell rows, or px2 lands two levels off.
- Offset a secret wall by half the live mip size. A fixed 32 is a whole tile on the 32 mip.
- Do not mip the near floor. Those rows magnify the texture, and a smaller level only blurs them.
- Resolve a frame-level flag in `frame->string` with a plain call. An `if` or `or` in a binding value closure-compiles and moves the tracked closure count.
- Scene-space overlays in px2 need the scene projection numerator, or they drift off their enemy.
- Do not bake a walk cycle. Two frames at terminal resolution read as silhouette flicker, the shimmer the mips exist to kill.
- The floor cannot use the linear per-row floor-step shortcut. The angular ray model rules it out, so it stays a per-cell mul-add.

See [performance.md](performance.md) for costs and guards.

## Asset attribution

Weapon sprites, weapon-fire sounds, and enemy, item and effect sprites derive from [Freedoom](https://freedoom.github.io/) (`freedoom1.wad` + `freedoom2.wad`), 3-clause BSD. `tools/bake-weapon-sprites.phel`, `tools/bake-weapon-sounds.phel` and `tools/bake-enemy-sprites.phel` bake them into `src/` data files. Re-bake from a WAD instead of hand-editing the data.
