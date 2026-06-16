# Audio

One-shot SFX via `src/io/sound.phel` (shell-out) plus a background OST riff via `src/io/music.phel`. No FFI, no PHP extensions.

`audio-player` probes once and memoises: macOS uses `afplay` plus `/System/Library/Sounds/*.aiff`. Linux tries `paplay` / `aplay` / `play` or terminal bell (`\a`) fallback.

## Event tags

Combat enqueues events on the world's per-frame `:sfx` queue via `combat/push-sfx`: `:shoot`, `:shoot-shotgun`, `:shoot-chaingun`, `:shoot-chainsaw`, `:shoot-bfg`, `:shoot-incinerator`, `:shoot-rocket`, `:hit`, `:kill`, `:reload`, `:click`, `:door`, `:heartbeat`, `:berserk`, `:wound`.

A locked-door bump also enqueues a muted `:click` (vol 0.5) as a "denied" cue, on the rising edge only (re-fires at the ~1.5s `NEED <COLOUR> KEY` hint cadence, not every frame). It is enqueued by `physics/try-move` directly (inlined, not via `push-sfx`) to avoid a `core/combat` <-> `core/physics` require cycle - `combat` already requires `physics/try-move`.

This queue keeps `tick-world` pure: no `play-sfx!` calls in-tick. `commands/play` drains it after `tick-world` and emits each event, gated on `:sound-on`. The queue clears at frame start so events never replay. (Level-transition cues like door advance play directly in the outer loop, outside the pure tick.)

Weapon-fire events play baked Freedoom (BSD) DMX reports (see "Weapon fire sounds" below). Everything else falls to the per-OS system map. macOS system map: Pop (pistol/kill), Blow (shotgun), Morse (chaingun), Purr (chainsaw), Glass (BFG), Frog (incinerator), Ping (rocket), Sosumi (player-hurt), Funk (reload), Tink (door/pickup), Submarine (wound), Bottle (heartbeat), Hero (berserk).

## Weapon fire sounds (Freedoom)

Each weapon-fire event prefers a baked Freedoom sound over the system map, so guns read with their real DOOM-style report. `tools/bake-weapon-sounds.phel` extracts the DMX lumps from a Freedoom WAD into `src/io/sound-data` as base64 8-bit-PCM WAVs (license-clean, no binary asset in the repo). `io/sound` decodes each to a temp WAV once (`ensure-sfx-file!`, memoised in `sfx-files`) and afplays it. Lumps: DSPISTOL (pistol + chaingun), DSSHOTGN (shotgun), DSSAWFUL (chainsaw), DSBFG (BFG), DSFIRSHT (incinerator), DSRLAUNC (rocket). All gated by `PHEL_DOOM_SILENT`, so tests never write or play.

## Per-weapon fire report

Every shot plays the weapon's `:fire-sfx` (hit or miss). Report volume attenuates by struck enemy distance: point-blank plays full volume, far drops toward floor (about 0.1), miss plays full volume (no enemy reference). Kill cue (`:kill`) layers on top at same distance volume. Wounds ride the fire report with floating HP and blood, no separate sound. All volumes scale by global SFX scalar (settings page control).

## Async firing and control

Each call shells out backgrounded (`&`). N key toggles `:sound-on`; mute is instant, in-flight SFX finish. `PHEL_DOOM_SILENT=1` env var (set by `composer test`) gates all output for deterministic tests.

## Volume control

Settings page (`docs/settings.md`) drives two levels via `afplay -v` (macOS only; other players ignore `-v`):

- SFX: `set-sfx-scalar!` stores 0..1 multiplier on sound state atom. `play-sfx!` scales every event by it. 0 mutes with no bell fallback. The audio probe (`ensure-probed!`) merges into state (never replaces), so settings never clobber a scalar set before first sound.
- Music: `set-music-volume!` updates the OST `-v` and restarts the loop (immediate). 0 stops the soundtrack.

## Background OST

A driving, dark melodic riff under the run to evoke the original DOOM (`src/io/music.phel`). The original DOOM soundtrack is copyrighted, so this is an ORIGINAL procedural composition: no WAD, no shipped asset, license-clean.

Pure: `riff-wav-bytes` synthesises a 16-bit mono 22050 Hz WAV from a note vector (`doom-riff`, an eighth-note ostinato in E minor). Each note is the fundamental plus a sub-octave and two harmonics, shaped by a fast-attack / exponential-decay / linear-release envelope. The release ramps every slot tail to zero, so note boundaries and the loop wrap are click-free (seamless). Written once to `sys_get_temp_dir()/phel-doom-music.wav`, reused.

Rides the Music volume slider (`apply-audio-settings!` drives `music/set-music-volume!`). Lifecycle from `commands/play`: `start-music!` after menu, `sync-music!` on N toggle, `stop-music!` on teardown. The shell watches the game PID and self-terminates if the game crashes (no orphan loop). All entry points no-op under `PHEL_DOOM_SILENT` or when no audio player is found.
