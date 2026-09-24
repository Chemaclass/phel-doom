# Combat

Shooting, taking damage, hit feedback. `src/core/combat.phel`, plus `loot.phel` and `weapons.phel`. Pure: sound cues queue as `{:name :vol}` on the world's `:sfx`, which `commands/play` drains and plays after `tick-world`.

Weapon numbers: [gameplay.md](gameplay.md#weapons). Monster stats: [monsters.md](monsters.md#stats-comparison).

## Tunables

| Constant | Value | Notes |
|----------|-------|-------|
| `shot-hit-radius` | 0.5 | Off-axis hitscan tolerance |
| `shot-max-range` | 12.0 | Default range; a spec's `:max-range` overrides |
| `shotgun-spread-half-angle` | 0.30 | Cone half-angle, radians (~17 degrees) |
| `shot-knockback-dist` | 1.0 | Enemy shove per wounding hit |
| `touch-damage-dist` | 0.7 | Contact damage range |
| `iframe-seconds` | 1.0 | Post-hit invulnerability |
| `knockback-dist` | 0.9 | Player shove away from the attacker |
| `flash-seconds` | 0.03 | Dark-red impact flash |
| `hit-marker-seconds` | 0.12 | Crosshair hit-marker |
| `streak-window-seconds` | 7.0 | A kill inside this chains the streak |

Per-weapon specs (`weapons.phel`) set mag, cooldown, reload time, reserve cap, ammo per box, damage, damage type, auto-fire, range, and the path flags below.

## Firing

`tick-shooting` fires on the trigger's rising edge, or on every ready frame while held for `:auto-fire?` weapons. `can-fire?` needs the fire, jam and reload timers at 0 and a round in the mag (`:no-ammo?` skips the mag).

`fire-shot` resolves the aim angle and wall probe once, then dispatches:

| Spec flag | Path | Weapons |
|---|---|---|
| `:splash-radius` | `bfg-fire` | BFG, rocket |
| `:pierce?` | `pierce-fire` | pistol |
| `:spread?` | `spread-fire` | shotgun |
| none | `single-hitscan-fire` | chaingun, chainsaw, incinerator |

Every path wakes the room by noise ([monsters.md](monsters.md#wake-triggers)) and counts toward accuracy. Pierce and spread share `finish-multikill`: blood and sfx on the nearest target, hit-stop by the toughest kill. Only the single-target path rolls pain and drops kill loot.

The heat/jam machinery (`:overheats?`, `heat-per-shot`, `jam-seconds`) is still data-driven, but no weapon opts in: jamming the fallback pistol felt bad.

## Magazine + reload

Each shot burns one round and arms the cooldown (`apply-heat`). `reload` moves `min(mag-size - mag, reserve)` into the mag and arms the reload timer. It returns the same world when a reload is running, the mag is full, or the reserve is empty.

An empty-mag pull shows `CLICK - press R to reload` (or `OUT OF AMMO`) for 0.8s. The reload nag (`reload-reminder-visible?` in `src/io/render/paint.phel`) arms at a mag fraction of 0.3 or less, so a pistol and a shotgun both nag at "nearly empty". It skips single-round mags, a dry reserve, a running reload, the CLICK prompt, and viewports under 9 rows. A finished reload flashes ` READY! ` for 0.30s.

## Hitscan shooting

A shot casts the wall probe (`cast-ray`), then `enemy/target-index` picks the nearest alive enemy in front, closer than the wall, in range, within `shot-hit-radius` of the ray, and passing the vertical gate.

`enemy/shoot` applies damage (0 if resisted) and sets the target `:aware`. A kill flips `:alive false` and arms the respawn timer; a wound floats the HP digit and rolls pain. `on-shot-hit` then bumps kills and streak, unlocks the L10 door on a cyber kill, drops loot, arms hit-stop, and stamps blood and the hit-marker.

A wounding hit shoves the enemy 1.0 unit along the shot, falling back to 0.5 then 0.25 against walls. Killing blows skip it, so corpse and loot stay on the death cell. A miss plays the report only, scaled by the distance to the wall.

### Vertical aim gate (look up/down)

With pitch, the flat cylinder test would hit an enemy while the crosshair points at the floor. So `shoot`, `pierce` and `spread-shoot` also require the crosshair on the drawn billboard (`enemy/vertical-hit?`, issue #243).

The crosshair sits at scene row `svh/2`. The feet sit at `round(svh/2 + 0.5*wall-px) + pr` (`pr` = pitch shear) and the body spans `2 * sprite-half-rows` up. That matches the renderer, so near enemies forgive more, far ones need level aim, and the 2x cyberdemon is easiest. `svh` arrives as the world's `:scene-rows`; without it the gate is off. Splash impacts are not gated.

### Hit-marker (crosshair feedback)

A connecting shot stamps `:hit-fx {:kill? :ttl}`: the `+` becomes a red `✗` on a kill or a yellow `×` on a wound for 0.12s. Splash stamps only kills. One-shot feedback, allowed in the [calm 3D view](rendering.md#calm-3d-view-no-decorative-blinks).

## Hostile reticle (issue #458)

`frame-stats` calls `combat/target-in-sights?` once per frame, and the crosshair paints steady red while a shot would connect. It runs the trigger's own selection (`enemy/target-index`, the damage-free half of `shoot`), never a copy.

Lesson: ask the real rule. A reticle on its own approximation drifts from the gun, which is worse than none.

The rule is per weapon: the shotgun asks its cone (`enemy/spread-target-index`), which disagrees with the corridor both ways (0.45 off axis at point blank is inside the corridor, outside the cone; 0.8 off at five units is the reverse). The pistol needs no special case. Splash can still catch an enemy the reticle left white. The reticle answers where the shot goes, not whether the gun is loaded: it stays red during a reload or on an empty mag. Hit-marker and muzzle flash outrank it; paused frames skip it.

## Weapon specializations

- **Pistol** (`:pierce?`, issue #124): `enemy/pierce` damages every enemy along the ray up to the first wall. Its edge over the higher-DPS chaingun is a lined-up corridor.
- **Shotgun** (`:spread?`, issue #125): the nearest enemy in the cone takes 3, then up to 2 more (index order) take 1. A slow crowd weapon.
- **Chainsaw**: `:no-ammo?` (no mag, `R` does nothing), `:max-range 1.5`, `:movement-mul 0.5` while the cooldown runs. Damage type `:melee`.
- **Incinerator** (issue #122): the only `:fire` weapon. Fast (0.06s) and short (`:max-range 4.0`), a swarm-clearer that fire-resistant types ignore.

### Splash: BFG (slot 5), rocket (slot 7)

Specs with `:splash-radius` go through `bfg-fire`:

1. `beam-impact`: the nearest alive enemy on the ray, else the wall, capped at range. Returns the point and the struck enemy's index (-1 on a wall).
2. `splash`: the struck enemy takes the direct `:damage`; every other alive enemy within `:splash-radius` takes `:splash-damage`. Berserk scales both. Survivors wake; no pain roll.
3. Kills bump kills and streak and unlock the boss door. Hit-stop is 0.16s if the L10 boss died, else 0.07s on any kill. No loot.

BFG: 10 direct, 6 splash, radius 3.0, `:plasma`. Rocket: 4 direct, 3 splash, radius 2.0, `:ballistic`. A cosmetic tracer flies to the impact over 0.32s. Shake is `shake-fire-secs` 0.08 on a whiff or `shake-blast-secs` 0.16 on a connecting blast, times `radius / 2`.

## Damage resistance

A catalog entry may carry `:resists #{...}`; `enemies/resists?` zeroes that damage type while the hit feedback still fires. Caco, baron, archvile and mancubus resist `:fire`. Nothing resists `:ballistic`, `:melee` or `:plasma`.

## Taking damage

`damage-step` decays every timer, then lands a contact hit when the player is not immune and an alive enemy whose state attacks (`:aware` or `:attacking`, per `enemy_ai/state-spec`) is within 0.7 units. Projectiles land through `hit-player-at` ([monsters.md](monsters.md#ranged-casters-projectiles)). Both call `apply-hit`, and `player-immune?` (i-frames, invuln, `--god`) gates both.

`:lives` is the half-heart pool (max 10). `hit-damage-for` costs 2 for caco, baron, archvile and mancubus, 3 for the cyber, 1 otherwise. `apply-hit`:

- Armor absorbs the whole hit (one point, no HP); otherwise lose the damage.
- One `try-move` of 0.9 units away from the attacker; a wall blocks it outright.
- 1.0s i-frames, a 0.03s dark-red flash (issue #465: red is Doom's pain language, and the old white wash was the last full-screen strobe), 0.25s shake.
- `:hurt-side` (front/back within 30 degrees, else left/right) for the edge blood columns, `:hurt-dir` (octant 0-7, issue #201) for the damage arc.

## Hit-stop (kill weight)

`hit-stop-for` freezes the world by the victim's max HP: none for 1-2, 0.07s for 3-9, 0.16s for 10+ (only the 50 HP boss). While `:hit-stop-secs` runs, `tick-world` skips the gameplay step and render holds the frame. Trash kills skip it so auto-fire stays fluid.

## Berserk pickup

Issue #127. `arm-berserk` sets 18s on `:berserk-secs` (refresh, not stack) and heals to 10 HP without lowering a soulsphere surplus. `berserk-mul-for` scales `:melee` x6 and every other type x2: the chainsaw shreds, guns get a nudge.

## Kill loot

`src/core/loot.phel`, single-target kills only. One uniform roll:

| Band | Drop |
|------|------|
| [0.00, 0.22) | ammo box tagged with a random owned weapon other than the pistol (pistol if nothing else is owned) |
| [0.22, 0.30) | armor |
| [0.30, 0.35) | heart, only below max HP; at full HP the band drops nothing |
| [0.35, 1.00) | nothing |

`pickup-ammos` refills the tagged weapon; untagged level boxes refill the active one.

`:no-ammo?` weapons (the chainsaw) never get an ammo box: `pick-loot-weapon` skips them, and a level box picked up while holding the chainsaw feeds the pistol. `:ammo-per-box 0` alone would not do it, since `0` is truthy in Phel and nothing falls back.
