# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Pure [Phel](https://phel-lang.org/) (Lisp on PHP). 256-color ANSI, 10 procgen levels, FPS combat, ~5ms frame. Full feature list: [docs/features.md](docs/features.md).

## Play

Needs PHP >= 8.4 and a 256-color terminal.

Fastest: grab the single-file PHAR from the [latest release](https://github.com/Chemaclass/phel-doom/releases/latest) (no clone, no Composer):

```bash
curl -fsSL -o phel-doom.phar https://github.com/Chemaclass/phel-doom/releases/latest/download/phel-doom.phar
php phel-doom.phar
```

<details>
<summary>Build from source (needs Composer, or Docker)</summary>

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

Or `composer install && composer play`.

### No local PHP? Run in Docker

PHP 8.5 CLI + Composer + deps in an image; `docker` is the only prerequisite.

```bash
make docker-build      # build image
make docker-play       # launch game (raw TTY)
make docker-test       # run test suite
make docker-shell      # bash inside container
make docker-clean      # remove image
```

Override tag: `DOCKER_IMG=mytag make docker-build`. Host PHP is the inner loop; Docker adds ~1s startup.

</details>

## Controls

| Key            | Action                  |
|---|---|
| `w` `a` `s` `d`         | Move / strafe           |
| `←` `→` / `↑` `↓`       | Turn / look up, down    |
| mouse          | Look + turn, left-click to fire (on by default) |
| `SHIFT`        | Sprint                  |
| `space` / `r`  | Fire / reload           |
| `1`...`7`      | Switch weapon           |
| `[` / `]` / wheel | Cycle weapons        |
| `p` / `q`      | Pause / quit (q asks, press again) |

Walk into doors to advance. Find weapons and pickups on the map.

Full controls, pickups, and weapons: [docs/gameplay.md](docs/gameplay.md).

## Internals

- [docs/README.md](docs/README.md) - per-subsystem guide.
- [docs/coming-from-clojure-or-php.md](docs/coming-from-clojure-or-php.md) - read Phel fast if you know Clojure or PHP.
- [docs/contributing.md](docs/contributing.md) - dev setup, test conventions, Phel gotchas.

## License

MIT
