# Settings

Player options for audio, gameplay defaults, input, accessibility and rendering. Persisted to `$HOME/.phel-doom-settings.json`: plain JSON, editable by hand.

## Architecture

- `src/core/settings.phel` (pure): the model. `page-fields` is the single table of fields; defaults, coercion, navigation and the page layout all derive from it. Also `coerce-settings`, `navigate` / `move-cursor` / `adjust`, and the value mappings (`music-volume`, `sfx-scalar`, `mouse-sensitivity`, `view-bob-intensity`).
- `src/io/settings.phel` (io): `load-settings` / `save-settings!`. Both iterate `page-fields`, so a new field persists without extra code (a hand-written key list once dropped `:view-bob` and `:light`). The JSON key is the field name; enum fields are stored as the bare name (`"normal"`).
- `src/commands/play.phel`: shows the page from the start menu and the pause menu, and applies volumes to `io/sound` and `io/music`.

Loading never blocks startup. A missing or malformed file yields defaults, and `coerce-settings` clamps percents to 0-100, forces bools and resets unknown enum values to the default. A failed save does not interrupt play: `settings-write-failed?` records it and the game reports it once on exit.

The page groups fields under section headers (Audio, Video, Play, Controls, Access) and shows a one-line hint for the field under the cursor (#468). A test asserts every field has both. On a terminal too short for all eighteen fields, the list scrolls around the cursor.

### Terminal-derived defaults

Two fields pick a default from the terminal when the player has never saved a choice. A saved choice always wins.

- **Sub-pixel** starts off on macOS Terminal.app (`$TERM_PROGRAM` = `Apple_Terminal`), which draws `▀` with row seams (#332). `PHEL_DOOM_SUBPIXEL=1` forces it on.
- **HUD glyphs** starts as `ascii` when `LC_ALL` / `LC_CTYPE` / `LANG` is not UTF-8 (#471).

## Fields

| Field | Key | Type (default) | Effect |
|-------|-----|----------------|--------|
| Music | `:music` | pct (60) | OST volume. `music-volume` maps it to a 0-0.5 playback level (60% = 0.30), so a maxed bed never masks footsteps. 0% stops the soundtrack. |
| SFX | `:sfx` | pct (90) | Multiplier on every `play-sfx!` event. 0% mutes without touching the `N` toggle. |
| Minimap | `:minimap` | bool (off) | Default `:show-map`. A live edit applies at once; restarts honour it. |
| Difficulty | `:difficulty` | enum (normal) | easy / normal / hard / nightmare. Default for the next run; CLI `--difficulty` overrides. Baked in at level build. |
| Crosshair | `:crosshair` | enum (cross) | `+` / `·` / `○` / off. With the mouse on, `off` still draws `·`. The hit marker always flashes. |
| Run timer | `:timer` | bool (off) | Appends elapsed run time (`M:SS`) to the row-2 HUD strip. |
| Mouse | `:mouse` | bool (on) | Mouselook: move to turn and look, click to fire (#246). Off sends no mouse escapes, so the terminal never captures the pointer. See [input.md](input.md#mouse-look-issue-246). |
| Sensitivity | `:sensitivity` | pct (50) | Mouselook multiplier `3 ^ ((pct - 50) / 50)` (#275): 0% = 1/3x, 50% = 1.0x, 100% = 3x. Geometric, so each end is the same ratio from neutral. |
| High contrast | `:high-contrast` | bool (off) | Renders dim HUD elements (compass off-letters, empty heart pips, a healthy reserve count) bold white for washed-out terminals. |
| Colorblind | `:colorblind` | enum (none) | none / deuteran / protan / tritan. Remaps the minimap keycard and door colours, the only glyphs told apart by colour alone. See [rendering.md](rendering.md#minimap-panel). |
| Low detail | `:fast-walls` | bool (off) | One flat sample per wall and floor cell instead of a `▀` half-block: ~11-26% less render time, ~31-40% fewer bytes. For large terminals and slow machines. The key keeps its old name for save compatibility. |
| Sub-pixel | `:subpixel` | bool (on) | `▀` half-block cells with two colours each. Off: one colour per cell, faster, less vertical detail. Turn it off where `▀` shows seams ([rendering.md](rendering.md#macos-terminalapp-compatibility)). |
| Truecolor | `:truecolor` | bool (off) | 24-bit fog cells instead of the xterm-256 cube, so the fade has no banding. Needs a truecolor terminal. |
| Quad detail | `:quad` | bool (off) | 2x2 quadrant glyphs where the four sub-pixels differ: smoother wall silhouettes, more horizontal floor detail. Needs Sub-pixel on. |
| View bob | `:view-bob` | pct (0) | Walk-cycle head bob (#411), off at 0. Distance-driven: `:bob-phase` advances with ground covered and returns to 0 at rest. `view-bob-intensity` maps the percent to [0, 1] and `projection/bob-rows` scales that to a 1-2 row nod. Aim is unaffected: the hit gate uses true pitch. |
| Room light | `:light` | bool (off) | Folds a per-cell room-light bias (#418) into the wall shade, so levels read as dark rooms with lit pools. Looked up once per column; +0.5-2.5% render ([rendering.md](rendering.md#per-column-shade-composition)). |
| HUD glyphs | `:glyphs` | enum (unicode) | unicode / ascii (#471). ascii swaps the keycard, heart, info and bullet glyphs for single-column stand-ins, for fonts that draw them as double-width tofu. |
| Texture filter | `:texmip` | bool (off) | Picks a pre-filtered texture level per wall column (#462), replacing far-wall speckle with an average. |

Every rendering option except Sub-pixel defaults off, and off is byte-identical to the shipped frame. All but Room light and View bob have a `PHEL_DOOM_*` environment override that applies for one run without touching the saved file; the list, scope and costs are in [rendering.md](rendering.md#optional-render-modes).

## Access

**Start menu.** `Enter` or `Space` plays, `s` opens settings, `q` quits. On that settings screen `Esc` goes back and saves.

**Pause menu** (`P`, #203): `Resume` / `Settings` / `Restart` / `Quit`. Up/down or `w`/`s` move the cursor; `Enter` or `Space` selects.

- `Resume` unpauses.
- `Settings` opens the options sub-page.
- `Restart` restarts the run from level 1 with a fresh seed. It asks twice: the row reads `Restart?  enter again`, and moving the cursor disarms it.
- `Quit` exits. `q` in a live run opens this menu with the cursor on Quit, so a second `q` quits (#454).

**Settings sub-page.** Up/down or `w`/`s` move the cursor; left/right or `a`/`d` change the value. WASD is the fallback when arrow codes misfire. Holding a key ramps a slider. `Enter` or `Space` returns to the pause menu; `P` resumes the game directly. Leaving the pause overlay (resume or quit) saves the settings.

Internals: `glue/controls.nav-deltas` turns the drained keys into `{:cursor :value}` steps and `core/settings.navigate` applies them. Settings ride on the world as `:settings` / `:settings-cursor`, so `frame-stats` can render them and edits survive level changes. A quick-load keeps the live settings, not the ones in the save (#279).

## Platform note

Volume reaches `afplay -v 0..1`, `paplay --volume=0..65536` and `play -v`. `aplay` has no volume flag: there the sliders persist and `N` works, but the level does not change.
