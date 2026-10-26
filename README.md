# phel-doom

[![phel-doom gameplay (YouTube)](https://img.youtube.com/vi/Gvz95m4wAkQ/maxresdefault.jpg)](https://www.youtube.com/watch?v=Gvz95m4wAkQ)

A DOOM-lite raycaster for the terminal, written in pure [Phel](https://phel-lang.org/), a Lisp that compiles to PHP. It has 256-color ANSI graphics, 10 levels, first-person combat, and a frame time of about 5 ms. See the [feature list](docs/features.md).

## Play

Needs PHP >= 8.5 and a 256-color terminal.

Download the single-file PHAR from the [latest release](https://github.com/Chemaclass/phel-doom/releases/latest). You don't need to clone the repository or install Composer:

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

The Docker image includes PHP 8.5, Composer, and the dependencies:

```bash
make docker-build   # build image (tag: DOCKER_IMG=mytag)
make docker-play    # launch game (raw TTY)
make docker-test    # run test suite
make docker-shell   # bash inside container
make docker-clean   # remove image
```

Docker adds about 1 second per command. Local PHP is faster for development.

</details>

## Controls

Use `w` `a` `s` `d` to move, arrows or mouse to turn and look, `space` or left-click to fire, `r` to reload, `1`-`7` to select weapons, `p` to pause, and `q` twice to quit. Walk into doors to advance.

See [gameplay](docs/gameplay.md) for all controls, pickups, and weapons.

## Internals

- [Documentation index](docs/README.md): guides to each subsystem.
- [Coming from Clojure or PHP](docs/coming-from-clojure-or-php.md): an introduction to Phel for Clojure and PHP developers.
- [Contributing](docs/contributing.md): development commands, checks, test conventions, and Phel pitfalls.

## License

MIT
