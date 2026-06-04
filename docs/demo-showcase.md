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

`--phase` / `-p` defaults to 1 and is clamped to 1..4. God mode, the
split-screen layout, and the full (no fog) map are always on. `Q` quits.

## The split layout

Every phase renders in a side-by-side layout: the left half is the normal 3D
raycast view (cast at half the column count), the right half is a full-height
2D top-down map of the level. It is driven by the `:split-map?` world flag,
which `render!` honours by dispatching to `split-frame->string`
(`src/io/render/main.phel`). The map panel itself is `split-map-rows`
(`src/io/render/hud.phel`), a full-height variant of the corner minimap.

This is distinct from the M-key corner minimap (`:show-map`), which is
unchanged.

## The phases

| Phase | Arena? | Enemies | Weapon | Reveals |
|-------|--------|---------|--------|---------|
| 1 | empty room (outer walls only) | no | hidden | the pure raycaster |
| 2 | empty room | no | pistol | firing + weapon HUD |
| 3 | empty room | yes | pistol | spawn + AI |
| 4 | real generated geometry | yes | pistol | interior cover walls |

The interior cover walls ("brinks") are deliberately the LAST reveal, so
phases 1-3 flatten the level to an empty arena and only phase 4 keeps the
real generated maze.

## How a phase is applied

`phel-doom.demo.phases/apply-phase` (`src/demo/phases.phel`) is a pure
`world -> world` transform:

- **arena** (phases 1-3): `flatten-interior` rewrites the grid so only the
  outer border stays wall, everything inside becomes floor, then rebuilds
  `:pgrid` so the raycaster's hot-path view stays in sync.
- **enemies** (off until phase 3): `with-enemies world []`.
- **weapon** (off in phase 1): stamps `:demo-hide-weapon?`, which makes
  `combat/tick-shooting` swallow the trigger (no shot, no dry-fire click) and
  `render!` skip the gun sprite (`paint-pistol-hud`).
- **pickups** (off in every phase): all pickup-spawn vectors cleared so the
  arena stays clean.

The transform stamps `:split-map?`, `:full-map?`, `:god?`, and `:demo-phase`.

## Wiring

- `src/demo/phases.phel` - the pure phase data + transform (unit-tested in
  `tests/demo/phases-test.phel`). The only demo-specific logic lives here, so
  the showcase stays out of the game code.
- `src/commands/demo.phel` - the thin CLI command; parses `--phase` and calls
  `run-demo-session`.
- `src/commands/play.phel` - `run-demo-session` (menu-less god + split run) and
  `run-levels`' `demo-phase` parameter, which applies the transform.
- `src/main.phel` - registers `demo-command`.
