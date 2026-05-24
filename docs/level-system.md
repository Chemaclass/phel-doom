# Level system

5-level progression catalog + `build-world` factory. `src/modules/core/level.phel`.

## Catalog

```phel
(def levels
  [{:size [22 16] :walls 12 :enemies 4  :chase 0.8 :enemy-lives 1 :name "imps"}
   {:size [28 20] :walls 22 :enemies 6  :chase 1.0 :enemy-lives 2 :name "demons"}
   {:size [36 24] :walls 38 :enemies 8  :chase 1.3 :enemy-lives 3 :name "cacodemons"}
   {:size [44 28] :walls 55 :enemies 5  :chase 1.6 :enemy-lives 4 :door-lock :blue :name "barons"}
   {:size [52 32] :walls 75 :enemies 7  :chase 2.0 :enemy-lives 5 :door-lock :red  :name "cyberdemons"}])
```

| Field | Meaning |
|---|---|
| `:size`        | `[width height]` of grid in cells |
| `:walls`       | Random wall blobs scattered inside |
| `:enemies`     | Monsters to spawn |
| `:chase`       | Chase AI speed (units/sec) |
| `:enemy-lives` | Per-enemy HP; controls hit-flash digit, wounded body shade |
| `:door-lock`   | `:blue` / `:red` / absent — colour required to pass the exit |
| `:name`        | Display name (HUD + intro splash) |

Plus enemy visual fields covered in [monsters.md](monsters.md): `:head-code`, `:body-code`, `:legs-code`, `:body-glyph`, `:body-glyph-fg`, `:face`, `:face-alt`, `:face-attack`.

## `config-for`

```phel
(defn config-for [n]
  (get levels (php/max 0 (php/min (php/- num-levels 1) (php/- n 1)))))
```

Level N config (1-indexed). Clamps out-of-range to nearest valid.

## `build-world`

Signature: `(build-world level-num lives backpack? diff owned)`. Sequence per build:

1. `random-grid` with `:walls` random 1×1 / 2×2 blobs
2. `seed-doors` carves one exit. `lock-the-door` upgrades it to `cell-door-blue` / `cell-door-red` when `:door-lock` is set.
3. Player spawn at a random open cell with random angle.
4. `:enemies` monsters at ≥ `enemy-min-spawn-dist 3.0` from player, each with HP = `:enemy-lives`.
5. `maybe-spawn-heart` only if `lives < max-lives`.
6. `maybe-spawn-armor` (50%); `maybe-spawn-berserk` (1/8); `maybe-spawn-invuln` (1/12); `maybe-spawn-backpack` (L2+, 1/5, skipped when already owned).
7. `maybe-spawn-keycard` when `:door-lock` is set.
8. `maybe-spawn-weapon-pickups`: shotgun on L2 / chaingun on L3, skipped when already owned. Pistol never spawns as a pickup.
9. `spawn-ammo-boxes` count = `ceil(enemies × max-lives / 8)`, floor 2.
10. Stamp enemy visuals, `:level-name`, `:difficulty`, 1.5s `:intro-secs`.

`run-levels` (in `commands/play.phel`) wraps the call and overlays cross-level carries on top of the fresh world: **active weapon + per-weapon mag/reserve state**, minimap + sound toggles, `:god?` flag.

## Why hearts only when lives < max-lives

Wasted pickups clutter the minimap; seeing a heart signals "below cap" without text.

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
