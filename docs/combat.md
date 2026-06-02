# Combat

Hitscan + damage timing + i-frames. `src/core/combat.phel`. Pure: no side effects. Sound cues (gun report, kill, pain, dry-fire click) are enqueued as `{:name :vol}` events on the world's per-frame `:sfx` queue; `commands/play` drains it after `tick-world` and emits via `play-sfx!`, gated by `(:sound-on world)`.

## Tunables

| Constant | Value | Notes |
|----------|-------|-------|
| `shot-hit-radius` | 0.5 | Off-axis hitscan tolerance (half-cell) |
| `shot-max-range` | 12.0 | Max hitscan distance (world units) |
| `shot-knockback-distance` | 1.0 | Push distance per wounding hit |
| `touch-damage-dist` | 0.7 | Contact damage range |
| `iframe-seconds` | 1.0 | Post-hit invulnerability window |
| `fire-anim-seconds` | 0.09 | Muzzle flash visibility |
| `fx-ttl-seconds` | 0.7 | Blood splatter lifetime |
| `flash-seconds` | 0.05 | White impact jolt |
| `heat-per-shot` | 0.30 | Overheat per shot (jam at 1.0); dormant - no weapon overheats |
| `jam-seconds` | 0.7 | Jam lockout duration; dormant (see Pistol below) |
| `mag-size` | 10 | Pistol default magazine capacity |
| `max-reserve` | 50 | Pistol default reserve cap |
| `reload-cooldown-seconds` | 1.2 | Pistol reload duration |
| `armory-reserve` | 9999 | --armory cheat reserve cap |

Per-weapon overrides in `weapons.phel`: mag-size, fire-cooldown, reload-duration, reserve-cap, ammo-per-box, damage, auto-fire?, overheats?.

## Magazine + reload

`can-fire?` requires: `:mag > 0`, `:fire-cooldown <= 0`, `:jam-secs <= 0`, `:reload-cooldown <= 0`. Empty mag silently fails; player presses **R**.

`reload` draws `min(mag-size - mag, :ammo-reserve)` into `:mag`, arms `:reload-cooldown`. Three no-ops (reload in progress, mag full, reserve empty) preserve world identity.

`apply-heat` decrements `:mag` by one per shot. `decay-timers` ticks `:reload-cooldown` each frame.

Empty trigger pulls → `empty-trigger-pull`: arm `:empty-click-secs` (0.8s), play `:click` sfx. Render paints `CLICK · press R to reload` or `OUT OF AMMO`.

The periodic `press R to RELOAD` nag is gated by the pure `reload-reminder-visible?` (`io/render.phel`). It arms on the remaining-mag **fraction** (`<= reload-reminder-frac`, 0.3) rather than an absolute count, so a 10-round pistol and a 4-round shotgun both nag at "nearly empty". Single-round mags (BFG, chainsaw: `mag-size <= 1`) reload every shot by design, so the nag is suppressed entirely. It is also suppressed while reloading, when the reserve is dry, during the dry-fire CLICK, and on viewports under 9 rows.

Fresh run starts with 30 reserve (3 mags); cap 50. Pickups refill (see [`level-system.md`](level-system.md)).

## Kill loot

On kill, roll uniform float through `roll-loot-kind`:

| Band | Drop | Notes |
|------|------|-------|
| [0.00, 0.15) | `:ammo` | Random owned weapon (excludes pistol); falls back to pistol |
| [0.15, 0.22) | `:armor` | Absorb one hit |
| [0.22, 0.25) | `:heart` | +1 life (suppressed at max health) |
| [0.25, 1.00) | nothing | ~75% of kills |

Drops push into `:hearts` / `:armors` / `:ammo-boxes` vectors (same as level spawns). `pickup-ammos` reads box's `:weapon` tag and refills that weapon's reserve.

## Hitscan shooting

Two-step scan per shot:

1. **Wall ray** along player facing via `cast-ray`, returns distance to first wall.
2. **Enemy scan**: project each alive enemy onto heading (dot product). Nearest one in front, closer than wall, within max-range, within hit-radius perpendicular = hit. Flip `:alive false`, arm respawn timer (3-6s uniform).

On hit: `play-shot-sfx` emits weapon report + kill cue (distance-attenuated). `on-shot-hit` bumps `:kills`, chains streak, pushes blood splatter, arms hit-stop if tough enemy dies.

On miss: weapon report only.

Killed enemy stays in vector with `:respawn-after` timer. See [monsters.md](monsters.md).

Weapons flagged `:pierce?` (the pistol) or `:spread?` (the shotgun) take a different path: `pierce` (in `enemy.phel`) damages **every** enemy in the line, while `spread-shoot` damages a primary plus grazed neighbours in a cone. Both aggregate kills through the shared `finish-multikill` tail (blood + sfx on the nearest target, hit-stop sized by the meatiest kill, no per-enemy loot).

### Blood splatter

`{:x :y :ttl fx-ttl-seconds}` pushed into `:fx`. Render paints RGB gradient (bright-pink → mid-red → dim-red).

## Damage + knockback

`damage-step` decays timers each frame, then applies touch hit if no i-frames and alive enemy in range (0.7 units).

`:lives` is a half-heart HP pool: `state/max-lives` = 10, drawn as 5 hearts of 2 HP each. A hit costs `enemy-hit-damage` HP by attacker type - 1 (half heart) for light melee, 2 (full heart) for heavy bruisers + casters (caco/baron/archvile/mancubus), 3 for the cyberdemon boss; `hit-damage-for` falls back to 1 for unlisted/nil types.

On contact:
- Armor absorbs the whole hit (drop one armor unit, no life lost regardless of damage size); otherwise lose `hit-damage-for (:type attacker)` HP.
- Arm 1.0s i-frames (prevent double-drain).
- 0.05s white flash (impact jolt).
- Knockback away from attacker (try 1.0 / 0.5 / 0.25 units on wall collision).
- Stamp `:hurt-side` (`:front` / `:back` / `:left` / `:right`) for directional red band at impact edge. Front/back use ±30° wedges around facing; everything else routes to left/right.

Both `take-damage` (contact, reads the nearest attacker's `:type`) and `hit-player-at` (projectile, the bolt carries its caster's `:dmg`) share `apply-hit`. `player-immune?` gates both: i-frames, invuln sphere, or dev god mode.

## Hit-stop (kill weight)

On kill, stamp `:hit-stop-secs` based on enemy HP via `hit-stop-for`:

| Enemy max-HP | Freeze |
|---|---|
| 1-2 | none (fast cleanup) |
| 3-9 | 0.07s (tough) |
| 10+ | 0.16s (boss) |

While `:hit-stop-secs > 0`, `play/tick-world` skips entire gameplay step (physics / AI / projectiles / shooting / damage); render holds frozen frame. Only tough kills freeze, so rapid-fire stays fluid.

## Weapon specializations

### Pistol (pierce, slot 1)

The pistol's identity (issue #124) is the `:pierce?` flag: its round passes through and damages every enemy along the ray, not just the nearest. That is its edge over the strictly-higher-DPS chaingun (20 vs 8 DPS) - a row of lined-up enemies in a corridor takes one hit each, where the chaingun would have to chew through them one at a time. The chaingun keeps the single-target sustained-spray niche; neither dominates.

**Overheat dropped.** The pistol used to be the only `:overheats?` weapon (jam at heat 1.0). Jamming the weapon the player is *forced* onto when out of ammo is anti-fun, so overheat was removed from the pistol. The chaingun's mag burn and the shotgun's slow cadence are brake enough for those, so no weapon overheats now. The generic `:overheats?` / heat / jam machinery stays in place (data-driven, dormant) for any future weapon that opts in; `heat-per-shot` and `jam-seconds` are unused until then.

### Shotgun (spread, slot 2)

The shotgun's `:spread?` flag makes it a multi-target graze (issue #125). Instead of one big single-target hit, the nearest enemy inside a cone (`:spread-half-angle`, default `shotgun-spread-half-angle` ~17 degrees) takes the full `:damage` (3); up to `:spread-targets - 1` other enemies in the cone are grazed for the smaller `:graze-damage` (1). `spread-shoot` (in `enemy.phel`) finds the primary, then grazes others in index order up to the cap; `spread-fire` routes the result through the shared `finish-multikill` tail (blood + sfx on the primary, hit-stop sized by the meatiest kill, no per-enemy loot). This turns the slow-cadence shotgun into a crowd weapon distinct from the chaingun's single-target spray.

### Chainsaw (melee, slot 4)

Flags branch combat:

| Flag | Effect |
|------|--------|
| `:no-ammo? true` | Skip mag check + decrement; `reloading?` returns false |
| `:max-range 1.5` | Hit only 1.5-cell radius (0.10s cooldown) |
| `:movement-mul 0.5` | Halve speed while firing |

Damage type `:melee`. 1 damage/tick stacks with berserk (2/tick during rage).

### BFG (splash, slot 5, found L7)

Spec carries `:splash-radius` + `:splash-damage`. Routes to `bfg-fire` instead of hitscan.

Flow:
1. `beam-impact` finds impact: nearest alive enemy along ray, or wall (both capped at range).
2. `splash` damages every alive enemy within splash-radius. Survivors wake + flash; no pain stagger.
3. Bump `:kills` by body count, chain streak, arm hit-stop (boss-length if cyber died), unlock boss door if applicable. No per-enemy loot.

Damage type `:plasma` (bypasses fire-resist). Single-action, 1.2s cooldown, mag 1 / reserve 20.

### Incinerator (fire, slot 6, found L6)

The only `:fire` weapon (issue #122). Hitscan flame stream: `:damage 1`, fast `:fire-cooldown 0.06`, mag 40, reserve cap 120, short `:max-range 4.0`. Fast auto-fire makes it a swarm-clearer, but the short reach keeps it out of the chaingun's long-range niche.

Its point is the damage type: caco / baron / archvile / mancubus carry `:resists #{:fire}`, so the flame does **zero** to them. The incinerator is the weapon that makes the resist system bite (before it, no player weapon ever emitted a resisted type). Switch off it for fire-resist heavies; use plasma (BFG), ballistic, or melee on those.

### Rocket launcher (splash, slot 7, found L5)

Mid-tier AoE (issue #123): fills the gap between the chaingun (no splash) and the rare BFG nuke. Carries `:splash-radius 2.0` + `:splash-damage 3`, so it routes through the same `bfg-fire` path as the BFG, with smaller numbers (BFG is radius 3.0 / splash 6). Single-action, `:fire-cooldown 0.9`, mag 1 / reserve cap 30. Damage type `:ballistic` (an explosive shell), so no enemy resists it. The everyday crowd tool; the BFG stays the rare panic button.

## Berserk pickup

Berserk sphere (`Ω` glyph, 1-in-8 levels):

1. `pickup-berserks` removes sphere, plays `:berserk` sfx, calls `arm-berserk`.
2. `arm-berserk` stamps `:berserk-secs` to 20s (refresh, not stack).
3. `decay-timers` ticks down; `fire-shot` multiplies weapon damage by 2 while active.
4. Render paints red pulsing border (suppressed by i-frames, which take priority).

## Damage resistance

`shoot` reads active weapon's `:damage-type` and passes to `enemy/shoot`. If target type has `:resists` set containing that type, damage is 0. Hit registration (splatter, flash, sfx, wake) still fires.

Current resistances:
- caco, baron, archvile, mancubus: `:fire`

The incinerator (slot 6) deals `:fire`, so it is the weapon those four mobs resist (zero damage). The BFG deals `:plasma`, which is NOT in any resist set, so it bypasses the fire resist by design. Pistol / shotgun / chaingun deal `:ballistic` and the chainsaw deals `:melee`; none of those are resisted by any current enemy.

## Nightmare respawn

`--difficulty=nightmare` stamps `:nightmare? true` on every enemy. Two effects:

- Respawn cooldown draws tighter band (1.0-2.0s vs 3.0-6.0s).
- `:max-concurrent` cap skips, so L10 boss-room minion swarm lives without 1-alive-at-a-time limit.

## Shot knockback

Every wounding hit (non-killing) pushes enemy ~1 cell back along shot direction. Walls clamp via half-step / quarter-step fallback. Killing blows skip knockback so corpse stays on death cell for loot drops.
