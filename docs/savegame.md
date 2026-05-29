# Save / load

`src/io/savegame.phel`. Mid-level quick-save (issue #63). The immutable
`:world` map is pure data, so it round-trips through JSON.

## Why a tagged codec

Phel keywords / sets / vectors / maps have no native JSON form, and
`php/serialize` mangles Phel's internal objects (it does not round-trip).
So `encode` / `decode` are a small tagged codec:

| Phel value | Encoded |
|---|---|
| keyword | `["$k", "name"]` |
| set | `["$s", [items...]]` |
| map | `["$m", {kw-name: val, ...}]` (all world map keys are keywords) |
| vector | `[items...]` |
| number / bool / string / nil | itself |

`encode` / `decode` are pure (no IO) and unit-tested for round-trip
equality, including empty collections.

## What is dropped

- `:pgrid` - the derived PHP-array mirror of `:grid`. Rebuilt from the
  grid on load via `state/rebuild-pgrid`.
- `:visited` - the fog-of-war PHP array. Reset empty on load; the fog
  re-reveals as the player walks.

Everything else in `new-world` is serialised as-is.

## Format + versioning

`world->savestring` wraps the encoded world in `{"version": N, "world":
...}` and `json_encode`s it. `savestring->world` refuses a save whose
`version` doesn't match `save-version` (or malformed JSON), returning
`nil` so the caller surfaces a friendly miss instead of loading a broken
world. Bump `save-version` whenever the world shape changes
incompatibly.

## Files + slots

`save-game! world slot` writes `$HOME/.phel-doom/saves/slot-<n>.json`
(creating the dir on first use); `load-game slot` reads it back or
returns `nil`. Slots 1-9 are valid (`valid-slot?`).

## In-game keys

`commands/play` wires **F5** -> save, **F9** -> load to slot 1
(`quick-save-slot`). The file IO runs in `game-loop` (never the pure
`tick-world`): F5 saves the post-tick world; F9 swaps the whole world
for the loaded one. Both stamp a brief `:save-flash-secs` + `:save-flash-msg`
HUD cue (`SAVED` / `LOADED` / `NO SAVE`) that `render/paint-save-flash`
paints centred near the top and `tick-world` decays.
