# Settings

Player options: music volume, SFX volume, minimap default, difficulty default. Persisted to `$HOME/.phel-doom-settings.json` (plain JSON, editable by hand) so choices survive restarts.

## Architecture

- `src/core/settings.phel` (pure): data model. Defaults, `coerce-settings` (clamp/validate), `move-cursor`, `adjust`, volume mappings (`music-volume`, `sfx-scalar`).
- `src/io/settings.phel` (io): `load-settings` / `save-settings!`. Bad files never block startup (returns defaults). Difficulty is stored as string, keyword-ised on load.
- `commands/play.phel`: wires page into start menu + in-game overlay, applies volumes to `io/sound` + `io/ambient`.

## Fields

| Field | Type | Range | Effect |
|-------|------|-------|--------|
| Music | pct | 0-100 (step 10) | Drone `-v` level. 0% stops bed. 60% = 0.30 (default). Capped at 0.5 so max volume never masks footsteps. |
| SFX | pct | 0-100 (step 10) | Global multiplier on `play-sfx!` events. 0% mutes without affecting N toggle. |
| Minimap | bool | on / off | Default `:show-map` state. Live edits apply immediately. |
| Difficulty | enum | easy / normal / hard / nightmare | Default for next run. CLI `--difficulty` overrides. Baked at level build time. |

## Access

The pause screen (`p`) IS the settings page. Start menu: ENTER to play, `s` for settings, `q` quit.

Navigation: `up`/`down` (or `w`/`s`) move cursor. `left`/`right` (or `a`/`d`) adjust value. WASD fallback when arrow codes misfire. Holding ramps sliders. Resume with `p` or `esc` persists changes.

Control internals: `glue/controls.nav-deltas` converts raw key drain to `{:cursor :value}` steps. `core/settings.navigate` applies them. Settings live on world as `:settings` / `:settings-cursor` so `frame-stats` can render and edits carry across level cuts.

## Platform note

Volume control via `afplay -v` (macOS only). Other players (`paplay`, `aplay`, `play`) ignore `-v` - sliders persist and N toggle works, but no audible level change on Linux/BSD.
