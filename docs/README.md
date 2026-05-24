# phel-doom internals

One doc per subsystem. Each points to its source files + functions.

## Map

| Topic | File |
|---|---|
| Feature catalogue (what the game does) | [features.md](features.md) |
| Module layout + dependency rules | [architecture.md](architecture.md) |
| Per-frame state transition | [game-loop.md](game-loop.md) |
| World + player data model | [state.md](state.md) |
| Grid + cell semantics | [map.md](map.md) |
| Raycaster: how walls get distances | [raycaster.md](raycaster.md) |
| ANSI render pipeline | [rendering.md](rendering.md) |
| Enemies: chase AI, faces, fades, aggro | [monsters.md](monsters.md) |
| Hitscan + damage + respawn | [combat.md](combat.md) |
| 5-level progression | [level-system.md](level-system.md) |
| Terminal input | [input.md](input.md) |
| Audio | [audio.md](audio.md) |
| High-scores persistence | [scores.md](scores.md) |
| DOOM .wad parser | [wad-parser.md](wad-parser.md) |
| Hot-loop optimizations | [performance.md](performance.md) |
| Contributing + Phel gotchas | [contributing.md](contributing.md) |

## Reading order for newcomers

1. `architecture.md`: what's where + why
2. `game-loop.md`: per-frame story end to end
3. `raycaster.md` + `rendering.md`: pixels on screen
4. `contributing.md`: dev workflow, test conventions, Phel quirks
5. Pick any subsystem as needed

## Quick orientation

```
src/main.phel                          ; CLI entrypoint
src/commands/play.phel                 ; tick-world + run-levels lifecycle
src/modules/core/                      ; pure logic, no IO
  state.phel       world data model
  map.phel         grid + random arena gen
  engine.phel      raycaster (cast-frame, cast-ray)
  physics.phel     player movement + counter decay
  combat.phel      hitscan + damage + heat/jam + knockback + berserk/invuln timers
  enemy.phel       chase AI + shoot resolution + respawn
  level.phel       5-level config catalog + build-world (pickups, keycards, lock)
  weapons.phel     3-weapon catalogue + per-weapon ammo state + switch
  difficulty.phel  easy/normal/hard/nightmare multipliers
src/modules/io/                        ; side effects only
  input.phel       stty raw mode + kitty protocol opt-in
  render.phel      frame->string + paint-* overlays + ANSI
  sound.phel       afplay/paplay/aplay shell-out
  scores.phel      $HOME/.phel-doom-scores.json
  wad.phel         WAD lump-directory parser
src/modules/glue/                      ; wires core + io
  controls.phel    bytes -> :moves counters + rising-edges
tests/                                 ; mirrors src/
```

Hot-loop boundary: anything under `core/` is pure data-in / data-out
and runs the same way in tests as in production. `io/` is where
side effects live; mock-free testability ends there. `glue/` reads
from both but stays effect-free (it's a pure byte → world transform).
