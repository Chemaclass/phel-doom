# Combat

Hitscan shooting + damage timing + i-frame logic. Lives in
`src/modules/core/combat.phel`. The only side effect is the
`play-sfx!` call, gated by `(:sound-on world)`.

## Tunables

```phel
(def shot-hit-radius   0.5)   ; off-axis tolerance for the ray to count as a hit
(def shot-max-range   12.0)   ; hitscan range in world units
(def touch-damage-dist 0.7)   ; enemy this close = -1 life
(def iframe-seconds    1.0)   ; post-hit invulnerability window
(def fire-anim-seconds 0.09)  ; muzzle flash visibility
(def fx-ttl-seconds    0.45)  ; blood splatter lifetime
(def flash-seconds     0.05)  ; 1-frame all-white impact jolt
```

## Shooting

```phel
(defn fire-shot [world]
  (let [[enemies' hit? hit-pos idx] (resolve-shot world)]
    (play-shot-sfx world hit?)
    (if hit?
      (on-shot-hit world enemies' hit-pos idx)
      (on-shot-miss world))))
```

### resolve-shot

Two-step hitscan:

1. **Cast a wall ray** from the player along their facing —
   `cast-wall-distance` calls `core/engine/cast-ray` and gets back
   the distance to the first wall on the player's heading line.
2. **Check every enemy** — `core/enemy/shoot` walks the enemy
   vector, projects each enemy onto the heading vector (dot
   product), and finds the **nearest one** that:
   - is `:alive`
   - is in front of the player (projection > 0)
   - is closer than the wall (proj < wall-dist) — walls block shots
   - is within max-range (proj < max-range)
   - is within hit-radius perpendicular to the heading

If found, that enemy is flipped `:alive false` and stamped with a
`:respawn-after` timer (3-6s uniform). Returns
`[new-enemies hit? hit-pos idx]`.

### on-shot-hit

```phel
;; bump kills + light muzzle flash + push blood splatter
(let [scored (update world :kills inc)]
  (push-blood-fx (assoc scored :fire-anim fire-anim-seconds) hit-pos))
```

The dead enemy stays in the vector with its respawn timer; the
per-frame `tick-enemies` step counts down and revives them later.
See [monsters.md](monsters.md).

### Blood fx

```phel
{:x ... :y ... :ttl fx-ttl-seconds}
```

Pushed into `(:fx world)`. `decay-fx` ticks each entry's `:ttl` by
dt and drops the ones that expired. `core/combat.phel` owns the
data; `io/render.phel` paints them as bright-pink → mid-red → dim-
red blocks at the world position via the projection math.

## Damage

```phel
(defn damage-step [world dt]
  (let [w (decay-timers world dt)]
    (if (vulnerable? w) (take-damage w) w)))
```

### decay-timers

Ticks four timers down by `dt`:

- `:iframes`     (post-hit immunity)
- `:fire-anim`   (muzzle flash)
- `:intro-secs`  (level intro splash)
- `:flash-secs`  (white impact frame)

Plus calls `decay-fx` on the blood splatter vector.

### vulnerable?

Returns true when both conditions hold:

```phel
(and (php/<= (:iframes world) 0.0)
     (enemies-touching? (:enemies world) px py))
```

`enemies-touching?` walks the enemies vector; the first alive enemy
within `touch-damage-dist` of the player triggers contact damage.
Squared-distance comparison so no sqrt per enemy.

### take-damage

```phel
(when (:sound-on world) (play-sfx! :hit))
(assoc (update world :lives dec-clamped)
       :iframes    iframe-seconds
       :flash-secs flash-seconds)
```

- Loses one life (clamped at 0).
- Starts a 1.0s i-frame window — `vulnerable?` returns false during
  this time, so a single touch can't drain multiple lives across
  consecutive frames.
- Starts the 0.05s flash window — `render!` paints the entire
  viewport white for the duration. One-frame jolt before the
  red i-frame palette wash takes over.

## i-frame visualization

During the 1.0s `:iframes` window, the render layer swaps in
`shade-table-blood` instead of `shade-table` — the whole grayscale
gradient becomes a red gradient, so the world flushes red and the
player gets unmistakable feedback that they're hit + briefly
invulnerable.

Sky / floor swap too:

```phel
sky'   (if bloody? sky-blood   sky)
floor' (if bloody? floor-blood floor)
```

## Why combat lives in `core/`

Almost pure. The only side effect is `play-sfx!` which is gated by
`(:sound-on world)` and is the same kind of "muted call" pattern
Clojure folks use for "effectful but not stateful". The decision to
fire / take damage / respawn is determined entirely by the world
+ dt + edges; same call returns the same world tomorrow.

Tests exercise it via `tick-shooting` and `damage-step` against
literal worlds — no fakes for the audio.
