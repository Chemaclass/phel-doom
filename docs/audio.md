# Audio

`src/modules/io/sound.phel`. Plays one-shot sound effects via OS
shell-out — no FFI, no PHP audio extensions.

## Why shell-out

PHP has no portable in-process audio. The path of least dependency
is to call the system's `afplay` / `paplay` / `aplay` binary
asynchronously with a short WAV/AIFF file. Falls back to a terminal
bell (`\a`) if no audio binary is found.

## Detection

`sound-player` runs once at load time, picking whichever binary is
available on the host:

| OS | Binary | Sound files |
|---|---|---|
| macOS | `afplay` | `/System/Library/Sounds/*.aiff` (Tink, Pop, etc.) |
| Linux | `paplay` (PulseAudio) | `/usr/share/sounds/freedesktop/stereo/*.oga` |
| Linux | `aplay` (ALSA) | `/usr/share/sounds/alsa/*.wav` |
| any  | `play` (sox) | Same as above |
| none | none | falls back to `\a` (terminal bell) |

The lookup walks the candidate list in that order and picks the
first one in `$PATH`.

## Event tags

Combat and other modules raise events by name, not by file:

```phel
(play-sfx! :hit)     ; player took damage
(play-sfx! :shoot)   ; trigger pulled, no hit
(play-sfx! :kill)    ; trigger pulled, enemy killed
(play-sfx! :door)    ; level transition or heart pickup
```

`macos-sounds` and the linux equivalents map each tag to a file on
disk. Picking different files per tag gives players audio cues that
read as distinct events ("Pop" for shoot, "Hero" for kill, "Sosumi"
for hit, "Tink" for door).

## Async firing

Each call shells out non-blocking:

```bash
afplay /System/Library/Sounds/Pop.aiff &
```

The `&` is critical: without it, the game would block until the
sound finishes playing. ~30ms is small but per-frame it adds up
and makes the loop choppy.

`php/exec` runs synchronously so the codebase wraps the command in
shell `( ... & ) >/dev/null 2>&1` so PHP returns immediately and
the audio binary runs in its own process.

## Gating by `:sound-on`

Every call site checks the world flag before invoking:

```phel
(when (:sound-on world) (play-sfx! :hit))
```

The N key toggles `:sound-on`. Mute is instant; in-flight sfx
finish on their own.

## Why under `io/`

Calls `exec`, talks to the OS. Pure side effect. No tests — would
need a fake `php/exec` to verify. Currently relied on integration
testing (run the game, hear the sounds).
