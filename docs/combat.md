# Combat

Hitscan + damage timing + i-frames. `src/modules/core/combat.phel`. Only side effect is `play-sfx!`, gated by `(:sound-on world)`.

## Tunables

```phel
(def shot-hit-radius   0.5)   ; off-axis tolerance for the ray to count as a hit
(def shot-max-range   12.0)   ; hitscan range in world units
(def touch-damage-dist 0.7)   ; enemy this close = -1 life
(def iframe-seconds    1.0)   ; post-hit invulnerability window
(def fire-anim-seconds 0.09)  ; muzzle flash visibility
(def fx-ttl-seconds    0.45)  ; blood splatter lifetime
(def flash-seconds     0.05)  ; 1-frame all-white impact jolt
(def mag-size          10)    ; rounds per magazine; reload at R
(def max-reserve       50)    ; hard cap on the spare ammo pool
(def reload-cooldown-seconds 1.5) ; reload animation + firing lockout
```

## Magazine + reload

`can-fire?` requires `:fire-cooldown <= 0`, `:jam-secs <= 0`, `:reload-cooldown <= 0`, AND `:mag > 0`. Trigger pulls on an empty mag drop silently — the player must press **R** to reload.

`reload` draws `min(mag-size - mag, :ammo-reserve)` rounds from the world's spare pool and arms `:reload-cooldown`. Three no-op paths keep the world identity stable so callers can compare cheaply: reload already in progress, mag already full, or reserve empty.

```phel
(defn reload [world]
  (let [mag     (or (:mag world) 0)
        reserve (or (:ammo-reserve world) 0)
        needed  (php/- mag-size mag)]
    (cond
      (php/> (or (:reload-cooldown world) 0.0) 0.0) world
      (php/<= needed 0)                              world
      (php/<= reserve 0)                             world
      :else
      (let [drawn (php/min needed reserve)]
        (assoc world
               :mag             (php/+ mag drawn)
               :ammo-reserve    (php/- reserve drawn)
               :reload-cooldown reload-cooldown-seconds)))))
```

`apply-heat` decrements `:mag` by one on every shot, clamped at zero. `decay-timers` ticks `:reload-cooldown` down each frame so the next trigger pull can fire as soon as the brief lockout expires.

A trigger pull on an empty mag with no other gate active routes through `empty-trigger-pull`: arms `:empty-click-secs` (`empty-click-seconds 0.8`) and plays the `:click` sfx. Render reads the timer and paints a centred `CLICK · press R to reload` prompt above the pistol — flips to `OUT OF AMMO` when `:ammo-reserve` is also 0.

Fresh runs start with `:ammo-reserve 30` (three full mags); the cap is `max-reserve` (50). Ammo-box pickups on the map top the reserve back up (see [`level-system.md`](level-system.md)).

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

1. **Wall ray** along facing. `cast-wall-distance` calls `core/engine/cast-ray`, returns distance to first wall.
2. **Enemy check**. `core/enemy/shoot` projects each enemy onto heading via dot product, picks nearest one that is `:alive`, in front (projection > 0), closer than the wall, within max-range, and within hit-radius perpendicular to heading.

If found, that enemy flips `:alive false` with `:respawn-after` (3-6s uniform). Returns `[new-enemies hit? hit-pos idx]`.

### on-shot-hit

```phel
;; bump kills + light muzzle flash + push blood splatter
(let [scored (update world :kills inc)]
  (push-blood-fx (assoc scored :fire-anim fire-anim-seconds) hit-pos))
```

Dead enemy stays in vector with respawn timer. `tick-enemies` counts down + revives. See [monsters.md](monsters.md).

### Blood fx

```phel
{:x ... :y ... :ttl fx-ttl-seconds}
```

Pushed into `(:fx world)`. `decay-fx` ticks each `:ttl` by dt, drops expired. `io/render.phel` paints them as bright-pink, mid-red, dim-red blocks via projection math.

## Damage

```phel
(defn damage-step [world dt]
  (let [w (decay-timers world dt)]
    (if (vulnerable? w) (take-damage w) w)))
```

### decay-timers

Ticks four timers by `dt`: `:iframes` (immunity), `:fire-anim` (muzzle flash), `:intro-secs` (level splash), `:flash-secs` (white impact). Also calls `decay-fx`.

### vulnerable?

```phel
(and (php/<= (:iframes world) 0.0)
     (enemies-touching? (:enemies world) px py))
```

`enemies-touching?` walks enemies; first alive one within `touch-damage-dist` triggers damage. Squared-distance comparison, no sqrt.

### take-damage

```phel
(when (:sound-on world) (play-sfx! :hit))
(assoc (update world :lives dec-clamped)
       :iframes    iframe-seconds
       :flash-secs flash-seconds)
```

- Loses one life (clamped at 0).
- 1.0s i-frame: `vulnerable?` returns false, single touch can't drain multiple lives.
- 0.05s flash: `render!` paints viewport white. One-frame jolt before red i-frame wash.

## i-frame visualization

During `:iframes`, render swaps `shade-table-blood` for `shade-table`. Grayscale becomes red. Sky/floor swap too:

```phel
sky'   (if bloody? sky-blood   sky)
floor' (if bloody? floor-blood floor)
```

## Why combat lives in `core/`

Almost pure. Only side effect is `play-sfx!`, gated by `(:sound-on world)`. Fire / take damage / respawn is fully determined by world + dt + edges. Tests exercise via `tick-shooting` and `damage-step` against literal worlds. No audio fakes.
