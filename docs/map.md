# Map / grid

`src/core/map.phel`: grid shape, cell semantics, generation, lookup helpers. How levels use it: [level-system.md](level-system.md).

## Cells

A grid is a vector of rows of ints. Always use the named constants, never raw literals.

| Constant | Value | Blocks player | Blocks rays | Notes |
|---|---|---|---|---|
| `cell-floor`       | 0 | no | no | |
| `cell-wall`        | 1 | yes | yes | |
| `cell-door`        | 2 | no | yes | Exit: stepping in ends the level |
| `cell-door-blue`   | 3 | until `:blue` held | yes | |
| `cell-door-red`    | 4 | until `:red` held | yes | |
| `cell-door-boss`   | 5 | until `:boss` held | yes | `:boss` is granted when the L10 cyber dies |
| `cell-secret`      | 6 | yes | yes | Looks like a wall until F reveals it |
| `cell-switch-off`  | 7 | yes | yes | F toggles it |
| `cell-switch-on`   | 8 | yes | yes | F toggles it back |
| `cell-door-yellow` | 9 | until `:yellow` held | yes | |

`lock-colours` maps locked doors to keys (`{3 :blue 4 :red 5 :boss 9 :yellow}`); `lock-cells` is its derived inverse, so they cannot drift. `:boss` has no keycard: combat grants it on the boss kill.

## Lookup helpers

```phel
(cell grid x y)            ; value; out of bounds reads as cell-wall
(wall? grid x y)           ; wall, secret or switch: blocks enemies and bolts
(door? grid x y)           ; any door variant
(door-lock grid x y)       ; key kw a door needs, or nil
(passable? grid keys x y)  ; can the player step here with these held keys?
(missing-key-for grid keys x y) ; lock kw blocking the player, or nil
(secret? grid x y)
(switch? grid x y)         ; either state
(find-door-cell grid)      ; [x y] of the first door, or nil
```

`wall?` ignores doors, so enemies and bolts pass them. `missing-key-for` lets `physics/try-move` tell a locked-door bump (`NEED <COLOUR> KEY` + deny click) from a silent wall bump. Out of bounds reads as wall, so the raycaster never range-checks.

## Generation

All generation draws from the seeded `rng`, so the same seed gives the same room.

- `(random-grid w h n-blocks)`: bordered room plus `n-blocks` random 1x1 or 2x2 wall blobs. The border is never overwritten. Size and obstacle density are independent knobs.
- `(scatter-walls grid [sx sy] n)`: the same blobs on an existing grid (fixed-shell levels), then `seal-pockets` walls off any floor cut off from spawn. The floor stays one connected region, the spawn cell stays clear, and pickups, enemies and the exit are never stranded.
- `(place-exit grid [sx sy])`: floods the floor reachable from spawn and turns one random wall touching it into `cell-door`. Any wall qualifies, an interior pillar or a border edge. `build-world` applies the lock afterwards.
- `(random-spawn grid)`: `[x y]` at the centre of a random floor cell, retrying until one is found.
- `(parse-layout rows)`: ASCII layout to `{:grid :spawn}`, nil without `@`. Characters: [level-system.md](level-system.md#layouts-layout).

### Cost lessons

Generation floods and scans the whole grid, so it works on a flat PHP-native mirror (`grid->php`, index `y*w + x`) instead of `cell` lookups. On 64x40 that took `place-exit` from 57.9 to 8.4 ms and `scatter-walls` from 58.1 to 10.1 ms, with all 210 worlds (10 levels x 7 seeds x 3 difficulties) hashing identically. The same pass keys the flood's seen-set by flat index (not a fresh `"x:y"` string), reads the four neighbour offsets from a flat int array (not a vector literal rebuilt per dequeue), and writes wall blobs into the mirror instead of `assoc-in` on the persistent grid per cell (~83 us each). A whole level build went from 42.7 to 13.9 ms.

Gotchas:

- PHP arrays pass BY VALUE into closures and functions. A `visit!` or `place-block!` helper writes to a copy and the caller sees nothing: silent, and fast-looking (the broken flood seemed 10x faster because it stopped after one cell). Mutate the array in the function that owns it, in statement position.
- The flat key collides out of bounds: `(-1, y)` and `(w-1, y-1)` share an index. Bounds-guard every lookup, and let the flood write only cells the grid reports as floor.

## Secret walls

Sources: `S` in a `:layout`, or `seed-secrets` on procgen levels (rule in [level-system.md](level-system.md#secrets)).

`(seed-secrets grid n)` converts up to `n` divider walls to `cell-secret`. A divider is a 1-cell-thick interior wall with floor on both horizontal or both vertical sides. The scan is deterministic, top-left first, skips the border, and never places two secrets side by side.

F with a secret in the cell directly ahead calls `reveal-secret` (swap to floor), rebuilds the ray grid, bumps `:secrets-found`, and drops a stash via `level/place-secret-reward`: an ammo box, an armor shard, and a trophy rotating soulsphere, berserk, invuln by reveal order. `:secrets-total` comes from `count-secrets` at build time.

Visual tell (issue #469): a secret samples the wall texture half a tile out of phase with its neighbours. See [rendering.md](rendering.md#secret-wall-tell-issue-469).

## Switches

Hand-authored only (`T` in a `:layout`, L10). The level config lists targets:

```phel
:switches [{:at [3 14]  :targets [[7 10]]}
           {:at [16 14] :targets [[12 10]]}]
```

F with a switch in the cell directly ahead calls `toggle-switch`: the switch flips off/on, every target flips wall/floor (doors and other cells untouched), and the ray grid is rebuilt. A switch with no matching entry flips only its own glyph. Minimap: dim `T` off, bright `T` on.
