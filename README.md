# phel-doom

![phel-doom in action](docs/screenshot.png)

DOOM-lite showcase in [Phel Lang](https://phel-lang.org/) — functional Lisp on PHP.

Terminal raycaster: pure-functional world state, 256-color ANSI walls, WASD,
live minimap, HUD (lives, kills, pos, heading, fps, frame ms), chasing enemies.
Runs in your shell.

## Requirements

- PHP **>= 8.4**
- [Composer](https://getcomposer.org/)
- 256-color ANSI terminal

## Quick start

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play          # WASD to move/turn, Q to quit
```

`composer install` / `composer play` work too.

## Project layout

```
src/
├── main.phel                          ; CLI entrypoint + Application wiring
├── commands/
│   └── play.phel                      ; subcommand: play
└── modules/
    ├── state.phel                     ; player + world records, pure updates
    ├── map.phel                       ; level grid + wall lookup
    ├── engine.phel                    ; raycaster (step march)
    ├── enemy.phel                     ; enemy spawn, chase AI, damage
    ├── render.phel                    ; ANSI frame composer + minimap + HUD
    └── input.phel                     ; raw STDIN, non-blocking key reads
tests/
└── modules/                           ; unit tests per module
phel-config.php                        ; build / export / format config
```

## Architecture

```
┌─────────────┐    ┌───────────┐    ┌────────────┐    ┌─────────────────────┐
│ input.phel  │───▶│ state.phel│───▶│ engine.phel│───▶│ render.phel         │
│ drain-keys  │    │ pure step │    │ raycast    │    │ viewport+minimap+HUD│
└─────────────┘    └───────────┘    └────────────┘    └─────────────────────┘
```

Game loop is one `loop`/`recur` in `commands/play.phel`. Each frame:

1. `render!` paints 3D viewport, minimap, HUD in one ANSI string.
2. `drain-keys` reads queued STDIN bytes (held key = multiple steps).
3. `apply-keys` folds each byte through pure `step-input` → recur.

Render time is the throttle; 1ms `usleep` only yields the CPU.

## Performance

Loop is bounded by `stty size` + `microtime` overhead, not the raycaster.
Per-frame `frame->string` on bundled bench (32×22 procedural map, minimap on):
~2 ms (80×24, ~440 fps), ~3 ms (120×30, ~310 fps), ~5 ms (180×40, ~210 fps).

Hot per-cell loop pushed off Phel's polymorphic runtime onto direct PHP ops:

- `php/aget`, `php/aset`, `php/+`, `php/<`, `php/===`, `php/*`, `php/-`,
  `php//` instead of `core/aget`, `+`, `<`, `=`, `*`, `-`, `/` — compiles to
  PHP subscript / operator emission, not runtime function calls.
- `cast-frame` returns flat PHP array of per-column distances. Renderer walks
  it by index with `php/aget`; no lazy seq, no keyword lookup per ray.
- 24 grayscale ANSI strings baked into `shade-table` (PHP array). Per-cell
  shade is one `php/aget`, not a `memoize-lru` lookup.
- 3D viewport row built with run-length encoding (one ANSI escape per colour
  run) into a PHP array, then `php/implode`'d once. No `(str acc ...)` chain
  re-copying the row buffer on every colour change.
- Minimap reads `:pgrid` (PHP-native nested array, stashed at construction)
  instead of Phel persistent vectors.
- Alternate screen buffer + cursor-home redraw + autowrap off — frames
  overwrite in place, no scrolling.

`engine.phel` keeps `proj-dist` decoupled from viewport width: each ray's
angular offset is `atan(col-offset / proj-dist)`. Resizing the terminal widens
the FOV instead of zooming the walls.

## Controls

DOOM-style, no mouse.

| Key       | Action              |
|-----------|---------------------|
| `↑` / `w` | Move forward        |
| `↓` / `s` | Move back           |
| `a` / `d` | Strafe left / right |
| `←` / `→` | Turn left / right   |
| `space`   | Fire                |
| `m`       | Toggle minimap      |
| `q`       | Quit                |

Compose freely: `w` + `a` + `→` walks forward, strafes left, pans view right.

## Development

```bash
composer test          # phel tests
composer format        # auto-format
composer lint          # phel-lint
composer build         # out/main.php standalone
composer repl          # interactive REPL
```

## Roadmap

- [x] Static map + raycaster
- [x] Player movement + collision
- [x] Procedurally generated map per run
- [x] Live minimap + HUD (lives, kills, pos, heading, fps, frame ms)
- [x] Full-terminal viewport with constant wall scale on resize
- [x] Enemies (chase AI, damage, i-frames, gun + muzzle flash)
- [ ] Doors
- [ ] WAD file parser (real DOOM levels)
- [ ] Sound via `ext-ffi` + miniaudio

## License

MIT
