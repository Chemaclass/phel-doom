# Save / load

`F5` saves and `F9` loads mid-level (#63). Both use slot 1 (`quick-save-slot`). The world map round-trips through JSON with a tagged codec in `src/io/savegame.phel`.

Files live at `$HOME/.phel-doom/saves/slot-<n>.json`; the directory is created on first save. The API accepts slots 1-9 (`max-slots`), but no key reaches slots 2-9 yet.

## Flow

`handle-save-load` runs in the game loop after `tick-world`, never inside the pure tick. It stamps a 1.2 s HUD cue: `SAVED`, `SAVE FAILED`, `LOADED` or `NO SAVE`.

A load replaces the whole world, except that `adopt-loaded-world` keeps the live `:settings` and `:settings-cursor` (#279). Settings are session preference, not run state; restoring the saved copy would revert them, and the next resume would persist the stale copy.

## Codec

Phel types map to JSON arrays:

- keyword: `["$k", "name"]`
- set: `["$s", [items...]]`
- map: `["$m", {kw-name: val...}]` (every world key is a keyword)
- vector: `[items...]`
- scalar: itself

`encode` and `decode` are pure and tested for round-trip equality. `decode` checks the `$m` payload at every level, so a malformed nested map returns nil instead of throwing out of the play loop.

## Dropped fields

`world->savestring` removes these before encoding:

| Keys | Why | On load |
|------|-----|---------|
| `:pgrid`, `:light-grid` | Derived from `:grid`. A PHP array would come back as a Phel vector and break `php/aget` in render. | `rebuild-pgrid` |
| `:visited` | Fog-of-war map | Empty; re-reveals as the player moves |
| `:moves` | Transient hold counters. Old saves stored frame counts that the seconds-based decay would read as ~15 s of drift. | `empty-moves` |
| `:settings`, `:settings-cursor` | Session preference (#279) | Live values kept |
| `:pause-confirm` | An armed Restart belongs to the session that asked (#454) | Absent |
| `:msg-text`, `:msg-secs` | A load must not show "Picked up a heart." (#456) | Absent |
| `:hint-secs`, `:hints-seen` | Someone loading a save is past the first-run hints (#467) | Absent |

## Versioning

`world->savestring` wraps the world in `{"version": N, "world": ...}`. `savestring->world` returns nil for malformed JSON, a version mismatch, or a `world` that is not an encoded map; the HUD then shows `NO SAVE`. Bump `save-version` (currently 1) on an incompatible world change.

Old saves still load inside version 1: `state/backpack-level` reads a pre-#68 `:backpack?` boolean as level 1. Do not remove that path without bumping the version.
