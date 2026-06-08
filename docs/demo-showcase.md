# Demo showcase (tech-talk mode)

A progressive, single-command reveal of the game built for live talks. Not
to be confused with [demo record/replay](demo.md) (the `--record` / `--demo`
deterministic playback feature).

The showcase reuses the real engine and the real play loop end to end. The
only thing it adds is a pure per-phase world transform applied right after
`build-world`, so the demo IS the game (same raycaster, same `tick-world`,
same render) - never a fork.

## Running it

```bash
phel run phel-doom.main demo --phase 1   # bare raycaster
phel run phel-doom.main demo --phase 2   # + the pistol
phel run phel-doom.main demo --phase 3   # + enemies
phel run phel-doom.main demo --phase 4   # + interior cover walls
```

`--phase` / `-p` defaults to 1 and is clamped to 1..4. God mode and the
corner minimap (shown, full / no fog) are always on. `Q` quits.

## The 2D map

Every phase renders as a normal full-screen 3D raycast with the corner
minimap turned on, so the 2D top-down view sits alongside the 3D one. This
reuses the existing game features only: `:show-map` (the M-key minimap toggle)
plus `:full-map?` (the `--full-map` no-fog reveal). The demo adds no render
path of its own - it just flips flags the game already honours.

## The phases

| Phase | Arena? | Enemies | Weapon | Reveals |
|-------|--------|---------|--------|---------|
| 1 | open room + central pillar | no | hidden | the pure raycaster |
| 2 | open room + central pillar | no | pistol | firing + weapon HUD |
| 3 | open room + central pillar | yes | pistol | spawn + AI |
| 4 | real generated geometry | yes | pistol | interior cover walls |

The interior cover walls ("brinks") are deliberately the LAST reveal, so
phases 1-3 flatten the level to an open arena and only phase 4 keeps the
real generated maze.

## How a phase is applied

`phel-doom.demo.phases/apply-phase` (`src/demo/phases.phel`) is a pure
`world -> world` transform:

- **arena** (phases 1-3): `flatten-interior` rewrites the grid so the outer
  border stays wall, everything inside becomes floor, and a small 3x3 pillar
  is stamped in the centre (`pillar-half`) so the bare raycaster has a wall to
  render. The pillar is carved around the player and any enemy so a fresh-seed
  spawn is never trapped, and is skipped on grids under 8 a side. Rebuilds
  `:pgrid` so the raycaster's hot-path view stays in sync.
- **enemies** (off until phase 3): `with-enemies world []`.
- **weapon** (off in phase 1): sets the generic `:hide-weapon?` flag, which
  makes `combat/tick-shooting` swallow the trigger (no shot, no dry-fire click)
  and the render layer skip the gun sprite. Core knows nothing of the demo - it
  just honours "no weapon in hand".
- **pickups** (off in every phase): all pickup-spawn vectors cleared so the
  arena stays clean.

The transform sets only generic flags the game already honours - `:show-map` +
`:full-map?` (the minimap, full), `:god?`, `:hide-weapon?`, `:hide-level-name?` -
plus `:demo-phase`, a diagnostic marker nothing branches on.

## Wiring

- `src/demo/phases.phel` - the pure phase data + transform (unit-tested in
  `tests/demo/phases-test.phel`). The only demo-specific logic lives here, so
  the showcase stays out of the game code.
- `src/commands/demo.phel` - the thin CLI command; parses `--phase` and calls
  `run-demo-session`.
- `src/commands/play.phel` - `run-demo-session` (menu-less god + full-map run)
  and `run-levels`' `demo-phase` parameter, which applies the transform.
- `src/main.phel` - registers `demo-command`.
