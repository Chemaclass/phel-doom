# phel-doom internals

Per-subsystem docs. Each one links to its source files and key functions.

## Map

| Topic | File |
|---|---|
| New to Phel (from Clojure/PHP) | [coming-from-clojure-or-php.md](coming-from-clojure-or-php.md) |
| Player guide (controls, pickups, weapons) | [gameplay.md](gameplay.md) |
| Feature catalogue | [features.md](features.md) |
| Module layout + dependency rules | [architecture.md](architecture.md) |
| Per-frame transitions | [game-loop.md](game-loop.md) |
| World + player data | [state.md](state.md) |
| Grid + cells | [map.md](map.md) |
| Raycaster | [raycaster.md](raycaster.md) |
| ANSI render | [rendering.md](rendering.md) |
| Enemies + AI | [monsters.md](monsters.md) |
| Combat + hitscan | [combat.md](combat.md) |
| Levels + boss arena | [level-system.md](level-system.md) |
| Terminal input | [input.md](input.md) |
| Audio (sfx + music) | [audio.md](audio.md) |
| Settings page | [settings.md](settings.md) |
| Save / load | [savegame.md](savegame.md) |
| High scores | [scores.md](scores.md) |
| Demo record / replay | [demo.md](demo.md) |
| Tech-talk showcase (`demo` command) | [demo-showcase.md](demo-showcase.md) |
| WAD parser | [wad-parser.md](wad-parser.md) |
| Performance | [performance.md](performance.md) |
| Contributing | [contributing.md](contributing.md) |
| Decision records | [adr/0001-remove-verticality-tier-system.md](adr/0001-remove-verticality-tier-system.md) |

## Reading path for a new contributor

1. [coming-from-clojure-or-php.md](coming-from-clojure-or-php.md): Phel for Clojure or PHP readers.
2. [architecture.md](architecture.md): layout and dependency rules.
3. [game-loop.md](game-loop.md): frame-to-frame flow.
4. [raycaster.md](raycaster.md) + [rendering.md](rendering.md): how pixels reach the screen.
5. [contributing.md](contributing.md): dev loop, gates, Phel quirks.

Then pick subsystems as needed.

## File layout

```
src/main.phel         CLI entry (phel.cli): play + demo commands
src/commands/         demo, play (game loop, tick-world, run-levels)
src/core/             pure logic: combat, difficulty, enemies, enemy, enemy_ai,
                      engine, format, level, light, loot, map, perf, physics,
                      pickups, projectile, projection, rng, settings, state,
                      version, weapons
src/demo/             phases (showcase world transforms)
src/glue/             controls (key bytes -> move commands)
src/io/               side effects: demo, input, music, render, savegame,
                      scores, settings, sound, sound_data, wad
src/io/render/        buffer, enemy_sprite, frame_math, hud, main, paint,
                      palette, screens, sprites, plus baked data
                      (enemy_sprites_data, wall_texture_data, weapon_sprites_data)
tests/<layer>/        mirrors src/, plus tests/bench for `composer bench`
```

What each file does and which layer may require which: [architecture.md](architecture.md).
