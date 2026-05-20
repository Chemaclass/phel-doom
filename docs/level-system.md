# Level system

The 5-level progression catalog + the `build-world` factory. Lives
in `src/modules/core/level.phel`.

## Catalog

```phel
(def levels
  [{:size [22 16] :walls 12 :enemies 4  :chase 0.8 :name "imps"        ...}
   {:size [28 20] :walls 22 :enemies 6  :chase 1.0 :name "demons"      ...}
   {:size [36 24] :walls 38 :enemies 8  :chase 1.3 :name "cacodemons"  ...}
   {:size [44 28] :walls 55 :enemies 9  :chase 1.6 :name "barons"      ...}
   {:size [52 32] :walls 75 :enemies 12 :chase 2.0 :name "cyberdemons" ...}])
```

Per-level knobs:

| Field | Meaning |
|---|---|
| `:size`     | `[width height]` of the grid in cells |
| `:walls`    | Number of random wall blobs scattered inside |
| `:enemies`  | How many monsters to spawn |
| `:chase`    | Movement speed of the chase AI (units/sec) |
| `:name`     | Display name, shown in HUD + intro splash |

Plus enemy visual fields covered in [monsters.md](monsters.md):
`:head-code`, `:body-code`, `:legs-code`, `:body-glyph`,
`:body-glyph-fg`, `:face`, `:face-alt`.

## `config-for`

```phel
(defn config-for [n]
  (get levels (php/max 0 (php/min (php/- num-levels 1) (php/- n 1)))))
```

Looks up the config for level N (1-indexed). Clamps out-of-range
inputs to the closest valid level so callers don't need to guard.

## `build-world`

```phel
(defn build-world [level-num lives]
  (let [cfg (config-for level-num)]
    (let [[w h] (:size cfg)
          grid  (seed-doors (random-grid w h (:walls cfg)) 1)]
      (let [[px py] (random-spawn grid)]
        (let [world (new-world grid (new-player px py random-angle))]
          (let [with-foes (with-enemies world
                            (spawn-enemies grid (:enemies cfg)
                                           enemy-min-spawn-dist px py))]
            (assoc with-foes
                   :level level-num :lives lives
                   :hearts      (maybe-spawn-heart grid lives px py)
                   :chase-speed (:chase cfg)
                   ;; enemy visual stamps...
                   :level-name  (:name cfg)
                   :intro-secs  1.5)))))))
```

Sequence:

1. **Random grid** with `:walls` blobs of size 1×1 or 2×2.
2. **One door** seeded into a random interior wall that has a floor
   neighbour (so the player can reach it).
3. **Player spawn** at a random open cell.
4. **Enemy spawn** of `:enemies` monsters, at least
   `enemy-min-spawn-dist = 3.0` units away from the player.
5. **Heart pickup** in a random open cell if `lives < max-lives`,
   otherwise no heart.
6. **Stamp the level metadata** onto the world (chase speed, monster
   colours, glyphs, name, etc.) plus a 1.5s intro splash timer.

The result is a fully-formed world ready to feed into `game-loop`.

## Why exactly one door per level

Earlier iterations had multiple doors per room. Player couldn't
tell which was the level exit. Changing to 1 door makes the goal
unambiguous — find the door, walk through.

## Why hearts only when lives < max-lives

Two design reasons:

1. Maxed-out hearts are wasted pickups; skipping the spawn keeps the
   minimap less cluttered.
2. The decision happens **at build-world time** with the carried-
   lives count, so a player at full health enters every room with no
   heart visible. Stepping into a room and immediately seeing a
   heart on the minimap signals "you're below cap" without any text.

## Reading order through a run

```
build-world 1 5     → L1 imps, no heart (started at max-lives)
... play ...
result :next-level :level 2 :lives 4
build-world 2 4     → L2 demons, ONE heart (lives < 5)
... play ...
result :next-level :level 3 :lives 5
build-world 3 5     → L3 cacodemons, no heart
... play ...
```

`run-levels` in `commands/play.phel` is the loop that calls
`build-world` for each iteration.

## Restart with the same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` call
and `mt_srand`s it. On `R` (capital) from an end screen, that seed
is reused — `random-grid` / `random-spawn` / `seed-doors` /
`spawn-enemies` all pull from the same PRNG sequence, so the level
sequence is bit-identical to the previous run. Lets the player
replay a particular tough spawn.
