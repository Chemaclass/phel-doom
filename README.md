# phel-doom

![phel-doom in action](docs/screenshot.png)

A DOOM-lite raycaster in your terminal, written in [Phel Lang](https://phel-lang.org/), a functional Lisp on PHP.

## Features

- 256-color ANSI raycaster, full-terminal viewport (FOV scales, walls don't)
- Procedurally generated map per level, with random walls + a door portal
- 5 levels of escalating difficulty: bigger room each time, more enemies,
  faster chase, new monster type with its own colour (imps → demons →
  cacodemons → barons → cyberdemons)
- Chasing enemies that pathfind around walls; hitscan combat with blood
  splatter, muzzle flash, and auto-respawn so the arena stays populated
- 3 lives, i-frame window after each hit, blood-red palette flush while
  hit, "YOU DIED" screen with final kill count
- Live minimap (top-right overlay, toggleable), top-left heart HUD,
  bottom HUD with kills / fps / frame ms / pos / heading
- Pause toggle and a bottom-of-screen gun glyph with on-fire flash
- WAD parser: reads any IWAD / PWAD's header + lump directory and
  decodes VERTEXES / LINEDEFS lumps
- Sound effects via terminal bell on shoot / hit / door open
- Pure-functional world state, single `loop`/`recur` game loop
- Sub-5ms `frame->string` even at 180×40 viewport

## Requirements

- PHP **>= 8.4**
- [Composer](https://getcomposer.org/)
- 256-color ANSI terminal

## Quick start

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

`composer install` / `composer play` work too.

## Controls

| Key       | Action              |
|-----------|---------------------|
| `w` / `s` | Move forward / back |
| `a` / `d` | Strafe left / right |
| `←` / `→` | Turn left / right   |
| `space`   | Fire                |
| `e`       | Open door in front  |
| `m`       | Toggle minimap      |
| `n`       | Toggle sound on/off |
| `p`       | Pause (menu shows sound, credits)  |
| `q`       | Quit                |

Inputs layer freely: `w` + `a` + `→` walks forward, strafes left, pans view right.

## Project layout

```
src/
├── main.phel                 ; CLI entrypoint + Application wiring
├── commands/play.phel        ; subcommand: play (game loop, tick-world)
└── modules/
    ├── state.phel            ; player + world records, pure updates
    ├── map.phel              ; grid generators + cell constants + lookups
    ├── engine.phel           ; raycaster (step march, proj-dist)
    ├── enemy.phel            ; spawn, chase AI, shoot, blood fx
    ├── level.phel            ; 5-level catalog + build-world factory
    ├── render.phel           ; ANSI frame + sprites + HUD + end screens
    ├── input.phel            ; raw STDIN, non-blocking key reads
    ├── sound.phel            ; OS shell-out sfx (afplay/paplay/aplay)
    └── wad.phel              ; DOOM .wad parser (header, lumps, geometry)
tests/                        ; mirrors src/, one *-test.phel per module
phel-config.php               ; build / export / format config
.github/workflows/ci.yml      ; CI: format-check, lint, test, build
```

## Architecture

```
┌─────────────┐    ┌───────────┐    ┌────────────┐    ┌─────────────────────┐
│ input.phel  │───▶│ state.phel│───▶│ engine.phel│───▶│ render.phel         │
│ drain-keys  │    │ pure step │    │ raycast    │    │ viewport+sprites+HUD│
└─────────────┘    └───────────┘    └────────────┘    └─────────────────────┘
                         ▲                 ▲
                         │                 │
                         └── enemy.phel ───┘
                             chase + shoot
```

`commands/play.phel` splits IO from pure logic:

- `game-loop` is the IO shell: it polls `stty size`, calls `render!`,
  sleeps 1ms, drains keys, edge-detects toggle keys, and hands the
  world to one pure function.
- `tick-world(world, keys, dt, edges)` is that pure function: apply
  toggles, refresh input counters, run physics, advance enemies,
  resolve a fire shot, decay timers. Same fn the test suite calls
  directly to assert per-frame behaviour.

Render time is the throttle; the 1ms `usleep` only yields the CPU.

## Performance

Per-frame `frame->string` on the bundled bench (32×22 map, minimap on):
~2 ms (80×24), ~3 ms (120×30), ~5 ms (180×40). Loop is bounded by
`stty size` + `microtime` overhead, not the raycaster.

Hot per-cell loop pushed off Phel's polymorphic runtime onto direct PHP ops:

- `php/aget`, `php/+`, `php/<`, `php/*` etc. compile to PHP subscript / operator emission, skipping the runtime dispatch path.
- `cast-frame` returns a flat PHP array of distances; renderer walks it by index, no lazy seq.
- 24 grayscale ANSI strings baked into `shade-table`, so per-cell shade is one `php/aget`.
- Viewport row run-length encoded into a PHP array, `php/implode`'d once. No `(str acc ...)` chain.
- Minimap reads `:pgrid` (PHP-native nested array) instead of Phel persistent vectors.
- Alternate screen buffer + cursor-home redraw + autowrap off, so frames overwrite in place.

`proj-dist` is decoupled from viewport width: each ray's angular offset is `atan(col-offset / proj-dist)`, so resizing the terminal widens the FOV instead of zooming the walls.

## Development

```bash
composer test          # phel tests (129 across map/state/engine/enemy/render/wad/level/play)
composer format        # auto-format
composer lint          # phel-lint (clean policy: zero warnings)
composer build         # out/main.php standalone
composer repl          # interactive REPL
```

CI on every push runs `phel doctor`, `phel format --dry-run`, `phel lint`,
`phel test`, `phel build` against PHP 8.4 and 8.5
(`.github/workflows/ci.yml`).

## Roadmap

- [x] Raycaster + procedural map + player movement & collision
- [x] Live minimap, HUD, full-terminal viewport
- [x] Enemies (chase AI, hitscan, lives, i-frames, blood, muzzle flash)
- [x] Doors (closed cells you open with E)
- [x] WAD file parser (header + directory + VERTEXES/LINEDEFS lumps)
- [x] Sound (terminal bell on shoot / hit / door open; `ext-ffi`+miniaudio left as a future swap)

### Next steps

- BSP-based renderer that consumes parsed WAD geometry (real DOOM levels)
- `ext-ffi` + miniaudio backend behind the existing `sound/play-async!` surface
- Weapon switching + ammo
- Power-ups / pickups on the procedural map

## License

MIT
