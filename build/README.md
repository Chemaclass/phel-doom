# build/

Turns the source tree into one self-contained executable: `phel-doom.phar`. Release orchestration lives in [`../tools/release.sh`](../tools/release.sh).

| File | Purpose |
|---|---|
| [`phar.sh`](phar.sh) | Build entry point. Compiles the game, then runs the packager. |
| [`build-phar.php`](build-phar.php) | Bundles `out/` + `vendor/` into a GZ-compressed, SHA256-signed PHAR whose stub runs `out/main.php`. |
| `out/` | PHAR output (`out/phel-doom.phar`). Gitignored. |

## Build

```bash
./build/phar.sh
php build/out/phel-doom.phar            # play
php build/out/phel-doom.phar --version
```

## How it works

`phel build` emits the whole game plus the Phel stdlib it uses as ready-to-run PHP under `out/`. Nothing compiles at runtime (`phar.readonly` forbids it anyway). So packaging is two steps:

1. `vendor/bin/phel build --no-cache` → compiled PHP under `out/`.
2. `build-phar.php` bundles `out/` + `vendor/`, minus `.phel` sources, `.map` files and any `tests` / `docs` dirs, then compresses and signs.

It is a ~100-line `Phar` script: no external tool, no network fetch, no mutation of `vendor/`. The one dev dependency (var-dumper, ~200 KB) ships as dead weight, because pruning it would mean regenerating a `--no-dev` autoloader. Levels are procedural and art and sound are baked into Phel data files, so there are no external assets to bundle.

The version comes from `src/core/version.phel` (also shown in the start menu and credits). `tools/release.sh` bumps it. The build stamps nothing.
