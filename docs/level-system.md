# Level system

5-level progression catalog + `build-world` factory. `src/modules/core/level.phel`.

## Catalog

```phel
(def levels
  [{:size [22 16] :walls 12 :enemies 4  :chase 0.8 :name "imps"        ...}
   {:size [28 20] :walls 22 :enemies 6  :chase 1.0 :name "demons"      ...}
   {:size [36 24] :walls 38 :enemies 8  :chase 1.3 :name "cacodemons"  ...}
   {:size [44 28] :walls 55 :enemies 5  :chase 1.6 :name "barons"      ...}
   {:size [52 32] :walls 75 :enemies 7  :chase 2.0 :name "cyberdemons" ...}])
```

| Field | Meaning |
|---|---|
| `:size`     | `[width height]` of grid in cells |
| `:walls`    | Random wall blobs scattered inside |
| `:enemies`  | Monsters to spawn |
| `:chase`    | Chase AI speed (units/sec) |
| `:name`     | Display name (HUD + intro splash) |

Plus enemy visual fields covered in [monsters.md](monsters.md): `:head-code`, `:body-code`, `:legs-code`, `:body-glyph`, `:body-glyph-fg`, `:face`, `:face-alt`.

## `config-for`

```phel
(defn config-for [n]
  (get levels (php/max 0 (php/min (php/- num-levels 1) (php/- n 1)))))
```

Level N config (1-indexed). Clamps out-of-range to nearest valid.

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
                   :armors      (maybe-spawn-armor grid)
                   :ammo-boxes  (spawn-ammo-boxes grid)
                   :chase-speed (:chase cfg)
                   ;; enemy visual stamps...
                   :level-name  (:name cfg)
                   :intro-secs  1.5)))))))
```

Sequence:

1. Random grid with `:walls` blobs of 1×1 or 2×2.
2. One door seeded into a random interior wall with a floor neighbour (reachable).
3. Player spawn at a random open cell.
4. `:enemies` monsters at least `enemy-min-spawn-dist = 3.0` from player.
5. Heart pickup in a random open cell if `lives < max-lives`; otherwise none.
6. Armor pickup roughly every other level (50% chance, one cell).
7. Two ammo-boxes at random open cells (always — reserve is finite, so the player must restock).
8. Stamp level metadata (chase speed, monster colours, glyphs, name) + 1.5s intro splash timer.

Result feeds into `game-loop`.

## Why exactly one door per level

Earlier iterations had multiple doors. Player couldn't tell which was the exit. One door = unambiguous goal.

## Why hearts only when lives < max-lives

1. Maxed hearts are wasted pickups; skipping keeps minimap less cluttered.
2. Decision happens at `build-world` with the carried lives count, so a full-health player enters every room with no heart visible. Seeing a heart on the minimap signals "below cap" without text.

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

`run-levels` in `commands/play.phel` calls `build-world` per iteration.

## Restart with the same seed

`run-levels` captures `(php/mt_rand)` before each `build-world` and `mt_srand`s it. On `R` (capital) from an end screen the seed is reused. `random-grid` / `random-spawn` / `seed-doors` / `spawn-enemies` all draw from the same PRNG, so the sequence is bit-identical. Lets the player replay a tough spawn.
