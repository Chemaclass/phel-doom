# phel-doom

![phel-doom in action](docs/screenshot.png)

A DOOM-lite showcase written in [Phel Lang](https://phel-lang.org/), a
functional Lisp that compiles to PHP.

`phel-doom` ships a terminal raycaster: pure-functional world state, ANSI 24-bit
shaded walls, WASD controls, a live minimap, and a HUD with position, heading,
fps, and per-frame timings. Runs entirely in your shell.

## Requirements

- PHP **>= 8.4**
- [Composer](https://getcomposer.org/)
- A terminal that supports ANSI 24-bit color (most modern terminals)

## Quick start

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
composer install
composer play           # WASD to move/turn, Q to quit
```

Or from the Makefile:

```bash
make install
make play
```

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
┌─────────────┐    ┌───────────┐    ┌────────────┐    ┌──────────┐
│ input.phel  │───▶│ state.phel│───▶│ engine.phel│───▶│render.phel│
│ STDIN raw   │    │ pure step │    │ raycast    │    │ ANSI out  │
└─────────────┘    └───────────┘    └────────────┘    └──────────┘
```

The game loop is one `loop`/`recur` in `commands/play.phel`. Every frame:

1. Render current world (`render!`).
2. Sleep one frame (~33ms).
3. Read one key non-blocking (`read-key`).
4. Step state via pure `step-input` → recur.

## Controls

| Key | Action       |
|-----|--------------|
| `w` | Move forward |
| `s` | Move back    |
| `a` | Turn left    |
| `d` | Turn right   |
| `q` | Quit         |

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
- [ ] Enemies (sprites)
- [ ] Doors
- [ ] WAD file parser (real DOOM levels)
- [ ] Sound via `ext-ffi` + miniaudio

## License

MIT
