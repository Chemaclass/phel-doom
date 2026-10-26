# Save / load

`F5` saves and `F9` loads during a level (#63). Both use slot 1 (`quick-save-slot`). `src/io/savegame.phel` encodes and restores the world as tagged JSON.

Saves live at `$HOME/.phel-doom/saves/slot-<n>.json`. The directory is created on the first save. The API accepts slots 1-9 (`max-slots`); the keys use slot 1.

## Flow

`handle-save-load` runs in the game loop after the pure `tick-world` and shows a 1.2 s HUD cue: `SAVED`, `SAVE FAILED`, `LOADED` or `NO SAVE`.

A load replaces the world, while `adopt-loaded-world` keeps the live `:settings` and `:settings-cursor` (#279). This preserves session preferences and prevents the next resume from saving stale settings.

## Codec

Phel types map to JSON arrays:

- keyword: `["$k", "name"]`
- set: `["$s", [items...]]`
- map: `["$m", {kw-name: val...}]` (every world key is a keyword)
- vector: `[items...]`
- scalar: itself

`encode` and `decode` are pure and tested for round-trip equality. `decode` checks each `$m` payload and returns nil for a malformed nested map rather than throwing from the play loop.

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

Version 1 still loads old saves: `state/backpack-level` reads a pre-#68 `:backpack?` boolean as level 1. Do not remove that path without bumping the version.
