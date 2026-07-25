# phel-doom internals

Per-subsystem docs, each linked to source files and key functions.

## Map

| Topic | File |
|---|---|
| New to Phel (from Clojure/PHP) | [coming-from-clojure-or-php.md](coming-from-clojure-or-php.md) |
| Player guide (controls, pickups, weapons) | [gameplay.md](gameplay.md) |
| Feature catalogue | [features.md](features.md) |
| Module layout + rules | [architecture.md](architecture.md) |
| Per-frame transitions | [game-loop.md](game-loop.md) |
| World + player data | [state.md](state.md) |
| Grid + cells | [map.md](map.md) |
| Raycaster | [raycaster.md](raycaster.md) |
| ANSI render | [rendering.md](rendering.md) |
| Enemies + AI | [monsters.md](monsters.md) |
| Combat + hitscan | [combat.md](combat.md) |
| Levels + boss arena | [level-system.md](level-system.md) |
| Terminal input | [input.md](input.md) |
| Audio | [audio.md](audio.md) |
| Scores | [scores.md](scores.md) |
| WAD parser | [wad-parser.md](wad-parser.md) |
| Performance | [performance.md](performance.md) |
| Contributing | [contributing.md](contributing.md) |

## Quick start: new contributor

1. `coming-from-clojure-or-php.md` - read Phel fast if you know either
2. `architecture.md` - layout + dependency rules
3. `game-loop.md` - frame-to-frame flow
4. `raycaster.md` + `rendering.md` - how pixels reach the screen
5. `contributing.md` - dev workflow + Phel quirks
6. Pick subsystems as needed

## File layout

```
src/main.phel                ; CLI entry (phel.cli)
src/commands/play.phel       ; tick-world + run-levels
src/core/                    ; pure logic (no IO)
  state.phel                 world + player + stats
  map.phel                   grid + procgen + cells
  engine.phel                raycaster: cast-frame, cast-ray
  physics.phel               player move + physics tick
  combat.phel                hitscan + damage
  enemy.phel                 spawn + step + respawn
  enemy_ai.phel              idle/wander/aware/hunting/pain
  enemies.phel               enemy catalog + stats
  level.phel                 level 1-10 + build-world
  weapons.phel               weapon catalog + ammo state
  projectile.phel            enemy fireballs: spawn + march + impacts
  perf.phel                  big-screen perf checks
  difficulty.phel            easy/normal/hard/nightmare
  settings.phel              options model (volume, defaults)
  rng.phel                   deterministic seeding
src/glue/                    ; pure wiring (core + io)
  controls.phel              bytes to move commands
src/io/                      ; side effects
  input.phel                 stty + kitty protocol
  render.phel                ANSI emit + overlays
  sound.phel                 afplay/paplay shell-out
  scores.phel                JSON persistence
  settings.phel              options load/save (JSON)
  savegame.phel              game state save/load
  music.phel                 background OST loop
  demo.phel                  --record / --demo run capture + replay
  wad.phel                   WAD parser
tests/                       ; unit tests (mirrors src/)
```

Rules: `core/` is pure, same in tests as prod. `io/` has side effects. `glue/` wires both, stays pure.
