# Audio

`src/modules/io/sound.phel`. One-shot SFX via OS shell-out. No FFI, no PHP audio extensions.

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
(play-sfx! :hit)        ; player took damage
(play-sfx! :shoot)      ; trigger pulled, no hit
(play-sfx! :kill)       ; trigger pulled, enemy died
(play-sfx! :wound)      ; trigger pulled, enemy survived (multi-life HP)
(play-sfx! :reload)     ; reload animation started
(play-sfx! :click)      ; trigger pulled on empty mag (dry-fire deny)
(play-sfx! :door)       ; level transition or heart/armor/ammo pickup
(play-sfx! :heartbeat)  ; low-life pulse
```

`macos-sounds` and Linux equivalents map each tag to a file. Current mapping aims for distinct semantic families: `Pop` for shoot + kill (consistent firing family), `Submarine` for wound (muted thunk so it doesn't compete with the floating HP digit), `Sosumi` for player-hurt, `Basso` for empty-click deny, `Funk` for reload, `Tink` for door / pickup, `Bottle` for heartbeat.

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

## Why under `io/`

Calls `exec`, talks to OS. Pure side effect. No tests; would need a fake `php/exec`. Currently integration-tested (run the game, hear sounds).
