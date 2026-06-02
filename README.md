# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Pure [Phel](https://phel-lang.org/) (Lisp on PHP). 256-color ANSI, 10 procgen levels, FPS combat, ~5ms frame. Full feature list: [docs/features.md](docs/features.md).

## Play

Needs PHP >= 8.4, Composer, and a 256-color terminal.

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install
make play
```

Or `composer install && composer play`.

<details>
<summary>No local PHP? Run in Docker</summary>

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
| `w` `a` `s` `d` / arrows | Move / turn    |
| `SHIFT`        | Sprint                  |
| `space` / `r`  | Fire / reload           |
| `1`...`7`      | Switch weapon           |
| `p` / `q`      | Pause / quit            |

Walk into doors to advance. Find weapons and pickups on the map.

Full controls, pickups, and weapons: [docs/gameplay.md](docs/gameplay.md).

## Internals

- [docs/README.md](docs/README.md) - per-subsystem guide.
- [docs/contributing.md](docs/contributing.md) - dev setup, test conventions, Phel gotchas.

## License

MIT
