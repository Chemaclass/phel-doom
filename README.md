# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/0s-sXxpcoIA/maxresdefault.jpg)](https://www.youtube.com/watch?v=0s-sXxpcoIA)

DOOM-lite raycaster in your terminal. Pure [Phel](https://phel-lang.org/) (Lisp on PHP). 256-color ANSI, 10 levels, FPS combat, ~5ms frame. Full feature list: [docs/features.md](docs/features.md).

## Play

Needs PHP >= 8.5 and a 256-color terminal.

Grab the single-file PHAR from the [latest release](https://github.com/Chemaclass/phel-doom/releases/latest). No clone, no Composer:

```bash
curl -fsSL -o phel-doom.phar https://github.com/Chemaclass/phel-doom/releases/latest/download/phel-doom.phar
php phel-doom.phar
```

<details>
<summary>Build from source (Composer or Docker)</summary>

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
make install   # or: composer install
make play      # or: composer play
```

No local PHP? The Docker image bundles PHP 8.5, Composer and the deps:

```bash
make docker-build   # build image (tag: DOCKER_IMG=mytag)
make docker-play    # launch game (raw TTY)
make docker-test    # run test suite
make docker-shell   # bash inside container
make docker-clean   # remove image
```

Docker adds ~1s per command. Host PHP stays the faster inner loop.

</details>

## Controls

`w` `a` `s` `d` move, arrows or mouse turn and look, `space` or left-click fire, `r` reload, `1`-`7` weapons, `p` pause, `q` quit (press twice). Walk into doors to advance.

Full key list, pickups and weapons: [docs/gameplay.md](docs/gameplay.md).

## Internals

- [docs/README.md](docs/README.md): index of per-subsystem docs.
- [docs/coming-from-clojure-or-php.md](docs/coming-from-clojure-or-php.md): read Phel fast if you know Clojure or PHP.
- [docs/contributing.md](docs/contributing.md): dev loop, gates, test conventions, Phel gotchas.

## License

MIT
