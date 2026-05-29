# Map / grid

`src/core/map.phel`. Grid data shape, cell semantics, random-map generation, lookup helpers.

## Cells

```phel
(def cell-floor     0)  ; walkable empty
(def cell-wall      1)  ; solid wall, blocks rays and player
(def cell-door      2)  ; unlocked door: passable trigger, blocks rays only
(def cell-door-blue 3)  ; blue-keyed door: blocks until player holds :blue keycard
(def cell-door-red  4)  ; red-keyed door: blocks until player holds :red keycard
(def cell-door-boss 5)  ; boss-locked door: blocks until player kills the boss (grants synthetic :boss keycard)
(def cell-secret    6)  ; hidden passage: looks + blocks like a wall until the player reveals it with F
(def cell-switch-off 7) ; inactive switch: blocks like a wall, F-press flips to cell-switch-on + mutates target cells
(def cell-switch-on  8) ; activated switch: same blocking + a second F-press reverts to cell-switch-off + targets
```

Every cell is one of these ints. Constants exported so no module uses raw `0/1/2/3/4/5` literals. `(= cell-door (cell g x y))` reads as purpose.

`lock-colours` maps locked-door cell values to keycard keywords:
```phel
{3 :blue   4 :red   5 :boss}
```

`:boss` is a synthetic "colour" - no physical keycard item ever spawns for it; the kw is granted automatically by `combat/maybe-unlock-boss-door` when the boss is killed on a `:door-lock :boss` level.

## Lookup helpers

```phel
(cell  grid x y)   ; cell value; out-of-bounds = cell-wall
(wall? grid x y)   ; true for cell-wall only (doors are passable!)
(door? grid x y)   ; true for cell-door
```

`wall?` is the player-collision predicate. Doors return false because walking into a door is the level-advance trigger. The raycaster has its own predicate that blocks rays on cell-door so doors stay visually solid until traversed.

## Random map generation

```phel
(random-grid w h n-blocks)
```

1. Bordered base: outer ring `cell-wall`, interior `cell-floor`.
2. Loop `n-blocks` times: random interior `(x, y)`, random 1×1 or 2×2 block, paint cells `cell-wall`.
3. Border preserved (never overwritten).

`build-world` picks `n-blocks` per level so room size and obstacle density are independent.

## Door seeding

```phel
(seed-doors grid n)
```

Converts `n` random interior wall cells into doors. Candidate must (a) currently be a wall and (b) sit next to at least one floor cell. Without the floor-neighbour check a door can hide inside a 2×2 wall blob and lock the room (real bug that shipped once). Gives up after 400 attempts.

```phel
(defn- has-floor-neighbour? [grid x y]
  (or (= cell-floor (cell grid (- x 1) y))
      (= cell-floor (cell grid (+ x 1) y))
      (= cell-floor (cell grid x (- y 1)))
      (= cell-floor (cell grid x (+ y 1)))))
```

## Player spawn

```phel
(random-spawn grid)  → [x y]   floats at the centre of a random open cell
```

Picks until it finds a `cell-floor`. Bordered grid guarantees one exists; loop terminates.

## Secret walls

Two sources:

- **Hand-authored**: write `S` in a `:layout` row; `parse-layout` resolves it to `cell-secret` (L10's pillar secrets).
- **Procgen-seeded**: `seed-secrets grid n` converts up to `n` *divider walls* (`divider-wall?`: a 1-cell-thick interior wall with floor on both horizontal OR both vertical sides) into `cell-secret`. Deterministic top-left-first scan (testable; the random grid itself varies the spots). `build-world` calls it on non-`:layout` levels, but **skips locked levels** - a secret shortcut there could bypass the keycard door. `secrets-per-level` (level.phel) = 2.

```phel
(wall?    grid x y)  ; true for secret cells - the raycaster paints them like normal walls
(passable? grid keys x y) ; false for secret cells - the player bumps until reveal
(secret?  grid x y)  ; true only for cell-secret
(reveal-secret grid x y)  ; swap cell-secret → cell-floor (no-op on non-secret)
(count-secrets grid)      ; per-level total, stamped at build time
(seed-secrets grid n)     ; convert up to n divider walls to cell-secret
```

The visual cue is deliberately absent (DOOM-style): identical wall shading, no overlay. Discovery is by exploration + bumping. `commands/play.phel/try-reveal-secret` watches the action-key rising edge (`F`); on a press it checks the cell one unit ahead of the player along `:angle`, calls `reveal-secret` if it's a secret, and drops a reward stash via `level/place-secret-reward`: an ammo box + armor shard plus one rotating trophy powerup (soulsphere / berserk / invuln, by reveal index - the rare pickups become a reliable exploration payoff). World tracks `:secrets-total` (set by `count-secrets` in `build-world`) + `:secrets-found` (bumped by `try-reveal-secret`); the F3 debug HUD paints `secrets X/Y`.

## Switches

Hand-authored only - `cell-switch-off` is never placed by random procgen. Layout char `T` opts a cell in; the level config supplies the `:switches` metadata:

```phel
:layout    [...
            "#..T............T..#"
            ...]
:switches  [{:at [3 14]  :targets [[7 10]]}
            {:at [16 14] :targets [[12 10]]}]
```

Each entry pairs a switch position with the cells it toggles. `try-toggle-switch` in `commands/play.phel` watches the `F` rising edge (after `try-reveal-secret`), checks the cell ahead of the player, and routes through `map/toggle-switch`:

1. `toggle-switch-cell` swaps the glyph between `cell-switch-off` and `cell-switch-on`.
2. For every `[x y]` in `:targets`, `toggle-target-cell` flips `cell-wall` ↔ `cell-floor`. Doors are skipped (defensive: targeting a door cell leaves it untouched).
3. `state/rebuild-pgrid` resyncs the raycaster's PHP-array view; without this the 3D render would still paint the pre-toggle wall.

The minimap glyph differs per state: dim cyan `T` for inactive, bright yellow `T` for activated, so the player can read which switches they've already flipped.

## Out-of-bounds reads

```phel
(cell [[1 1 1] [1 0 1]] 99 99)  → cell-wall
(cell [[1 1 1] [1 0 1]] -1 0)   → cell-wall
```

Off-map = wall means the raycaster skips range checks: keeps stepping until a non-floor cell (or max-depth). One branch saved per ray step.
