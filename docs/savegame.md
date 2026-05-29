# Save / load

`src/io/savegame.phel`. Mid-level F5/F9 quick-save (issue #63). World map round-trips through JSON via small tagged codec.

## Tagged codec

Phel keywords / sets / vectors have no native JSON form:
- keyword -> `["$k", "name"]`
- set -> `["$s", [items...]]`
- map -> `["$m", {kw-name: val...}]` (all world map keys are keywords)
- vector -> `[items...]`
- scalar -> itself

`encode` / `decode` are pure, unit-tested for round-trip equality.

## Dropped fields

- `:pgrid`: derived PHP-array mirror of `:grid`, rebuilt on load
- `:visited`: fog-of-war PHP array, reset empty on load and re-revealed

## Versioning

`world->savestring` wraps the encoded world in `{"version": N, "world": ...}` and JSON-encodes. `savestring->world` refuses a save with mismatched version or malformed JSON, returning `nil` (caller surfaces `NO SAVE` cue). Bump `save-version` on incompatible world shape changes.

## Slots + keys

F5 (save) / F9 (load) to slot 1 (`quick-save-slot`). File IO in `game-loop` (never pure `tick-world`). Slots 1-9 valid. HUD cue (`SAVED` / `LOADED` / `NO SAVE`) stamped on action.
