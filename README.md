# phel-doom

![phel-doom in action](docs/screenshot.png)

A DOOM-lite showcase written in [Phel Lang](https://phel-lang.org/), a
functional Lisp that compiles to PHP.

`phel-doom` ships a terminal raycaster: pure-functional world state, 256-color
ANSI shaded walls, WASD controls, a live minimap, and a HUD with position,
heading, fps, and per-frame timings. Runs entirely in your shell.

## Requirements

- PHP **>= 8.4**
- [Composer](https://getcomposer.org/)
- A terminal that supports 256-color ANSI (most modern terminals)

## Quick start

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play          # WASD to move/turn, Q to quit
```

Composer equivalents (`composer install`, `composer play`) work too.

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

The game loop is one `loop`/`recur` in `commands/play.phel`. Every frame:

1. `render!` paints the 3D viewport, minimap, and HUD in one ANSI string.
2. `drain-keys` reads all queued bytes from STDIN (held keys = multiple steps).
3. `apply-keys` folds each byte through pure `step-input` → recur.

Render time is the throttle; the 1ms `usleep` only yields the CPU.

## Performance

Render is fast enough that the game loop is bounded by `stty size` +
`microtime` overhead, not by the raycaster. Per-frame `frame->string`
cost on the bundled bench (32×22 procedural map, minimap visible):

| Viewport | Before optimisation | After       |
|----------|---------------------|-------------|
| 80×24    | ~150 ms (~7 fps)    | ~2 ms (~440 fps) |
| 120×30   | ~220 ms (~5 fps)    | ~3 ms (~310 fps) |
| 180×40   | n/a (capped)        | ~5 ms (~210 fps) |

The wins came from pushing the hot per-cell loop off Phel's polymorphic
runtime and onto direct PHP ops:

- `php/aget`, `php/aset`, `php/+`, `php/<`, `php/===`, `php/*`, `php/-`,
  `php//` instead of `core/aget`, `+`, `<`, `=`, `*`, `-`, `/` — compiles
  to PHP subscript / operator emission instead of a runtime function
  call per op.
- `cast-frame` returns a flat PHP array of per-column distances. The
  renderer walks it by index with `php/aget`; no lazy seq, no keyword
  lookup per ray.
- The 24 grayscale ANSI strings are baked into `shade-table` (a PHP
  array). Per-cell shade is one `php/aget`, not a `memoize-lru` lookup.
- The 3D viewport row is built with run-length encoding (one ANSI
  escape per colour run) into a PHP array, then `php/implode`'d once.
  Avoids the `(str acc ...)` chain that re-copied the row buffer on
  every colour change.
- The minimap reads through `:pgrid` (PHP-native nested array stashed
  on the world at construction time) instead of through Phel persistent
  vectors.
- Alternate screen buffer + cursor-home redraw + autowrap off, so
  consecutive frames overwrite in place instead of scrolling.

`engine.phel` keeps the projection constant (`proj-dist`) decoupled
from the viewport width: each ray's angular offset is `atan(col-offset /
proj-dist)`, so resizing the terminal widens the FOV rather than
zooming the walls.

## Controls

Classic DOOM layout — no mouse needed.

| Key       | Action              |
|-----------|---------------------|
| `↑` / `↓` | Move forward / back |
| `←` / `→` | Turn left / right   |
| `,` / `.` | Strafe left / right |
| `m`       | Toggle minimap      |
| `q`       | Quit                |

Movement and turning compose freely: holding `↑` + `,` + `→` walks
forward, strafes left, and pans the view right all at once.

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
- [x] Live minimap + HUD (position, heading, fps, frame ms)
- [x] Full-terminal viewport with constant wall scale on resize
- [ ] Enemies (sprites)
- [ ] Doors
- [ ] WAD file parser (real DOOM levels)
- [ ] Sound via `ext-ffi` + miniaudio

## License

MIT
