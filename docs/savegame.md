# Save / load

Mid-level F5 (save) / F9 (load) quick-save to slot 1 (issue #63). World map round-trips through JSON via tagged codec (`src/io/savegame.phel`).

## Codec

Phel types map to JSON arrays:
- keyword: `["$k", "name"]`
- set: `["$s", [items...]]`
- map: `["$m", {kw-name: val...}]` (world keys are all keywords)
- vector: `[items...]`
- scalar: itself (unchanged)

`encode` and `decode` are pure, tested for round-trip equality.

## Dropped fields

- `:pgrid`: PHP-array mirror of `:grid` (rebuilt on load)
- `:light-grid`: per-cell room-light bias derived from `:grid` (#418; rebuilt on load by `rebuild-pgrid`). Serializing it would round-trip a PHP array back as a Phel vector and break the per-column `php/aget` in render.
- `:visited`: fog-of-war map (reset empty, re-revealed as player moves)

## Versioning

`world->savestring` wraps encoded world in `{"version": N, "world": ...}`. `savestring->world` refuses version mismatch or malformed JSON, returns nil (HUD shows `NO SAVE` cue). Bump `save-version` on incompatible world changes.

## Slots

Slots 1-9 valid. File IO in game loop (never in pure `tick-world`). HUD cues: `SAVED` / `LOADED` / `NO SAVE`.
