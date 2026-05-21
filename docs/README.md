# phel-doom internals

One doc per subsystem. Each points to its source files + functions.

## Map

| Topic | File |
|---|---|
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

## Reading order for newcomers

1. `architecture.md`: what's where + why
2. `game-loop.md`: per-frame story end to end
3. `raycaster.md` + `rendering.md`: pixels on screen
4. Pick any subsystem as needed
