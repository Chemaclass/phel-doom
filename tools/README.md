# tools/

Dev-time scripts. Nothing here ships in the phar.

## Asset bakers

The repo holds no binary art or audio. Each baker reads lumps from the [Freedoom](https://freedoom.github.io/) WADs (BSD) with `src/io/wad.phel` and writes a committed Phel data file. Re-run one only to change which lumps or frames are extracted (edit the list in the script) or to bump the Freedoom version.

Fetch the WADs once:

```bash
curl -L -o /tmp/freedoom.zip https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip
unzip -j /tmp/freedoom.zip '*.wad' -d /tmp/freedoom
# -> /tmp/freedoom/freedoom1.wad, /tmp/freedoom/freedoom2.wad
```

Run with `vendor/bin/phel run tools/<script> <freedoom1.wad> <freedoom2.wad>`:

| Script | Writes | Content |
|--------|--------|---------|
| `bake-enemy-sprites.phel` | `src/io/render/enemy_sprites_data.phel` | 256-colour enemy frames at native resolution, projectiles, floating pickups, death sequences, blood spurts. Needs both WADs. |
| `bake-weapon-sprites.phel` | `src/io/render/weapon_sprites_data.phel` | first-person weapon frames |
| `bake-weapon-sounds.phel` | `src/io/sound_data.phel` | 36 DMX sounds as base64 WAVs (see [audio.md](../docs/audio.md)) |

`src/io/render/wall_texture_data.phel` was baked once from a Freedoom flat and then sanitized to grayscale. No script regenerates it.

After re-baking, run `composer test`, then smoke-test visually with the `/play` skill.

## Frame shots

`frame-shot.sh` renders a frame script (e.g. `shots/showcase.phel`) to PNG through `frame-to-html.php` and headless Chrome. See [contributing.md](../docs/contributing.md#looking-at-a-frame).

## Benchmarking

`bench-ab.sh` compares two git refs. `bench-flags.sh` compares render features within one ref by switching each off. Both interleave their configs, because a single reading drifts more than most changes are worth. See [performance.md](../docs/performance.md) for the current cost split.

## Build guards

Each is a `composer` script inside `composer ci`, with its own fixtures (`*-test.sh`). Details: [contributing.md](../docs/contributing.md#gates).

| Guard | Fails when |
|-------|-----------|
| `format-sources.sh` | a hand-written `.phel` file is not formatted (skips generated data files) |
| `check-layers.sh` | a require points the wrong way across `io/` -> `glue/` -> `core/` |
| `check-cycles.php` | two phel-doom namespaces require each other, directly or through an alias |
| `check-unused.php` | a top-level definition under `src/` is referenced nowhere in `src/`, `tests/` or `tools/` |
| `check-docs.php` | a doc links to a missing file or heading, or names a path or composer script that is not there |
| `check-deprecations.sh` | the suite raises a compiler deprecation or a float-truncation notice |

`check-cycles` and `check-unused` share `lib/phel-source.php`. It blanks `;` comments, `#_` discards and string bodies while keeping offsets, so a name that appears only in prose cannot fool either guard.

## Release

`release.sh` cuts a release: validate semver and preflight, move the `## [Unreleased]` CHANGELOG block into a dated section, bump `src/core/version.phel`, build and smoke-test `phel-doom.phar` (via `build/phar.sh`), commit, tag `vX.Y.Z`, push, and create the GitHub release with the phar and its SHA256 attached.

Do not run it raw. Use the `/release` skill, which wraps it and verifies the published phar and GitHub release.

```
./tools/release.sh [version] [--dry-run] [--force] [--name "Release name"]
```
