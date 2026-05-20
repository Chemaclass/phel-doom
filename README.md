# phel-doom

![phel-doom in action](docs/screenshot.png)

A DOOM-lite raycaster in your terminal, written in [Phel Lang](https://phel-lang.org/), a functional Lisp on PHP.

## Features

- 256-color ANSI raycaster, full-terminal viewport (FOV scales, walls don't)
- Procedurally generated map per level: random walls, one door, one heart
  pickup (when you're below max-lives)
- 5 levels of escalating difficulty — bigger room each time, more enemies,
  faster chase, new monster type with its own colour
  (imps → demons → cacodemons → barons → cyberdemons)
- Chasing enemies that pathfind around walls; hitscan combat with blood
  splatter, muzzle flash, and auto-respawn so the arena stays populated
- 5 lives, post-hit i-frame window, blood-red palette flush while hit
- Door = auto-trigger portal: walk in, advance to next level
- Heart pickups refill one life (capped at 5)
- "YOU DIED" + "VICTORY" centred end screens with cumulative kills + time
- Live minimap (top-right overlay, toggleable), top-left heart HUD,
  bottom HUD with level, kills, fps, frame ms, position, heading
- Pause menu with sound toggle + credits, restart from any end screen
- Sound effects via OS shell-out (afplay / paplay / aplay / play)
  with terminal-bell fallback
- WAD parser: reads any IWAD / PWAD's header + lump directory and
  decodes VERTEXES / LINEDEFS lumps
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
| `m`       | Toggle minimap      |
| `n`       | Toggle sound on/off |
| `p`       | Pause (menu shows sound, credits)  |
| `q`       | Quit                |

Inputs layer freely: `w` + `a` + `→` walks forward, strafes left, pans
view right. Walk into a door to auto-advance to the next level; walk
over a heart to refill a life.

## Project layout

```
src/
├── main.phel                 ; CLI entrypoint + Application wiring
├── commands/play.phel        ; IO shell: game-loop + end screens + run lifecycle
└── modules/
    ├── state.phel            ; world + player records, pure updates, gain-life
    ├── map.phel              ; grid generators + cell constants + lookups
    ├── engine.phel           ; raycaster (step march, proj-dist)
    ├── enemy.phel            ; spawn, chase AI, shoot, respawn
    ├── controls.phel         ; key bytes → counters + rising-edge detection
    ├── physics.phel          ; player rotation + translation + counter decay
    ├── combat.phel           ; fire-shot + damage-step + blood fx + tunables
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

`commands/play.phel` is a thin IO shell. The per-frame transition is a
pure function composed from focused modules:

- `game-loop` polls `stty size`, calls `render!`, sleeps 1ms, drains
  keys, edge-detects toggle keys, and hands the world to `tick-world`.
- `tick-world(world, keys, dt, edges)` is the pure function: apply
  toggles, refresh input counters, run physics, pick up hearts,
  advance enemies, resolve a fire shot, decay timers. Same function
  the test suite calls directly.

Per-domain logic is split for readability:

- **controls.phel** owns key bytes → `:moves` counters + rising-edge
  detection for one-shot keys.
- **physics.phel** owns rotation, translation, and counter decay.
- **combat.phel** owns the hitscan + i-frame timing + damage.
- **level.phel** owns the 5-level catalog + `build-world` factory.

Render time is the throttle; the 1ms `usleep` only yields the CPU.

## Performance

Per-frame `frame->string` on the bundled bench (32×22 map, minimap on):
~2 ms (80×24), ~3 ms (120×30), ~5 ms (180×40). The game loop is
bounded by `stty size` + `microtime` overhead, not the raycaster.

Hot per-cell loop pushed off Phel's polymorphic runtime onto direct PHP ops:

- `php/aget`, `php/+`, `php/<`, `php/*` etc. compile to PHP subscript /
  operator emission, skipping the runtime dispatch path.
- `cast-frame` returns a flat PHP array of distances; renderer walks
  it by index, no lazy seq.
- 24 grayscale ANSI strings baked into `shade-table`, so per-cell
  shade is one `php/aget`.
- Viewport row run-length encoded into a PHP array, `php/implode`'d
  once. No `(str acc ...)` chain.
- Minimap reads `:pgrid` (PHP-native nested array) instead of Phel
  persistent vectors.
- Alternate screen buffer + cursor-home redraw + autowrap off, so
  frames overwrite in place.
- Hot-path numeric args carry `^float` tags so Phel doesn't infer int
  signatures from `*` constants and trigger PHP 8.4+ precision-loss
  deprecations on `microtime()` values.

`proj-dist` is decoupled from viewport width: each ray's angular
offset is `atan(col-offset / proj-dist)`, so resizing the terminal
widens the FOV instead of zooming the walls.

## Development

```bash
composer test          # phel tests (132 across all modules)
composer format        # auto-format
composer lint          # phel-lint (clean policy: zero warnings)
composer build         # out/main.php standalone
composer repl          # interactive REPL
```

CI on every push runs `phel doctor`, `phel format --dry-run`,
`phel lint`, `phel test`, `phel build` against PHP 8.4 and 8.5
(`.github/workflows/ci.yml`).

## Roadmap

- [x] Raycaster + procedural map + player movement & collision
- [x] Live minimap, HUD, full-terminal viewport
- [x] Enemies (chase AI, hitscan, lives, i-frames, blood, muzzle flash)
- [x] Doors (auto-advance to the next level on touch)
- [x] 5-level progression with monster variety, heart pickups
- [x] Death + victory end screens, run-restart from either
- [x] WAD file parser (header + directory + VERTEXES/LINEDEFS lumps)
- [x] Sound (OS shell-out + terminal-bell fallback)

### Next steps

- BSP-based renderer that consumes parsed WAD geometry (real DOOM levels)
- `ext-ffi` + miniaudio backend behind the existing `sound/play-async!` surface
- Weapon switching + ammo
- More pickup kinds (armour, keys, ammo) on the procedural map

## License

MIT
