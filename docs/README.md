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
| 10-level progression + L10 boss arena | [level-system.md](level-system.md) |
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
src/main.phel                ; CLI entrypoint (phel.cli)
src/commands/play.phel       ; tick-world + run-levels lifecycle
src/core/                    ; pure logic, no IO
  state.phel       world data model
  map.phel         grid + procgen + cell semantics
  engine.phel      raycaster (cast-frame, cast-ray)
  physics.phel     player movement + counter decay + stamina
  combat.phel      hitscan + damage + heat/jam + knockback + berserk/invuln
  enemy.phel       spawn + chase step + shoot resolution + respawn
  enemy_ai.phel    AI state machine (dormant/wander/aware/hunting/pain/attacking)
  enemies.phel     enemy-types catalog (visuals + default HP per kw)
  level.phel       10-level catalog + build-world (procgen or hand-authored)
  weapons.phel     weapon catalog + per-weapon ammo state + switch
  perf.phel        big-screen perf-mode predicates
  difficulty.phel  easy/normal/hard/nightmare multipliers
src/glue/                    ; wires core + io, stays pure
  controls.phel    bytes -> :moves counters + rising edges
src/io/                      ; side effects only
  input.phel       stty raw mode + kitty protocol opt-in
  render.phel      frame->string + paint-* overlays + ANSI
  sound.phel       afplay/paplay/aplay shell-out
  scores.phel      $HOME/.phel-doom-scores.json
  wad.phel         WAD lump-directory parser
tests/                       ; mirrors src/
```

Hot-loop boundary: `core/` is pure data-in / data-out, same in tests as prod. `io/` is where side effects live. `glue/` reads both but stays effect-free (pure byte → world transform).
