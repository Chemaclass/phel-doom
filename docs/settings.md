# Settings

Player-configurable options: bg-music volume, sfx volume, the default minimap state, and the default difficulty. Persisted to `$HOME/.phel-doom-settings.json` (plain JSON, inspect or wipe by hand) so choices survive restarts.

## Layers

- `src/core/settings.phel` (pure): the data model. Defaults, `coerce-settings` (clamp + validate loaded values), cursor movement (`move-cursor`), value adjustment (`adjust`), and the percent -> playback-scalar mappings (`music-volume`, `sfx-scalar`).
- `src/io/settings.phel` (io): `load-settings` / `save-settings!`. Mirrors `io/scores`: load + save errors are swallowed so a bad file never blocks the game. Difficulty is stored as a bare string and keyword-ised on the way in.
- `commands/play.phel`: wires the page into the start menu + the in-game overlay and applies the volumes to `io/sound` + `io/ambient`.

## Fields

| Field | Kind | Values | Effect |
|-------|------|--------|--------|
| Music | volume | 0..100% (step 10) | Drone `afplay -v` level. 0% stops the bed. 60% = 0.30, the historical default. |
| SFX | volume | 0..100% (step 10) | Global multiplier on every `play-sfx!` event volume. 0% mutes sfx without touching the N toggle. |
| Minimap | toggle | on / off | Default `:show-map` at run start; editing it live updates the current frame. |
| Difficulty | enum | easy / normal / hard / nightmare | Default for the run. `--difficulty` on the CLI overrides it. |

Volumes map through `core/settings`: `music-volume` = `(pct / 100) * music-ceiling` (ceiling 0.5 so a maxed bed never masks footsteps); `sfx-scalar` = `pct / 100`.

## Reaching the page

The settings page IS the pause screen, so there is only one overlay layer to learn (the `h` info panel stays a separate read-only reference).

- In game: press `p` (pause). The game freezes and the options appear; `p` resumes.
- Start menu: press `s` to open the settings screen, edit, then `esc` to return.

Navigation: `up` / `down` move the cursor, `left` / `right` adjust the selected field. Volume + minimap edits take effect immediately; difficulty applies from the next run (it is baked per level at build time). Resuming (`p`, or `esc` on the start-menu screen) persists the file.

The settings map rides on the world (`:settings` / `:settings-cursor`) so `frame-stats` can paint it and edits carry across level cuts. The render layer keys the overlay off `:paused`.

## Platform note

Volume control rides on `afplay -v`, which is macOS-only. `paplay` / `aplay` / `play` ignore `-v`, so on other hosts the sliders still persist and the N sound toggle still works, but moving a volume slider does not change the audible level.
