# Audio

`src/io/sound.phel`. One-shot SFX via OS shell-out. No FFI, no PHP audio extensions.

## Why shell-out

PHP has no portable in-process audio. Lowest-dependency path: call `afplay` / `paplay` / `aplay` asynchronously with a short WAV/AIFF. Falls back to terminal bell (`\a`) when no audio binary is found.

## Detection

`sound-player` runs once at load, picks first available binary:

| OS | Binary | Sound files |
|---|---|---|
| macOS | `afplay` | `/System/Library/Sounds/*.aiff` (Tink, Pop, etc.) |
| Linux | `paplay` (PulseAudio) | `/usr/share/sounds/freedesktop/stereo/*.oga` |
| Linux | `aplay` (ALSA) | `/usr/share/sounds/alsa/*.wav` |
| any  | `play` (sox) | Same as above |
| none | none | falls back to `\a` (terminal bell) |

## Event tags

Combat and other modules raise events by name, not by file:

```phel
(play-sfx! :hit)             ; player took damage
(play-sfx! :shoot)           ; pistol fire (default fire report)
(play-sfx! :shoot-shotgun)   ; shotgun fire
(play-sfx! :shoot-chaingun)  ; chaingun fire
(play-sfx! :shoot-chainsaw)  ; chainsaw rev
(play-sfx! :kill)            ; killing blow (layered over the fire report)
(play-sfx! :reload)          ; reload animation started
(play-sfx! :click)           ; trigger pulled on empty mag (dry-fire deny)
(play-sfx! :door)            ; level transition or heart/armor/ammo pickup
(play-sfx! :heartbeat)       ; low-life pulse
(play-sfx! :berserk)         ; rage sphere picked up
```

`macos-sounds` and Linux equivalents map each tag to a file: `Pop` for pistol-fire + kill, `Blow` for shotgun, `Morse` for chaingun, `Purr` for chainsaw, `Sosumi` for player-hurt, `Basso` for empty-click deny, `Funk` for reload, `Tink` for door / pickup, `Bottle` for heartbeat, `Hero` for berserk.

## Per-weapon fire report

Every trigger pull plays the ACTIVE weapon's own fire sound, hit or miss. The event comes from the weapon spec's `:fire-sfx` (weapons.phel), so combat is data-driven: `(play-sfx! (or (:fire-sfx (w-spec world)) :shoot) 1.0)`. On a kill the `:kill` cue is layered on top (distance-attenuated); wounds ride on the fire report plus the floating HP digit + blood, with no separate sound.

Previously a shot that connected swapped the gun sound for the enemy reaction, so a weapon felt silent when you actually hit something (the shotgun especially). Playing the fire report unconditionally fixes that and gives each weapon a distinct voice.

## Async firing

Each call shells out non-blocking:

```bash
afplay /System/Library/Sounds/Pop.aiff &
```

`&` is critical: without it the game blocks until the sound finishes (~30ms, choppy per frame). `php/exec` runs synchronously, so the codebase wraps with `( ... & ) >/dev/null 2>&1`. PHP returns immediately; audio binary runs in its own process.

## Gating by `:sound-on`

```phel
(when (:sound-on world) (play-sfx! :hit))
```

N key toggles `:sound-on`. Mute is instant; in-flight sfx finish on their own.

## Test gate

`composer test` exports `PHEL_DOOM_SILENT=1`; `play-sfx!` short-circuits when the env var is `"1"`. `tests/io/sound-test.phel` asserts the gate is on during the suite so it can't silently regress.

## Distance attenuation

`distance-volume` scales `:wound` / `:kill` sfx by distance to the hit so crowded fights don't drown the channel.

## Ambient drone loop

`src/io/ambient.phel`. A low, slow-pulsing background drone runs under the whole gameplay session for dread.

No asset is shipped. `drone-wav-bytes` synthesises a seamless `loop-seconds` (2s) clip of 16-bit mono PCM at 22050 Hz: three low partials (55 / 82 / 110 Hz, all integer cycles in the window so the loop has no click) under a 0.5 Hz tremolo, scaled to a quiet `gain`. It's a pure function (same args -> same bytes), unit-tested in `tests/io/ambient-test.phel`. The bytes are written once to `sys_get_temp_dir()/phel-doom-ambient.wav` and reused.

`start-ambient!` backgrounds a shell that re-plays the clip forever:

```bash
sh -c 'while kill -0 <game-pid> 2>/dev/null; do afplay -v 0.30 <wav> >/dev/null 2>&1; done' & echo $!
```

The `kill -0 <game-pid>` guard is the orphan safety net: if the game crashes or is SIGKILLed without a clean stop, the loop self-terminates within one clip instead of looping forever. `echo $!` returns the shell PID, tracked in the `proc` atom.

`stop-ambient!` kills the loop shell first (so no new clip spawns) then `pkill -f`s the temp path (matches only the drone, never the per-event sfx playing system sounds).

Lifecycle is driven from `commands/play`:

- `start-ambient!` when gameplay begins (after the start menu).
- `sync-ambient!` on the N (sound) toggle, comparing `:sound-on` across the frame.
- `stop-ambient!` on every teardown path.

All entry points are no-ops under `PHEL_DOOM_SILENT` and on hosts with no audio player (no bell fallback - a once-a-clip bell would be worse than silence).

## Why under `io/`

Calls `exec`, talks to OS. Pure side effect. Integration-tested by running the game. (The drone synthesis is pure and unit-tested; only the loop process is IO.)
