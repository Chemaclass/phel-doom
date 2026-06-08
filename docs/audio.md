# Audio

One-shot SFX via `src/io/sound.phel` (shell-out), ambient drone via `src/io/ambient.phel`, and a background OST riff via `src/io/music.phel`. No FFI, no PHP extensions.

`audio-player` probes once and memoises: macOS uses `afplay` plus `/System/Library/Sounds/*.aiff`. Linux tries `paplay` / `aplay` / `play` or terminal bell (`\a`) fallback.

## Event tags

Combat enqueues events on the world's per-frame `:sfx` queue via `combat/push-sfx`: `:shoot`, `:shoot-shotgun`, `:shoot-chaingun`, `:shoot-chainsaw`, `:shoot-bfg`, `:shoot-incinerator`, `:shoot-rocket`, `:shoot-super-shotgun`, `:hit`, `:kill`, `:reload`, `:click`, `:door`, `:heartbeat`, `:berserk`, `:wound`.

This queue keeps `tick-world` pure: no `play-sfx!` calls in-tick. `commands/play` drains it after `tick-world` and emits each event, gated on `:sound-on`. The queue clears at frame start so events never replay. (Level-transition cues like door advance play directly in the outer loop, outside the pure tick.)

macOS sound map: Pop (pistol/kill), Blow (shotgun), Morse (chaingun), Purr (chainsaw), Glass (BFG), Frog (incinerator), Ping (rocket), Basso (super shotgun), Sosumi (player-hurt), Funk (reload), Tink (door/pickup), Submarine (wound), Bottle (heartbeat), Hero (berserk).

## Per-weapon fire report

Every shot plays the weapon's `:fire-sfx` (hit or miss). Report volume attenuates by struck enemy distance: point-blank plays full volume, far drops toward floor (about 0.1), miss plays full volume (no enemy reference). Kill cue (`:kill`) layers on top at same distance volume. Wounds ride the fire report with floating HP and blood, no separate sound. All volumes scale by global SFX scalar (settings page control).

## Async firing and control

Each call shells out backgrounded (`&`). N key toggles `:sound-on`; mute is instant, in-flight SFX finish. `PHEL_DOOM_SILENT=1` env var (set by `composer test`) gates all output for deterministic tests.

## Volume control

Settings page (`docs/settings.md`) drives two levels via `afplay -v` (macOS only; other players ignore `-v`):

- SFX: `set-sfx-scalar!` stores 0..1 multiplier on sound state atom. `play-sfx!` scales every event by it. 0 mutes with no bell fallback. The audio probe (`ensure-probed!`) merges into state (never replaces), so settings never clobber a scalar set before first sound.
- Music: `set-music-volume!` updates drone `-v` and restarts loop (immediate). 0 stops bed.

## Ambient drone

Low pulsing background for dread (no shipped asset).

Pure: `drone-wav-bytes` synthesises seamless 2s 16-bit mono 22050 Hz clip. Three partials (55/82/110 Hz, integer cycles no click) under 0.5 Hz tremolo. Written once to `sys_get_temp_dir()/phel-doom-ambient.wav`, reused.

Lifecycle from `commands/play`: `start-ambient!` after menu, `sync-ambient!` on N toggle, `stop-ambient!` on teardown. Shell watches game PID and self-terminates if game crashes (no orphan loop). All entry points no-op under `PHEL_DOOM_SILENT` or when no audio player found.

## Background OST

A driving, dark melodic riff under the run to evoke the original DOOM (`src/io/music.phel`). The original DOOM soundtrack is copyrighted, so this is an ORIGINAL procedural composition: no WAD, no shipped asset, license-clean.

Pure: `riff-wav-bytes` synthesises a 16-bit mono 22050 Hz WAV from a note vector (`doom-riff`, an eighth-note ostinato in E minor). Each note is the fundamental plus a sub-octave and two harmonics, shaped by a fast-attack / exponential-decay / linear-release envelope. The release ramps every slot tail to zero, so note boundaries and the loop wrap are click-free (seamless). Written once to `sys_get_temp_dir()/phel-doom-music.wav`, reused.

Plays on top of the ambient drone: drone is the sub-bass bed, music is the tune. Both ride the Music volume slider (`apply-audio-settings!` drives `ambient/set-music-volume!` and `music/set-music-volume!` together). Lifecycle mirrors the drone: `start-music!` after menu, `sync-music!` on N toggle, `stop-music!` on teardown. Same PID-guarded backgrounded loop, same `PHEL_DOOM_SILENT` / no-player no-ops.
