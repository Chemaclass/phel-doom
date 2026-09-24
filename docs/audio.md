# Audio

One-shot sound effects via `src/io/sound.phel`, plus a background soundtrack via `src/io/music.phel`. Both shell out to a system audio player. No FFI, no PHP extensions.

## Players and fallbacks

`audio-player` probes `PATH` once and memoises the first of `afplay`, `paplay`, `aplay`, `play`. The OST reuses the same probe.

Each event plays, in order of preference:

1. A baked Freedoom sound, if the event has one.
2. A macOS system sound from `/System/Library/Sounds/*.aiff` (`macos-sounds`), on macOS only.
3. The terminal bell (`\a`). `:heartbeat` skips the bell so a low-health player is not beeped every second.

SFX volume reaches `afplay -v 0..1`, `paplay --volume=0..65536` and `play -v` (issue #459). `aplay` has no volume flag.

## Baked Freedoom sounds (issue #460)

`tools/bake-weapon-sounds.phel` extracts DMX lumps from the Freedoom IWADs (BSD) into `src/io/sound_data.phel` as base64 8-bit mono WAVs. No binary asset lives in the repo. At runtime `ensure-sfx-file!` decodes each to a temp WAV once (memoised in `sfx-files`) and plays it from there.

The map (`freedoom-sfx`) covers 36 events: the seven weapon reports, per-type monster sight and death cries, the fireball launch, the melee claw, monster pain, the player's grunt, and the world cues (item, weapon, powerup, door, locked door, switch).

Freedoom splits its bestiary across two IWADs. The tool falls back to the second for a lump the first lacks (revenant, archvile and mancubus live in `freedoom2.wad`), and prints any event found in neither:

```sh
vendor/bin/phel run tools/bake-weapon-sounds.phel /path/freedoom1.wad /path/freedoom2.wad
```

Cost of the full set: `sound_data.phel` 190 KB → 1.3 MB, phar 3.47 MB → 4.08 MB, cold start unchanged (the namespace is not on the startup path).

## The sfx sidecar (issue #459)

A per-event `php/exec "player file &"` costs a fork+exec on the game thread (~3-4 ms). The chaingun fires 20 times a second inside an 8.3 ms frame budget, and the cost never shows in F3's cast/render split. So `io/sound` starts one long-lived `sh` on the first audible event and writes it one command line per sound (~0.001 ms). The sidecar:

- reads a line at a time, so it costs nothing between events;
- backgrounds each player, so a long sound cannot delay the next;
- guards on `kill -0 <game-pid>`, so a killed game leaves no orphan playing;
- exits on EOF when teardown (`stop-sfx!`) closes the pipe;
- sends its stdout and stderr to `/dev/null`, so a shell error never prints into the game screen.

Write rules:

- **Non-blocking.** A full pipe drops the sound instead of stalling the frame.
- **No torn lines.** Lines are 60-90 bytes, below `PIPE_BUF` (512 on macOS, 4096 on Linux), so a write lands whole or fails. A short write still gets a newline as a backstop.
- **Skip dead pipes.** Ctrl-C can kill the sidecar mid-frame. Writes are skipped once `proc_get_status` says it is gone, else "Broken pipe" prints over the screen.
- **No retries.** A failed start is remembered. Hosts without `proc_open` fall back to the per-event exec.

A silent session (tests, `PHEL_DOOM_SILENT`, muted settings) starts no sidecar.

## Event queue

Core code never plays sound. It enqueues `{:name :vol}` on the world's per-frame `:sfx` queue via `combat/push-sfx`. `tick-world` clears the queue at frame start, so events never replay. After the tick, `commands/play` plays each queued event, gated on `:sound-on`. The heartbeat and the door-advance cue play directly from the outer loop.

Sources:

- **Combat**: the weapon's `:fire-sfx` on every shot, `:kill` plus a per-type death cry on a kill (the cry at `death-cry-gain` 0.4 of the kill volume: the Freedoom screams are mastered much hotter), `:click` on dry fire, `:reload`, `:player-pain`. A monster's melee hit adds `:claw`. A shot that staggers a monster adds its pain cry (`pain-sfx-for`): `:enemy-pain` for imps and revenants, `:enemy-pain-heavy` for the demon family. Only the single-target weapons roll pain, so only they make monsters cry out.
- **Enemies**: a per-type sight cry on wake, `:fireball` on launch.
- **Pickups and world**: `:item`, `:weapon-up`, `:powerup`, `:door` (also secret reveal), `:switch`.
- **Locked door**: `:locked` at volume 0.5, on the rising edge only, so holding into the door re-fires at the ~1.5s hint cadence. `physics/try-move` enqueues it inline instead of calling `push-sfx`, which would create a `core/combat` <-> `core/physics` require cycle.

The two maps in `src/io/sound_data.phel` and `src/io/sound.phel` are the full event list.

## Fire report volume

Every shot plays its report, hit or miss, attenuated by the distance to what it struck: the enemy on a hit, the wall on a miss (`cast-wall-dist`). Point-blank is full volume, far drops toward ~0.1. A near wall reads loud, an open level quiet. The kill cue layers on top at the same volume.

## Volume and mute

The settings page ([settings.md](settings.md)) drives two levels:

- **SFX**: `set-sfx-scalar!` stores a 0..1 multiplier that `play-sfx!` applies to every event. 0 mutes with no bell fallback. The first audio probe merges into the sound state instead of replacing it, so a scalar set before the first sound survives.
- **Music**: `set-music-volume!` restarts the loop at the new level. 0 stops the soundtrack. Only `afplay` takes a music volume; other players ignore it.

The N key toggles `:sound-on`: mute is instant, in-flight sounds finish, and the OST starts or stops (`sync-music!`). `PHEL_DOOM_SILENT=1` (set by `composer test`) gates all output. `io/sound` also mutes itself when running under `phel test`.

## Background OST

An original procedural riff in E minor, evoking DOOM without its copyrighted soundtrack (`src/io/music.phel`, issue #158). No WAD, no shipped asset.

- `doom-riff` is an eighth-note ostinato. `variant-riff` sprinkles random 3rd/5th/octave stabs over the root hits. `session-riff` chains 8 such sections into one track, seeded off the PID, so each session sounds different.
- `riff-wav-bytes` synthesises a 16-bit mono 22050 Hz WAV. Each note is a fundamental, a sub-octave and two harmonics under an envelope that returns to zero, so section joins and the loop wrap are click-free.
- The track is written once per session to `sys_get_temp_dir()/phel-doom-music-<pid>.wav` and looped whole by a backgrounded shell. That shell also guards on `kill -0 <game-pid>`.

Lifecycle, driven from `commands/play`: `start-music!` when gameplay begins, `pause-music!` / `resume-music!` (SIGSTOP / SIGCONT) on the pause edge, `sync-music!` on N, `stop-music!` on teardown, which also deletes the temp WAV. Every entry point is a no-op under `PHEL_DOOM_SILENT` or with no audio player.
