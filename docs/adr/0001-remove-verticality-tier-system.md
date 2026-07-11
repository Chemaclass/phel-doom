# ADR 0001: Remove the verticality / tier system (again)

- Status: Accepted
- Date: 2026-07-11
- Deciders: maintainer (Chemaclass)
- Supersedes: nothing (first ADR)
- Related: epic #375 (re-add), issue #325 / PR #328 (first removal, shipped 0.16.0)

## Context

phel-doom is a terminal raycaster. Twice now it has grown a full
"verticality" layer (variable floor and ceiling heights, staircases,
step-up physics, tier-aware rendering and AI) and twice the maintainer has
judged it a net negative for the play experience.

- First build: removed in a deliberate full flat reset (issue #325 / PR #328,
  shipped `0.16.0`, 2026-06-27). The look up/down pitch aim was ruled a camera
  shear, not verticality, and kept.
- Second build: epic #375 re-added it from scratch as a grid-cell heightmap
  (NOT DOOM sector polygons). Fully landed across ~13 feature PRs (#368-#405,
  #416b) plus follow-ups. This is the version this ADR removes.

Why it deteriorates the experience (maintainer judgment, both times):

1. Stairs are hard to read in an ANSI raycaster. Treads collapse to a single
   row at low view angles; without a strong lit lip per step the geometry
   reads as a flat smear, not steps. Legibility is fragile and view-angle
   dependent.
2. The correctness surface is large and cross-cutting: cast, render, physics,
   combat aim, enemy pathing, sprite occlusion, and save all have to agree on
   the height model. Each new render fix (near-floor recession #416b, feet
   anchoring #395, occlusion #394) chased a regression the previous one
   exposed.
3. The gameplay payoff is thin: only one shipped level (L2) was tiered; every
   other level stayed deliberately flat to preserve the byte-identical
   invariant (see below). The cost/benefit did not land.

The maintainer wants the complexity out of the game today, with this ADR as
the durable record so a third attempt (if ever) starts from the learnings,
not from zero.

## Decision

Remove the entire verticality / tier machinery. Collapse the game back to a
single flat floor (z = 0) and a full-height ceiling (cz = 1.0) everywhere.

Keep (explicitly NOT verticality):

- Look up/down **pitch** (the #231/#240/#243 camera horizon shear) and the
  screen-projection vertical aim gate it drives on flat sprites. This is a
  camera effect; it works with no height data and was kept the first time too.
- View/head bob (#411), weapon idle bob + sway (#412), weapon-fire extralight
  (#413). Tagged "epic #375/#408" but they ride `:pitch` / `:bob-phase`, not
  `fz` / `cz`. No height dependency.

Remove:

- Per-cell height data: `:fz-grid` / `:cz-grid`, the `:pfz` / `:pcz` hot
  arrays, and the `:fz-flat?` / `:cz-flat?` build flags.
- Map kernels: `fz-step`, `quantize-fz`, `floor-z`, `ceiling-z`,
  `player-height`, `headroom-clears?`, layout digit/lowercase parsing.
- Cast: the multi-span DDA (`:spans` floor risers, `:uspans` ceiling drops)
  and `cast-shot-dist` (shoot-through-lintel). Collapse to the single-span
  `cast-ray` legacy march.
- Physics: step-up (`step-clears?`) and headroom gate.
- Combat: the tier-z anchor on the aim gate (enemy `fz` / `eye-z`); keep the
  flat #243 pitch gate.
- Enemy: BFS stair flow-field (`chase-dist-field` / `chase-waypoint`), the
  climb gate, and tier feet anchoring. Collapse to the greedy flat chase.
- Render: riser / tier-top / upper-wall painters, tier palettes, sprite
  crop-by-tier occlusion, eye-z floor recession. Collapse to the flat
  single-floor path (`eye-z = 0.5`, `floor-cast-k`).
- Content: the L2 staircase showcase becomes a flat room keeping its identity.
- Projection: `floor-cast-num`, `tier-top-row-dist`, `ceiling-top-row-dist`.

Player `:z` field is removed. Player is always at floor 0.

## Consequences

- Codebase shrinks by the whole epic-#375 surface; the flat path was always
  the else-arm of every tier branch, so collapsing is mechanical.
- Old tiered saves still load: they carry ignored `:fz-grid` / `:cz-grid`
  keys, dropped on next rebuild. No save-version bump (mirrors the add, which
  also took none).
- Flat levels are byte-identical before and after removal (the invariant that
  gated the whole epic guarantees this); their golden hashes do not move.

## Learnings (read these before any third attempt)

### Model choice

- Use a **grid-cell heightmap** (per integer cell `fz` floor height + `cz`
  ceiling height, quantized to 0.25 steps), NOT DOOM sector polygons. The grid
  fits the raycaster's DDA naturally: each cell crossing is a potential
  riser/drop event.
- Authoring lived in the ASCII layout: digits `1` / `2` / `3` = fz 0.25 / 0.5
  / 0.75 (max 0.75 so a floor never meets the cz=1.0 ceiling); chars `a` / `b`
  / `c` = cz 0.75 / 0.5 / 0.25. A raised `fz` under a lowered `cz` is a window
  gap.

### The byte-identical-flat invariant (the load-bearing idea)

- Every tier feature MUST be a no-op on flat levels, verified byte-for-byte.
  This is what let the epic ship incrementally without regressing the 10 flat
  campaign levels. Mechanisms:
  - Build-time `:fz-flat?` / `:cz-flat?` flags select a legacy single-span DDA
    march on flat worlds; the multi-span march only runs where height varies.
  - The eye-height floor-cast `floor-cast-num 70.0 0.5 0.0` equals the baked
    flat constant `floor-cast-k` (17.5) to the bit, so `eye-z = 0.5` collapses
    to the flat floor path exactly.
  - `fz-step == player-height == 0.25`: a raised fz-0.75 tier under a cz-1.0
    ceiling still has 0.25 clearance, so every flat-ceiling level stays
    walkable and shootable. This identity is what kept the system
    behaviour-neutral on shipped content.

### Perf rule (generalizes beyond verticality)

- Any per-step cost added **unconditionally** shows up on every frame of every
  level, flat or not. Gate it behind a build flag or inline it to the flat
  constant. This is why the flat flags and the baked `floor-cast-k` exist.

### Testing (do NOT repeat the md5 mistake)

- Golden md5 frame hashes are **OS-fragile** near row boundaries: macOS vs
  Linux libm rounding diverges, and the `cz == eye-z` (0.5) knife-edge flips a
  row. Test tiered scenes with **differ-from-flat + determinism assertions**
  (same input twice = same output; tiered output differs from flat), NOT md5
  pins. md5 pins are fine for flat goldens only.
- `^:pure` inlining regressions do not show in golden hashes (they crash in
  non-render paths). Always run the FULL suite on a `^:pure` change.

### Render legibility (the hard part)

- Paint EVERY riser per column plus a **lit leading lip** on each step, not
  just the nearest riser. The lip is what makes stairs legible; without it
  treads collapse at low angle. Painting only the nearest riser was the root
  cause of the #318 "floating enemies / invisible stairs" bug.
- Sprite occlusion by tiers is **crop, not squish**: keep the full sprite box
  in the size fields (they drive sprite-y), and gate painting on a *separate*
  visible-window `[crop-top, crop-bot)`. Squishing the box distorts the
  sprite (learned in #315 for vertical clip, same shape here).
- Enemy feet anchor to their cell `fz` via a bare `:pfz` aget + `eye-z`; the
  projection carries `:cell-x` / `:cell-y` so the zone pass can look up height.

### Combat + AI

- Two separable vertical-aim layers: the #243 screen-projection pitch gate
  (works on flat, is camera pitch) and the #396 tier-z anchor on top of it
  (`enemy-fz` / `eye-z`). The first stays after removal; only the second is
  tier code.
- Stair pathing needs a **BFS flow-field** flooded from the player over the
  one-`fz-step`-climbable graph (#405). The greedy "aim within ±135deg"
  chase stalls against a tall multi-step tier face. Build the field once per
  frame and share it across enemies; flat worlds skip it and keep the greedy
  chase.

### Process hazards (parallel-agent work)

- Worktree agent branches can leak into the main checkout; verify
  `git branch --show-current` before any `reset --hard`, recover lost work
  from dangling stashes via `git fsck --lost-found`.
- Parallel-agent worktree Bash cwd can land in the WRONG sibling worktree;
  always `cd "$ABS_WORKTREE"` first and stage only your own files.
- When a long-running removal branch forks before another feature merges,
  reconcile by merging main IN, do not assume a clean replay (the #324 reticle
  vs #328 flat-reset conflict).

## How to re-add (if a third attempt is ever wanted)

1. Reinstate the grid heightmap: `:fz-grid` / `:cz-grid` on the world, `:pfz` /
   `:pcz` hot arrays, `:fz-flat?` / `:cz-flat?` build flags, and the layout
   digit/lowercase parsing. Keep the 0.25 quantum and the
   `fz-step == player-height` identity.
2. Add the multi-span DDA behind the flat flags (legacy march stays the flat
   fast-path). Emit `:spans` (floor risers) and `:uspans` (ceiling drops).
3. Render: multi-step riser painter with lit lips + perspective treads; tier
   palettes; crop-based sprite occlusion; eye-z floor recession that collapses
   to `floor-cast-k` at `eye-z = 0.5`.
4. Physics step-up + headroom; combat tier-z anchor on the flat pitch gate;
   enemy BFS flow-field chase.
5. Author ONE tiered showcase level; keep every other level flat and prove
   byte-identical.
6. Test with differ-from-flat + determinism, never md5 pins on tiered frames.
   Full-suite every `^:pure` change.

Start from git history: the removed implementation is recoverable from the
epic-#375 PRs (#368-#405, #416b) and the commit that this ADR ships with.
