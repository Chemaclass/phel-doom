# tools/

Build-time scripts. Run by hand, not part of the game runtime. Nothing here ships in the phar.

## Asset bakers

The game commits no binary art or audio. Each baker extracts lumps from a [Freedoom](https://freedoom.github.io/) WAD (BSD-licensed) and writes a committed Phel data file that the runtime reads. Re-run a baker only when changing which lumps/frames are extracted (edit the lump list in the script) or bumping the Freedoom version. Otherwise the data is already committed and there is nothing to do.

### Get the WADs

The WADs are not in the repo. Fetch Freedoom once:

```bash
curl -L -o /tmp/freedoom.zip https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip
unzip -j /tmp/freedoom.zip '*.wad' -d /tmp/freedoom
# -> /tmp/freedoom/freedoom1.wad, /tmp/freedoom/freedoom2.wad
```

### Run

| Script | Command | Writes |
|--------|---------|--------|
| `bake-enemy-sprites.phel` | `vendor/bin/phel run tools/bake-enemy-sprites.phel <freedoom1.wad> <freedoom2.wad>` | `src/io/render/enemy_sprites_data.phel` |
| `bake-weapon-sprites.phel` | `vendor/bin/phel run tools/bake-weapon-sprites.phel <freedoom1.wad> [freedoom2.wad]` | `src/io/render/weapon_sprites_data.phel` |
| `bake-weapon-sounds.phel` | `vendor/bin/phel run tools/bake-weapon-sounds.phel <freedoom1.wad>` | `src/io/sound_data.phel` |

What each bakes:

- **Enemy sprites** - front-facing enemy frames at native resolution (render samples them into the billboard span), plus projectile tracers (fireball, BFG ball, rocket, plasma), floating pickups (area-averaged mip), per-type death sequences, and blood-spurt frames. Output is 256-colour.
- **Weapon sprites** - first-person weapon frames.
- **Weapon sounds** - DMX sounds decoded to a base64 WAV map. Runtime (`src/io/sound.phel`) writes each to a temp WAV once, then `afplay`s it per fire event.

### After re-baking

```bash
composer test   # data files load + game logic still green
```

Then smoke-test visually with the `/play` skill.

## Build guards

Each is a `composer` script wired into `composer ci`, and each ships its own fixtures (`*-test.sh`) because a guard that is quietly wrong is worse than no guard.

| Guard | Fails when |
|-------|-----------|
| `check-layers.sh` | a require points the wrong way across `io/` -> `glue/` -> `core/` |
| `check-cycles.php` | two phel-doom namespaces require each other, directly or through an alias |
| `check-unused.php` | a top-level definition under `src/` is referenced nowhere in `src/`, `tests/` or `tools/` |
| `check-deprecations.sh` | the suite raises a compiler deprecation or a float-truncation notice |

`check-cycles` and `check-unused` share `lib/phel-source.php`, which blanks `;` comments, `#_` discards and string bodies while keeping offsets and newlines, so neither can be fooled by a name that appears only in prose - and a fix to that parser reaches both.

`php tools/check-unused.php --report` also lists the definitions referenced only from `tests/`. Those are not failures (a fixture, or a parser whose only caller today is its own test), but the list is worth a look when hunting dead weight.

## Release

`release.sh` cuts a phel-doom release: validate semver and preflight, move the `## [Unreleased]` CHANGELOG block into a dated version section, build a self-contained `phel-doom.phar`, smoke-test it, commit, tag `vX.Y.Z`, push branch and tag.

Do not invoke it raw. Use the `/release` skill, which wraps this script and verifies the published phar + GitHub release.

```
./tools/release.sh [version] [--dry-run] [--force] [--name "Release name"]
```
