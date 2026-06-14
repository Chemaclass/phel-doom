# Settings

Player options: music volume, SFX volume, minimap default, difficulty default. Persisted to `$HOME/.phel-doom-settings.json` (plain JSON, editable by hand) so choices survive restarts.

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
| Crosshair | enum | cross / dot / open / off | Idle reticle glyph (`+` / `·` / `○` / hidden). `off` hides the idle reticle; the hit-marker still flashes on a hit. |
| Run timer | bool | on / off | Append the elapsed run time (`M:SS`) to the row-2 HUD strip. |
| High contrast | bool | on / off | Accessibility. Un-dims the dim/grey HUD elements - compass non-facing letters, empty heart pips, and a healthy ammo-reserve count render bold white instead of SGR-dim/grey so the HUD reads on washed-out or low-quality terminals. |
| Reduced motion | bool | on / off | Accessibility / photosensitivity. When on, gates the strobing horror beats: lights-flicker scanlines dropped; heartbeat edge, berserk border, pulsing HUD labels (low-ammo / behind-you) and powerup banners hold steady; jump-scare face flash suppressed; the door-eye drops its SGR-5 terminal hardware blink. Essential single-shot feedback (directional hit-vignette, kill flash) is kept. `PHEL_DOOM_REDUCED_MOTION=1` forces it on regardless of the saved value. |

## Access

The pause screen (`p`) IS the settings page. Start menu: ENTER to play, `s` for settings, `q` quit.

Navigation: `up`/`down` (or `w`/`s`) move cursor. `left`/`right` (or `a`/`d`) adjust value. WASD fallback when arrow codes misfire. Holding ramps sliders. Resume with `p` or `esc` persists changes.

Control internals: `glue/controls.nav-deltas` converts raw key drain to `{:cursor :value}` steps. `core/settings.navigate` applies them. Settings live on world as `:settings` / `:settings-cursor` so `frame-stats` can render and edits carry across level cuts.

## Platform note

Volume control via `afplay -v` (macOS only). Other players (`paplay`, `aplay`, `play`) ignore `-v` - sliders persist and N toggle works, but no audible level change on Linux/BSD.
