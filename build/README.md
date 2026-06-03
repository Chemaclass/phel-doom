# build/

Artifact production for phel-doom. Everything here turns the source tree into
a shippable single-file executable: `phel-doom.phar`. Release orchestration
lives in [`../tools/release.sh`](../tools/release.sh).

## Files

| File | Purpose |
|---|---|
| [`phar.sh`](phar.sh) | Build entry point. Compiles the game, then runs the packager. |
| [`build-phar.php`](build-phar.php) | Bundles `out/` + `vendor/` into a GZ-compressed, SHA256-signed PHAR with a stub that runs `out/main.php`. |
| `out/` | PHAR output (`out/phel-doom.phar`). Gitignored. |

## How it works

phel-doom is a Phel *application*, not the compiler. `phel build` emits the
whole game plus the Phel stdlib it touches as ready-to-run PHP under `out/`.
Nothing compiles at runtime (`phar.readonly` forbids it anyway), so packaging
is two steps, orchestrated by `phar.sh`:

1. `phel build --no-cache` -> compiled PHP under `out/`.
2. `build-phar.php` bundles `out/` + `vendor/` (minus `.phel`/`.map` and any
   `tests`/`docs` dirs), sets a stub that maps the PHAR and runs `out/main.php`,
   then GZ-compresses and SHA256-signs.

It is a ~90-line `Phar` build with no external tool, no network fetch, and no
mutation of the working tree's `vendor/`. The whole vendor tree ships as-is; the
single dev dependency (var-dumper, ~200 KB) rides along as harmless dead weight,
because pruning it would mean regenerating a `--no-dev` autoloader (i.e.
mutating `vendor/`). The stub's `out/main.php` does its own
`require "../vendor/autoload.php"`, which resolves inside the PHAR. Levels are
generated procedurally, so there are no external assets to bundle.

The reported version comes from `src/core/version.phel` (the single source of
truth, also shown in the start menu + credits), which `tools/release.sh` bumps
as part of the release commit - the build stamps nothing.

## Build

```bash
./build/phar.sh
# -> build/out/phel-doom.phar
```

Run it:

```bash
php build/out/phel-doom.phar          # play
php build/out/phel-doom.phar --version
```

## Not here

- Release orchestration (version bump, CHANGELOG, tag, push, GitHub release +
  PHAR attach) -> [`../tools/release.sh`](../tools/release.sh).
