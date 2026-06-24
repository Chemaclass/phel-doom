# Settings

Player options across audio, gameplay defaults, input, accessibility, and performance (the full set is the Fields table below). Persisted to `$HOME/.phel-doom-settings.json` (plain JSON, editable by hand) so choices survive restarts.

## Architecture

- `src/core/settings.phel` (pure): data model. Defaults, `coerce-settings` (clamp/validate), `move-cursor`, `adjust`, volume mappings (`music-volume`, `sfx-scalar`).
- `src/io/settings.phel` (io): `load-settings` / `save-settings!`. Bad files never block startup (returns defaults). Difficulty is stored as string, keyword-ised on load.
- `commands/play.phel`: wires page into start menu + in-game overlay, applies volumes to `io/sound` + `io/music`.

## Fields

| Field | Type | Range | Effect |
|-------|------|-------|--------|
| Music | pct | 0-100 (step 10) | OST `-v` level. 0% stops the soundtrack. 60% = 0.30 (default). Capped at 0.5 so max volume never masks footsteps. |
| SFX | pct | 0-100 (step 10) | Global multiplier on `play-sfx!` events. 0% mutes without affecting N toggle. |
| Minimap | bool | on / off | Default `:show-map` state. Live edits apply immediately. |
| Difficulty | enum | easy / normal / hard / nightmare | Default for next run. CLI `--difficulty` overrides. Baked at level build time. |
| Crosshair | enum | cross / dot / open / off | Idle reticle glyph (`+` / `·` / `○` / hidden). `off` hides the idle reticle; the hit-marker still flashes on a hit. When mouselook is on, `off` still draws a minimal centre dot so the aim point is never lost. |
| Mouse | bool | on / off | FPS-style mouselook (issue #246), **on by default**. Move the mouse to turn + look up/down, left-click to fire. Off omits the xterm mouse-tracking escapes entirely, so a terminal that dislikes pointer capture opts out cleanly. The keyboard path is unchanged either way. See [input.md](input.md#mouse-look-issue-246). |
| Sensitivity | pct | 0-100 (step 10) | Mouselook speed multiplier, geometric around the midpoint (issue #275): `3 ^ ((pct - 50) / 50)`. The midpoint **50% = the neutral 1.0x** (saved-settings back-compat); 0% slows to ~0.33x (1/3) for fine aiming, 100% speeds up to 3.0x for fast flicks. Each end sits the same ratio from neutral, so the slider gives a genuinely useful slow <-> fast range instead of the old narrow 0..2x linear band. Raise for faster turns, lower for fine tracking. The camera turn already tracks pointer speed (a 2x-bigger flick = 2x yaw); this only scales that proportional response. Mapped through `core/settings.mouse-sensitivity`. |
| Run timer | bool | on / off | Append the elapsed run time (`M:SS`) to the row-2 HUD strip. |
| High contrast | bool | on / off | Accessibility. Un-dims the dim/grey HUD elements - compass non-facing letters, empty heart pips, and a healthy ammo-reserve count render bold white instead of SGR-dim/grey so the HUD reads on washed-out or low-quality terminals. |
| Colorblind | enum | none / deuteran / protan / tritan | Accessibility (colour-vision deficiency). The minimap keycard (`k`) and door (`▌`) markers are the only glyphs distinguished by colour alone (blue / red / yellow share a glyph each), so a CVD player can confuse which key opens which door. Non-`none` modes remap that triad to a brightness-plus-hue-separated, CVD-safe set (the same code on a key and its matching door): `deuteran` + `protan` (red-green) use sky-blue / orange / white; `tritan` (blue-yellow) uses blue / red / white. Overlay-only palette swap selected once per frame, so zero hot-3D-path cost. Every other marker already carries a distinct glyph (shape-not-colour). |
| Low detail | bool | on / off | Performance. Paints each wall AND floor cell as one flat colour instead of a two-sample `▀` half-block, trading interior vertical texture detail for render speed: ~11-26% less render time (scaling up with screen size) and ~31-40% fewer bytes per frame. Wall silhouettes and top/bottom edges keep their sub-pixel precision (the seam mixer still runs); sky and sprites are untouched. Off by default, so the shipped look is unchanged (golden frame hashes identical). Aimed at large terminals and slower hardware where the per-cell render loop dominates. The internal setting key stays `:fast-walls` (save-file back-compat). Dev / bench override: `PHEL_DOOM_FLAT_WALLTEX=1` forces it without touching saved settings. |
| Sub-pixel | bool | on / off | Compatibility (#332). **On** (default) draws the `▀` half-block 2-colour cells (full vertical fidelity on floor / walls / sky). **Off** falls back to one solid colour per cell. Turn it OFF on terminals that render `▀` with anti-aliased row seams or inter-line gaps - most notably **macOS Terminal.app** - where the half-block illusion breaks into visible horizontal seams; the flat-cell path renders cleanly there. Off costs vertical fidelity but is faster. See the Terminal.app note in [rendering.md](rendering.md#macos-terminalapp-compatibility). Dev / bench override: `PHEL_DOOM_NO_SUBPIXEL=1` forces it off without touching saved settings. |

## Access

Pressing `p` opens the navigable **pause menu** (issue #203): `Resume` / `Settings` / `Restart` / `Quit`. `up`/`down` (or `w`/`s`) move the cursor; `enter` or `space` selects. `Resume` unpauses, `Settings` drops into the options sub-page below, `Restart` restarts the run from level 1 with a fresh seed, `Quit` exits to the shell. Start menu: ENTER to play, `s` for settings, `q` quit.

On the **Settings** sub-page: `up`/`down` (or `w`/`s`) move cursor, `left`/`right` (or `a`/`d`) adjust the selected value. WASD fallback when arrow codes misfire. Holding ramps sliders. `enter` or `space` (or `p`) backs out to the pause menu; leaving the pause overlay persists changes.

Control internals: `glue/controls.nav-deltas` converts raw key drain to `{:cursor :value}` steps. `core/settings.navigate` applies them. Settings live on world as `:settings` / `:settings-cursor` so `frame-stats` can render and edits carry across level cuts.

## Platform note

Volume control via `afplay -v` (macOS only). Other players (`paplay`, `aplay`, `play`) ignore `-v` - sliders persist and N toggle works, but no audible level change on Linux/BSD.
