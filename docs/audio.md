# Audio

One-shot SFX via `src/io/sound.phel` (shell-out) + ambient drone via `src/io/ambient.phel`. No FFI, no PHP extensions.

`audio-player` probes once and memoises: macOS uses `afplay` + `/System/Library/Sounds/*.aiff`. Linux tries `paplay` / `aplay` / `play` or terminal bell (`\a`) fallback.

## Event tags

Combat raises events by name: `:shoot`, `:shoot-shotgun`, `:shoot-chaingun`, `:shoot-chainsaw`, `:shoot-bfg`, `:hit`, `:kill`, `:reload`, `:click`, `:door`, `:heartbeat`, `:berserk`, `:wound`.

`core/combat` is pure: it enqueues `{:name :vol}` events on the world's per-frame `:sfx` queue rather than calling `play-sfx!`. `commands/play` drains the queue after `tick-world` and emits each event, gated on `:sound-on`. Keeps the effect at the io boundary.

macOS maps to `.aiff`: Pop (pistol/kill), Blow (shotgun), Morse (chaingun), Purr (chainsaw), Glass (BFG), Sosumi (player-hurt), Basso (dry-fire), Funk (reload), Tink (door/pickup), Submarine (wound), Bottle (heartbeat), Hero (berserk).

## Per-weapon fire report

Every shot plays the weapon's `:fire-sfx` unconditionally (hit or miss). Kill cue (`:kill`) layers on top, distance-attenuated. Wounds ride on fire report + floating HP digit + blood, no separate sound.

## Async firing + control

Each call shells out backgrounded (`&`). N key toggles `:sound-on`; mute is instant, in-flight sfx finish. `PHEL_DOOM_SILENT=1` env var (set by `composer test`) gates all output (deterministic suite).

## Volume

The settings page (see `docs/settings.md`) drives two levels via `afplay -v` (macOS only; other players ignore `-v`):

- SFX: `set-sfx-scalar!` stores a 0..1 multiplier on the sound state atom; `play-sfx!` scales every event volume by it. 0 mutes sfx with no bell fallback.
- Music: `set-music-volume!` updates the drone `-v` and restarts the loop so the change is immediate. 0 stops the bed.

## Ambient drone

Low pulsing background loop for dread (no shipped asset).

Pure: `drone-wav-bytes` synthesises seamless 2s 16-bit mono 22050 Hz clip. Three low partials (55/82/110 Hz, integer cycles so no click) under 0.5 Hz tremolo. Written once to `sys_get_temp_dir()/phel-doom-ambient.wav` and reused.

Lifecycle from `commands/play`: `start-ambient!` after menu -> `sync-ambient!` on N toggle -> `stop-ambient!` on teardown.

Safety net: shell watches game PID, self-terminates if game crashes (no orphan loop). All entry points no-op under `PHEL_DOOM_SILENT` or no audio player.
