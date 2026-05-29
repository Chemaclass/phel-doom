# Combat

Hitscan + damage timing + i-frames. `src/core/combat.phel`. Only side effect is `play-sfx!`, gated by `(:sound-on world)`.

## Tunables

```phel
(def shot-hit-radius   0.5)   ; off-axis tolerance for a ray-hit
(def shot-max-range   12.0)   ; hitscan range, world units
(def shot-knockback-distance 1.0) ; world units pushed back per wounding hit
(def touch-damage-dist 0.7)   ; enemy this close = take-damage
(def iframe-seconds    1.0)   ; post-hit invulnerability window
(def fire-anim-seconds 0.09)  ; muzzle flash visibility
(def fx-ttl-seconds    0.7)   ; blood splatter lifetime
(def flash-seconds     0.05)  ; 1-frame white impact jolt
(def heat-per-shot     0.30)  ; pistol-only - see `:overheats?` flag
(def jam-seconds       1.4)   ; pistol-only lockout when heat ≥ 1
;; Pistol fallback defaults - overridden per weapon in weapons.phel
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

A trigger pull on an empty mag with no other gate active routes through `empty-trigger-pull`: arms `:empty-click-secs` (`empty-click-seconds 0.8`) and plays the `:click` sfx. Render reads the timer and paints a centred `CLICK · press R to reload` prompt above the pistol - flips to `OUT OF AMMO` when `:ammo-reserve` is also 0.

Fresh runs start with `:ammo-reserve 30` (three full mags); the cap is `max-reserve` (50). Ammo-box pickups on the map top the reserve back up (see [`level-system.md`](level-system.md)).

## Kill loot drops

On every kill `on-shot-hit` rolls a uniform float and routes through `roll-loot-kind`:

| Band | Drop | Notes |
|------|------|-------|
| `[0.00, 0.15)` | `:ammo` | Most common - kill-loot ammo carries a `:weapon` tag picked uniformly from `:owned-weapons` MINUS the pistol (pistol has level-spawned boxes anyway). Fresh L1 / pistol-only fixtures fall back to pistol. |
| `[0.15, 0.22)` | `:armor` (absorb one hit) | Mid - useful but not as scarce as health |
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
;; bump kills + light muzzle flash + push blood splatter + distance-attenuated :hit sfx
(let [scored (update world :kills inc)]
  (push-blood-fx (assoc scored :fire-anim fire-anim-seconds) hit-pos))
```

The `play-shot-sfx` call in `fire-shot` (before on-shot-hit) emits the hit sound. For kills, `play-sfx! :kill` (distance-volume attenuated). Damage-only hits that don't kill emit `play-sfx! :wound` (distance-attenuated via `distance-volume` in `io/sound.phel`). Distance falloff keeps loud sfx from constant audio spam during crowded fights.

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
     (not (:god? world))                ; --god
     (enemies-touching? (:enemies world) px py))
```

Four gates: i-frame window, invulnerability sphere timer, dev god mode, AND at least one alive enemy within `touch-damage-dist`. Squared-distance comparison, no sqrt.

### take-damage (player contact)

- Armor absorbs the hit first if `:armor > 0` (drops the counter, no life loss).
- Otherwise loses one life (clamped at 0).
- 1.0s i-frame: `vulnerable?` returns false, single touch can't drain multiple lives.
- 0.05s flash: `render!` paints viewport white. One-frame jolt before the red i-frame wash.
- Player knockback shove away from the attacker; arms `:hurt-side` (one of `:left` `:right` `:front` `:back`) so the directional red band paints on the matching edge. Front and back use a narrow ±30° wedge around the player's facing / anti-facing vectors; everything else routes to the wider left / right edges. Closes the rear blind spot that the previous left-only / right-only routing left open (issue #66).

Internally `take-damage` and the projectile path share `apply-hit`, which takes an attacker `{:x :y :d2}` (the nearest enemy for contact, the bolt impact point for projectiles).

### hit-player-at + player-immune? (projectile impacts)

`hit-player-at world sx sy` applies the same hit as a contact touch but from an arbitrary world point - an enemy fireball impact (see [monsters.md](monsters.md) ranged casters + `core/projectile.phel`). `player-immune? world` is the projectile-side gate: i-frames, invuln sphere, or dev god mode - the same guards as `vulnerable?` minus the enemy-touch test. `core/projectile/resolve-hits` checks it before calling `hit-player-at`, so a bolt fizzles on the i-frame shield instead of phasing through.

### Hit-stop (kill weight)

On the killing blow `on-shot-hit` stamps `:hit-stop-secs` via `hit-stop-for (:max-lives killed)`:

| Enemy max-HP | Freeze |
|---|---|
| 1-2 (imp, demon) | none - kills clean so chaingun spray stays fluid |
| 3-9 (caco, baron) | `hit-stop-tough-seconds` (0.07s) |
| 10+ (boss cyber) | `hit-stop-boss-seconds` (0.16s) |

`play/tick-world` checks `:hit-stop-secs` right after the pause gate: while it's positive the whole gameplay step (physics / AI / projectiles / shooting / damage) is skipped and the timer just decays by `dt`. Render keeps drawing the frozen frame, so the muzzle flash + blood splatter hold for the freeze and the kill lands with weight. Gating on enemy toughness (not every kill) avoids stuttering a rapid-fire weapon into a slideshow.

### Chainsaw

Slot-4 melee weapon. Spec lives in `weapons/weapons :chainsaw` and carries three flags that the combat path branches on:

| Flag | Effect |
|------|--------|
| `:no-ammo? true` | `can-fire?` skips the mag check; `apply-heat` skips the mag decrement; `reloading?` always returns false. |
| `:max-range 1.5` | `resolve-shot` reads this in place of the global `shot-max-range` so the saw only lands on enemies inside the 1.5-cell envelope. |
| `:movement-mul 0.5` | `physics/weapon-movement-factor` halves longitudinal + lateral speed while `:fire-cooldown > 0`. The slow only kicks in mid-swing; an idle chainsaw walks at full speed. |

Damage type is `:melee` so future enemy resistances can target the saw without affecting ranged weapons. The 1-per-tick damage stacks with the berserk multiplier for a 2-per-tick swing during the rage window.

### BFG (splash weapon, issue #58)

Slot-5 area weapon, found on L7. The spec carries `:splash-radius` + `:splash-damage`; `fire-shot` branches on `:splash-radius` and routes to `bfg-fire` instead of the single-target hitscan:

1. `enemy/beam-impact` finds where the beam lands - the nearest alive enemy along the player's ray, else the wall (both capped at range). Pure projection scan, no mutation.
2. `enemy/splash` damages every alive enemy within `:splash-radius` of that impact point, returning `[new-enemies killed-count]`. Survivors wake (`:aware`) + take a hit-flash; no pain roll (a room-clear shouldn't stagger-lock the survivors).
3. `bfg-fire` bumps `:kills` by the body count, chains the streak, arms hit-stop (boss-length if a cyber died), and unlocks the boss door if the blast killed the cyberdemon. No per-enemy loot - the blast is its own reward.

Damage type is `:plasma`, NOT `:fire`, so the BFG bypasses the fire-resistant caco / baron / archvile / mancubus - it's the intended answer to grouped late-game mobs. Single-action (one deliberate shot per pull), slow 1.2s cooldown, expensive cells (mag 1, reserve cap 20).

### Berserk pickup

A berserk sphere (`:berserks` vector on the world, `Ω` glyph in the viewport + minimap) sits in 1-in-8 levels. Stepping on the cell drives:

1. `pickup-berserks` in `commands/play.phel` removes the sphere from `:berserks`, plays the dedicated `:berserk` sfx (Hero.aiff on macOS), and calls `arm-berserk`.
2. `arm-berserk` is a pure helper that stamps `:berserk-secs` to the full `berserk-seconds` window (20s). Refresh-not-stack: stepping on a second sphere replaces the timer rather than extending it, so the buff can never exceed `berserk-seconds`.
3. `decay-timers` (inside `damage-step`) ticks the counter down by dt each frame. `berserk?` reads it; `fire-shot` multiplies the active weapon's `:damage` by `berserk-damage-mul` (2) while the predicate is true.
4. `paint-berserk-tint` in `io/render.phel` paints a pulsing deep-red border around the viewport while the timer is positive AND the player is not already in i-frames; the bright i-frame edge bar wins on overlap so the more urgent cue reads first.

### Damage resistance

`enemy/shoot` takes a `damage-type` keyword (threaded in by `resolve-shot` from the active weapon's `:damage-type` field). The enemy catalog (`core/enemies.phel`) optionally tags monster types with `:resists #{...}`; if the picked target's type resists the incoming damage type, the per-hit damage is multiplied by zero so the target survives the hit with its lives unchanged. Hit registration (blood splatter, flash, sfx, wake) still fires so the player sees the bullet land and reads "no effect" from the missing HP digit / fading health bar.

Current catalog:

| Type | Resists |
|------|---------|
| caco | `:fire` |
| baron | `:fire` |
| archvile | `:fire` |
| mancubus | `:fire` |

All current weapons deal `:ballistic`, so the resist data is dormant until the BFG / plasma roster lands. Adding a new resistance is a one-line catalog edit; adding a new damage type is one keyword on the weapon spec.

### Nightmare respawn

`--difficulty=nightmare` stamps `:nightmare? true` on every enemy at level build time. Two downstream effects:

- `shoot` reads `:nightmare?` on the kill victim and draws the respawn cooldown from a tighter `[nightmare-respawn-delay-min, nightmare-respawn-delay-max]` band (1.0s to 2.0s) instead of the regular 3.0s to 6.0s.
- `tick-one`'s `:max-concurrent` gate skips entirely for nightmare enemies, so the L10 boss-arena cap (1 alive imp at a time) no longer applies and the swarm reasserts itself.

Other difficulties are unchanged. The HUD nightmare badge (red `[nightmare]` tag in the top strip) already existed.

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
