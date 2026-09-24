# Demo showcase (tech-talk mode)

A progressive, single-command reveal of the game, built for live talks. Not to be confused with [demo record/replay](demo.md) (`--record` / `--demo`).

The showcase reuses the real engine and play loop. It adds one pure per-phase world transform, applied right after `build-world`. The demo IS the game (same raycaster, same `tick-world`, same render), never a fork.

## Running it

```bash
vendor/bin/phel run phel-doom.main demo --phase 1   # bare raycaster
vendor/bin/phel run phel-doom.main demo --phase 2   # + the pistol
vendor/bin/phel run phel-doom.main demo --phase 3   # + enemies
vendor/bin/phel run phel-doom.main demo --phase 4   # + interior cover walls
```

`--phase` / `-p` defaults to 1. Any value outside 1..4 prints an error and exits non-zero. God mode, every weapon, and the full corner minimap (no fog) are always on. Mouse reporting is off, so a screencast keeps the pointer. `Q` quits.

## The phases

| Phase | Arena | Enemies | Weapon | Sound | Reveals |
|-------|-------|---------|--------|-------|---------|
| 1 | open room + central pillar | no | hidden | off | the pure raycaster |
| 2 | open room + central pillar | no | pistol | off | firing + weapon HUD |
| 3 | open room + central pillar | yes | pistol | on | spawn + AI |
| 4 | real generated geometry | yes | pistol | on | interior cover walls |

The interior cover walls come last by design: phases 1-3 flatten the level, and only phase 4 keeps the real maze. Every phase shows the 2D minimap next to the 3D view using existing flags only, so the demo adds no render path.

## How a phase is applied

`apply-phase` (`src/demo/phases.phel`) is a pure `world -> world` transform:

- **arena** (phases 1-3): `flatten-interior` keeps the outer border, turns the inside to floor, and stamps a 3x3 pillar in the centre (`pillar-half`) so there is a wall to render. The pillar is carved around the player and any enemy, and skipped on grids under 8 a side. `:pgrid` is rebuilt to match.
- **enemies** (from phase 3): `with-enemies world []` until then.
- **weapon** (from phase 2): phase 1 sets `:hide-weapon?`. `combat/tick-shooting` then swallows the trigger and render skips the gun sprite.
- **pickups** (never): every pickup-spawn vector is cleared.

It sets only generic flags the game already honours: `:show-map` + `:full-map?` (minimap, no fog), `:god?`, `:hide-weapon?`, `:hide-level-name?` (while there are no enemies), `:sound-on` (only with enemies), `:intro-secs 0`, and `:armory-reserve` 99 (the run has every weapon, and 99 fits the HUD). `:demo-phase` is a diagnostic marker nothing branches on. Core knows nothing of the demo.

## Wiring

- `src/demo/phases.phel`: phase data + transform, tested in `tests/demo/phases-test.phel`.
- `src/commands/demo.phel`: the CLI command. Validates `--phase`, calls `run-demo-session`.
- `src/commands/play.phel`: `run-demo-session` (menu-less god + full-map + armory run) and the `demo-phase` parameter of `run-levels`, which applies the transform.
- `src/main.phel`: registers `demo-command`.
