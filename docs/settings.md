# Settings

Player options across audio, gameplay defaults, input, accessibility and performance (full set in the Fields table below). Persisted to `$HOME/.phel-doom-settings.json`, plain JSON and editable by hand, so choices survive restarts.

## Architecture

- `src/core/settings.phel` (pure): the data model. Defaults, `coerce-settings` (clamp/validate), `move-cursor`, `adjust`, volume mappings (`music-volume`, `sfx-scalar`).
- `src/io/settings.phel` (io): `load-settings` / `save-settings!`. A bad file never blocks startup, it returns defaults. Difficulty is stored as a string, keyword-ised on load.
- `commands/play.phel`: wires page into start menu + in-game overlay, applies volumes to `io/sound` + `io/music`.

The page groups fields under section headers (Audio, Video, Play, Controls, Access) and shows a one-line hint for the field under the cursor (issue #468). Both come from the same `page-fields` table that drives navigation and rendering, so a new field cannot ship without a section and a hint. A test asserts it. On a terminal too short for seventeen fields the LIST scrolls around the cursor instead of the box growing past the screen. The selected field is always on screen.

## Fields

| Field | Type | Range | Effect |
|-------|------|-------|--------|
| Music | pct | 0-100 (step 10) | OST `-v` level. 0% stops the soundtrack. 60% = 0.30 (default). Capped at 0.5, so max volume never masks footsteps. |
| SFX | pct | 0-100 (step 10) | Global multiplier on `play-sfx!` events. 0% mutes without touching the N toggle. |
| Minimap | bool | on / off | Default `:show-map` state. Live edits apply immediately. |
| Difficulty | enum | easy / normal / hard / nightmare | Default for next run. CLI `--difficulty` overrides. Baked at level build time. |
| Crosshair | enum | cross / dot / open / off | Idle reticle glyph (`+` / `·` / `○` / hidden). `off` hides the idle reticle; the hit-marker still flashes on a hit. With mouselook on, `off` still draws a minimal centre dot, so the aim point is never lost. |
| Mouse | bool | on / off | FPS-style mouselook (issue #246), **on by default**. Move the mouse to turn + look up/down, left-click to fire. Off omits the xterm mouse-tracking escapes entirely, so a terminal that dislikes pointer capture opts out cleanly. Keyboard path unchanged either way. See [input.md](input.md#mouse-look-issue-246). |
| Sensitivity | pct | 0-100 (step 10) | Mouselook speed multiplier, geometric around the midpoint (issue #275): `3 ^ ((pct - 50) / 50)`. **50% = the neutral 1.0x** (saved-settings back-compat). 0% slows to ~0.33x (1/3) for fine aiming, 100% speeds up to 3.0x for fast flicks. Each end sits the same ratio from neutral, so the slider spans a useful slow <-> fast range instead of the old narrow 0..2x linear band. Raise for faster turns, lower for fine tracking. The camera turn already tracks pointer speed (a 2x-bigger flick = 2x yaw); this only scales that proportional response. Mapped through `core/settings.mouse-sensitivity`. |
| Run timer | bool | on / off | Append the elapsed run time (`M:SS`) to the row-2 HUD strip. |
| High contrast | bool | on / off | Accessibility. Un-dims the dim/grey HUD elements: compass non-facing letters, empty heart pips and a healthy ammo-reserve count render bold white instead of SGR-dim/grey, so the HUD reads on washed-out or low-quality terminals. |
| Colorblind | enum | none / deuteran / protan / tritan | Accessibility (colour-vision deficiency). The minimap keycard (`k`) and door (`▌`) markers are the only glyphs told apart by colour alone (blue / red / yellow share a glyph each), so a CVD player can confuse which key opens which door. Non-`none` modes remap that triad to a brightness-plus-hue-separated, CVD-safe set, the same code on a key and its matching door: `deuteran` + `protan` (red-green) use sky-blue / orange / white, `tritan` (blue-yellow) uses blue / red / white. Overlay-only palette swap, selected once per frame, so zero hot-3D-path cost. Every other marker already carries a distinct glyph (shape-not-colour). |
| Low detail | bool | on / off | Performance. Paints each wall AND floor cell as one flat colour instead of a two-sample `▀` half-block. Trades interior vertical texture detail for speed: ~11-26% less render time (scaling up with screen size), ~31-40% fewer bytes per frame. Wall silhouettes and top/bottom edges keep their sub-pixel precision (the seam mixer still runs); sky and sprites are untouched. Off by default, so the shipped look is unchanged (golden frame hashes identical). Aimed at large terminals and slower hardware where the per-cell render loop dominates. The internal setting key stays `:fast-walls` (save-file back-compat). Dev / bench override: `PHEL_DOOM_FLAT_WALLTEX=1` forces it without touching saved settings. |
| View bob | pct | 0-100 (step 10) | Walk-cycle head bob (#411). **0% (default) = off**, so the shipped moving look is unchanged. Higher nods the whole scene (walls, floor, sky, enemies) further as you walk. Distance-driven: a `:bob-phase` on the world advances with ground covered in `core/physics.phel` and settles to 0 at rest, so a standing frame is byte-identical. The percent maps to a `[0, 1]` amplitude via `core/settings.view-bob-intensity`, which `core/projection.bob-rows` scales by a small fraction of the viewport height (a subtle 1-2 row nod, not a look-around). Accessibility: a motion-sensitive player leaves it at 0. Aiming is unaffected: the hit gate stays on true camera pitch, so the bob never moves where a shot lands. |
| Sub-pixel | bool | on / off | Compatibility (#332). **On** (default) draws the `▀` half-block 2-colour cells (full vertical fidelity on floor / walls / sky). **Off** falls back to one solid colour per cell. Turn it OFF on terminals that render `▀` with anti-aliased row seams or inter-line gaps, most notably **macOS Terminal.app**, where the half-block illusion breaks into visible horizontal seams. The flat-cell path renders cleanly there. Off costs vertical fidelity but is faster. See the Terminal.app note in [rendering.md](rendering.md#macos-terminalapp-compatibility). Dev / bench override: `PHEL_DOOM_NO_SUBPIXEL=1` forces it off without touching saved settings. |
| Room light | bool | on / off | Atmosphere (#418). **Off** (default) keeps the uniform distance shading, so golden frames are unchanged. **On** folds a per-cell room-light bias into the wall shade, so levels read as dark rooms with lit pools instead of even lighting. The bias grid comes from the map at load (`core/light`, lamp pools on a coarse lattice), looked up one-per-column at the ray's hit cell, so the hot path stays within budget (measured +0.5-2.5% render, off-path byte-identical). See [rendering.md](rendering.md#per-column-shade-composition). |
| HUD glyphs | enum | unicode / ascii | Symbol set for the HUD (issue #471). `unicode` draws the keycard, half-heart, info and bullet glyphs. `ascii` swaps each for a single-column stand-in, for a font that renders them as tofu, which is often double width and shifts every column after it. On first run a non-UTF-8 locale (`LC_ALL` / `LC_CTYPE` / `LANG`) defaults to `ascii`. A saved choice always wins. |

## Access

Pressing `p` opens the navigable **pause menu** (issue #203): `Resume` / `Settings` / `Restart` / `Quit`. `up`/`down` (or `w`/`s`) move the cursor, `enter` or `space` selects. `Resume` unpauses. `Settings` drops into the options sub-page below. `Restart` restarts the run from level 1 with a fresh seed, asking twice first (the row reads `Restart?  enter again`; moving the cursor disarms). `Quit` exits to the shell. `q` in a live run opens this menu on Quit, so a second `q` quits (issue #454). Start menu: ENTER to play, `s` for settings, `q` quit.

On the **Settings** sub-page: `up`/`down` (or `w`/`s`) move the cursor, `left`/`right` (or `a`/`d`) adjust the selected value. WASD is the fallback when arrow codes misfire. Holding ramps sliders. `enter` or `space` (or `p`) backs out to the pause menu. Leaving the pause overlay persists changes.

Control internals: `glue/controls.nav-deltas` converts raw key drain to `{:cursor :value}` steps, `core/settings.navigate` applies them. Settings live on the world as `:settings` / `:settings-cursor`, so `frame-stats` can render them and edits carry across level cuts.

## Platform note

Volume reaches `afplay -v 0..1`, `paplay --volume=0..65536` and `play -v` (issue #459). Only `aplay` has no volume flag. There the sliders persist and the N toggle works, but the level does not change.
