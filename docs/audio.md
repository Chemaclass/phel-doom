# Audio

One-shot SFX via `src/io/sound.phel` (shell-out), plus a background OST riff via `src/io/music.phel`. No FFI, no PHP extensions.

`audio-player` probes once and memoises. macOS uses `afplay` plus `/System/Library/Sounds/*.aiff`. Linux tries `paplay` / `aplay` / `play`, falling back to the terminal bell (`\a`). Volume reaches every backend now: `afplay -v 0..1`, `paplay --volume=0..65536`, `play -v` (issue #459), so the SFX and Music sliders are no longer macOS-only.

## Baked Freedoom sounds (issue #460)

`tools/bake-weapon-sounds.phel` generates `src/io/sound_data.phel` from the Freedoom IWADs (BSD). Each DMX lump becomes an 8-bit mono WAV, base64'd, written to a temp file on first use and played from there. It covers 36 events: the weapon reports, per-type monster wake and death cries, the fireball launch, the melee claw, monster pain, the player's own grunt, and the world cues (item, weapon, powerup, door, refused door, switch).

Before that only the seven weapon reports were baked. Every other event fell through to the per-OS system sounds, which exist only on macOS. On Linux and BSD a hit, a kill, a pickup, a reload and a door were all the terminal BELL. No monster made a sound at all: nothing announced a wake, a launched fireball or a death.

Freedoom splits its bestiary across the two IWADs, so the tool takes both and falls back to the second for a lump the first lacks (revenant, archvile and mancubus live in `freedoom2.wad`):

```sh
vendor/bin/phel run tools/bake-weapon-sounds.phel /path/freedoom1.wad /path/freedoom2.wad
```

It prints a line for any event whose lump is in neither, instead of dropping it silently. Cost of the extra 29 sounds: `sound_data.phel` 190 KB -> 1.3 MB, phar 3.47 MB -> 4.08 MB, cold start unchanged (0.16s, the namespace is not on the startup path).


## The sfx sidecar (issue #459)

Every sound effect used to be `php/exec "player file &"` on the game thread: a shell fork+exec at **3.30 ms per event** on the reference machine. The chaingun fires every 0.05s, 20 events a second inside an 8.3ms frame budget, and a kill frame layers report + kill + wound: three forks could blow the frame alone. None of it showed in F3's cast/render split, so it read as mystery jitter.

`io/sound` now starts one long-lived `sh` on the first audible event and writes it a command line per sound: **0.0012 ms per event**, a plain buffered write. The sidecar reads a line at a time, so it costs nothing between events. It backgrounds each player, so a long sound cannot delay the next, and guards on `kill -0 <game-pid>` like the music loop, so a SIGKILLed game leaves no orphan playing into an empty terminal. Teardown closes the pipe, ending it via EOF.

The pipe is non-blocking: a full pipe must never stall a frame. Losing a sound is an acceptable trade. Sfx are disposable, a stuttered frame is not.

A torn write would be worse than a lost one: the next event appends to the fragment, splicing two commands into one instead of dropping a sound. POSIX pipe atomicity rules that out. A non-blocking write at or below `PIPE_BUF` (512 bytes on macOS, 4096 on Linux) lands whole or fails with EAGAIN, and these lines are 60-90 bytes. The explicit terminator after a short write is belt-and-braces for a pathological path length, not the primary safety.

The sidecar's stdout and stderr go to `/dev/null`, so a shell-level error can never print into the alternate screen mid-frame. A write is skipped when `proc_get_status` says the shell is gone: Ctrl-C reaches the whole foreground process group, so the sidecar can die while the game finishes its frame, and a write to a dead pipe would print "Broken pipe" over the ANSI screen once per event. A failed start is remembered, not retried: retrying per event is exactly the cost this removes. Hosts without `proc_open` fall back to the old per-event exec. A silent session (tests, `PHEL_DOOM_SILENT`, muted settings) starts no sidecar at all.

## Event tags

Combat enqueues events on the world's per-frame `:sfx` queue via `combat/push-sfx`: `:shoot`, `:shoot-shotgun`, `:shoot-chaingun`, `:shoot-chainsaw`, `:shoot-bfg`, `:shoot-incinerator`, `:shoot-rocket`, `:hit`, `:kill`, `:reload`, `:click`, `:door`, `:heartbeat`, `:berserk`, `:wound`.

A locked-door bump also enqueues a muted `:click` (vol 0.5) as a "denied" cue, on the rising edge only (it re-fires at the ~1.5s `NEED <COLOUR> KEY` hint cadence, not every frame). `physics/try-move` enqueues it directly (inlined, not via `push-sfx`) to avoid a `core/combat` <-> `core/physics` require cycle: `combat` already requires `physics/try-move`.

This queue keeps `tick-world` pure: no `play-sfx!` calls in-tick. `commands/play` drains it after `tick-world` and emits each event, gated on `:sound-on`. The queue clears at frame start, so events never replay. (Level-transition cues like door advance play directly in the outer loop, outside the pure tick.)

Weapon-fire events play baked Freedoom (BSD) DMX reports (see "Weapon fire sounds" below). Everything else falls to the per-OS system map. macOS system map: Pop (pistol/kill), Blow (shotgun), Morse (chaingun), Purr (chainsaw), Glass (BFG), Frog (incinerator), Ping (rocket), Sosumi (player-hurt), Funk (reload), Tink (door/pickup), Submarine (wound), Bottle (heartbeat), Hero (berserk).

## Weapon fire sounds (Freedoom)

Each weapon-fire event prefers a baked Freedoom sound over the system map, so guns read with their real DOOM-style report. `tools/bake-weapon-sounds.phel` extracts the DMX lumps from a Freedoom WAD into `src/io/sound_data.phel` as base64 8-bit-PCM WAVs (license-clean, no binary asset in the repo). `io/sound` decodes each to a temp WAV once (`ensure-sfx-file!`, memoised in `sfx-files`), then afplays it. Lumps: DSPISTOL (pistol + chaingun), DSSHOTGN (shotgun), DSSAWFUL (chainsaw), DSBFG (BFG), DSFIRSHT (incinerator), DSRLAUNC (rocket). All gated by `PHEL_DOOM_SILENT`, so tests never write or play.

## Per-weapon fire report

Every shot plays the weapon's `:fire-sfx`, hit or miss. Report volume attenuates by the collision-target distance: point-blank is full volume, far drops toward the floor (about 0.1). The target is the struck enemy on a hit, the wall the shot collides with on a miss (`cast-wall-dist`). So a near wall reads loud, a far wall or an open level quiet: the report tells you how close the thing you hit is. Kill cue (`:kill`) layers on top at the same distance volume. Wounds ride the fire report with floating HP and blood, no separate sound. All volumes scale by the global SFX scalar (settings page control).

## Async firing and control

Each call shells out backgrounded (`&`). The N key toggles `:sound-on`: mute is instant, in-flight SFX finish. The `PHEL_DOOM_SILENT=1` env var (set by `composer test`) gates all output for deterministic tests.

## Volume control

Settings page (`docs/settings.md`) drives two levels. `afplay`, `paplay` and `play` each take a volume flag (issue #459). Only `aplay` has none:

- SFX: `set-sfx-scalar!` stores a 0..1 multiplier on the sound state atom. `play-sfx!` scales every event by it. 0 mutes with no bell fallback. The audio probe (`ensure-probed!`) merges into state, never replaces it, so settings never clobber a scalar set before the first sound.
- Music: `set-music-volume!` updates the OST `-v` and restarts the loop (immediate). 0 stops the soundtrack.

## Background OST

A driving, dark melodic riff under the run, to evoke the original DOOM (`src/io/music.phel`). The DOOM soundtrack is copyrighted, so this is an ORIGINAL procedural composition: no WAD, no shipped asset, license-clean.

Pure: `riff-wav-bytes` synthesises a 16-bit mono 22050 Hz WAV from a note vector (`doom-riff`, an eighth-note ostinato in E minor). Each note is the fundamental plus a sub-octave and two harmonics, shaped by a fast-attack / exponential-decay / linear-release envelope. The release ramps every slot tail to zero, so note boundaries and the loop wrap are click-free (seamless). Written once to `sys_get_temp_dir()/phel-doom-music.wav`, then reused.

Rides the Music volume slider (`apply-audio-settings!` drives `music/set-music-volume!`). Lifecycle from `commands/play`: `start-music!` after menu, `sync-music!` on N toggle, `stop-music!` on teardown. The shell watches the game PID and self-terminates on a crash (no orphan loop). Every entry point no-ops under `PHEL_DOOM_SILENT`, or when no audio player is found.
