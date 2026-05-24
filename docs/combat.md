# Combat

Hitscan + damage timing + i-frames. `src/modules/core/combat.phel`. Only side effect is `play-sfx!`, gated by `(:sound-on world)`.

## Tunables

```phel
(def shot-hit-radius   0.5)   ; off-axis tolerance for a ray-hit
(def shot-max-range   12.0)   ; hitscan range, world units
(def shot-knockback-distance 1.0) ; world units pushed back per wounding hit
(def touch-damage-dist 0.7)   ; enemy this close = take-damage
(def iframe-seconds    1.0)   ; post-hit invulnerability window
(def fire-anim-seconds 0.09)  ; muzzle flash visibility
(def fx-ttl-seconds    0.45)  ; blood splatter lifetime
(def flash-seconds     0.05)  ; 1-frame white impact jolt
(def heat-per-shot     0.30)  ; pistol-only — see `:overheats?` flag
(def jam-seconds       1.4)   ; pistol-only lockout when heat ≥ 1
;; Pistol fallback defaults — overridden per weapon in weapons.phel
;; (`mag-size`, `fire-cooldown`, `reload-duration`, `reserve-cap`,
;; `ammo-per-box`, `damage`, `auto-fire?`, `overheats?`).
(def mag-size 10)
(def max-reserve 50)
(def reload-cooldown-seconds 1.2)
(def armory-reserve 999) ; per-weapon reserve cap under --armory
```

## Magazine + reload

`can-fire?` requires `:mag > 0`, `:fire-cooldown <= 0`, `:jam-secs <= 0`, AND `:reload-cooldown <= 0`. Empty mag returns silent; player presses **R** to reload. Mag-size, reload-duration, and reserve-cap come from the active weapon's `weapons` spec (`weapons.phel`).

`reload` draws `min(mag-size - mag, :ammo-reserve)` into `:mag` and arms `:reload-cooldown`. Three no-op paths (reload-in-progress, mag-full, reserve-empty) keep the world identity stable for cheap comparison.

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

## Kill loot drops

On every kill `on-shot-hit` rolls a uniform float and routes through `roll-loot-kind`:

| Band | Drop | Notes |
|------|------|-------|
| `[0.00, 0.15)` | `:ammo` | Most common — kill-loot ammo carries a `:weapon` tag picked uniformly from `:owned-weapons` MINUS the pistol (pistol has level-spawned boxes anyway). Fresh L1 / pistol-only fixtures fall back to pistol. |
| `[0.15, 0.22)` | `:armor` (absorb one hit) | Mid — useful but not as scarce as health |
| `[0.22, 0.25)` | `:heart` (`+1` life) | Rarest, AND suppressed when `lives = max-lives` so it never wastes |
| `[0.25, 1.00)` | nothing | ~75% of kills drop nothing; keeps the floor uncluttered |

The drop is pushed into the same `:hearts` / `:armors` / `:ammo-boxes` vectors that level-start pickups use. `pickup-ammos` in `play.phel` reads the box's `:weapon` tag and tops up that weapon's `:weapon-state` reserve (mirror stays in sync only if the tagged weapon is the active one). Untagged (level-spawn) boxes refill the active weapon.

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

## Damage + knockback

```phel
(defn damage-step [world dt]
  (let [w (decay-timers world dt)]
    (if (vulnerable? w) (take-damage w) w)))
```

### decay-timers

Decrements `:iframes`, `:fire-anim`, `:intro-secs`, `:flash-secs` by `dt`. Also decays `:fx` (blood splatters).

### vulnerable?

```phel
(and (php/<= (:iframes world) 0.0)
     (php/<= (or (:invuln-secs world) 0.0) 0.0)
     (not (:god? world))                ; --god / make play-dev
     (enemies-touching? (:enemies world) px py))
```

Four gates: i-frame window, invulnerability sphere timer, dev god mode, AND at least one alive enemy within `touch-damage-dist`. Squared-distance comparison, no sqrt.

### take-damage (player contact)

- Armor absorbs the hit first if `:armor > 0` (drops the counter, no life loss).
- Otherwise loses one life (clamped at 0).
- 1.0s i-frame: `vulnerable?` returns false, single touch can't drain multiple lives.
- 0.05s flash: `render!` paints viewport white. One-frame jolt before the red i-frame wash.
- Player knockback shove away from the attacker; arms `:hurt-side` so the directional red band paints on the correct edge.

### Shot knockback (enemy-only)

Every wounding enemy hit (`:lives > 0` after damage) pushes the enemy ~1 cell back along the shot direction. Movement respects walls (half-step or quarter-step fallback if full step hits a wall). Killing blows skip knockback so the corpse lands on the death cell and loot drops cleanly. See `enemy/push-back-enemy`.

## i-frame visualization

During `:iframes`, render swaps `shade-table-blood` for `shade-table`. Grayscale becomes red. Sky/floor swap too:

```phel
sky'   (if bloody? sky-blood   sky)
floor' (if bloody? floor-blood floor)
```

## Why combat lives in `core/`

Almost pure. Only side effect is `play-sfx!`, gated by `(:sound-on world)`. Fire / take damage / respawn is fully determined by world + dt + edges. Tests exercise via `tick-shooting` and `damage-step` against literal worlds. No audio fakes.
