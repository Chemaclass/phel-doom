# Combat

Hitscan + damage timing + i-frames. `src/core/combat.phel`. Pure: no side effects. Sound cues (gun report, kill, pain, dry-fire click) queue as `{:name :vol}` on the world's per-frame `:sfx`; `commands/play` drains it after `tick-world` and emits via `play-sfx!`, gated by `(:sound-on world)`.

## Tunables

| Constant | Value | Notes |
|----------|-------|-------|
| `shot-hit-radius` | 0.5 | Off-axis hitscan tolerance (half-cell) |
| `shot-max-range` | 12.0 | Max hitscan distance (world units) |
| `shot-knockback-dist` | 1.0 | Push distance per wounding hit |
| `touch-damage-dist` | 0.7 | Contact damage range |
| `iframe-seconds` | 1.0 | Post-hit invulnerability window |
| `shake-damage-secs` | 0.25 | Screen-shake on taking a hit |
| `shake-fire-secs` | 0.08 | Screen-shake base for a splash-weapon launch (x splash-radius/2) |
| `shake-blast-secs` | 0.16 | Screen-shake base for a connecting splash blast (x splash-radius/2) |
| `fire-anim-seconds` | 0.13 | Muzzle flash visibility |
| `fx-ttl-seconds` | 0.7 | Blood splatter lifetime |
| `flash-seconds` | 0.05 | White impact jolt |
| `heat-per-shot` | 0.30 | Overheat per shot (dormant - no weapon overheats) |
| `jam-seconds` | 0.7 | Jam lockout duration (dormant) |
| `mag-size` | 10 | Pistol default magazine capacity |
| `reload-cooldown-seconds` | 1.2 | Pistol reload duration |
| `armory-reserve` | 9999 | --armory cheat reserve cap |

Per-weapon overrides in `weapons.phel`: mag-size, fire-cooldown, reload-duration, reserve-cap, ammo-per-box, damage, auto-fire?, overheats?.

## Magazine + reload

`can-fire?` requires: `:mag > 0`, `:fire-cooldown <= 0`, `:jam-secs <= 0`, `:reload-cooldown <= 0`. Empty mag silently fails; player presses **R**.

`reload` draws `min(mag-size - mag, :ammo-reserve)` into `:mag`, arms `:reload-cooldown`. Three no-ops (reload in progress, mag full, reserve empty) preserve world identity.

`apply-heat` decrements `:mag` by one per shot. `decay-timers` ticks `:reload-cooldown` each frame.

Empty trigger pulls → `empty-trigger-pull`: arm `:empty-click-secs` (0.8s), play the `:click` sfx. Render paints `CLICK · press R to reload` or `OUT OF AMMO`.

The pure `reload-reminder-visible?` (`io/render.phel`) gates the periodic `press R to RELOAD` nag. It arms on the remaining-mag **fraction** (`<= reload-reminder-frac`, 0.3), not an absolute count, so a 10-round pistol and a 4-round shotgun both nag at "nearly empty". Single-round mags (BFG, chainsaw: `mag-size <= 1`) reload every shot by design, so the nag never shows. Also suppressed while reloading, on a dry reserve, during the dry-fire CLICK, and under 9 viewport rows.

A finished reload flashes a one-shot bright-green ` READY! ` at that row for `reload-ready-flash-seconds` (0.30s), so the gun-hot-again moment reads. `tick-world` catches the `:reload-cooldown` `>0 -> <=0` edge, since `damage-step`'s `decay-timers` is the only site ticking it. Pure overlay (`paint-reload-ready`) on the `:reload-ready-secs` timer, suppressed under 9 viewport rows.

Fresh run starts with 30 reserve (3 mags); cap 50. Pickups refill (see [`level-system.md`](level-system.md)).

## Kill loot

The drop economy lives in `src/core/loot.phel` (extracted from `combat.phel`). On a kill, `on-shot-hit` calls `push-kill-loot`, which rolls a uniform float through `roll-loot-kind`:

| Band | Drop | Notes |
|------|------|-------|
| [0.00, 0.22) | `:ammo` | Random owned weapon (excludes pistol); falls back to pistol |
| [0.22, 0.30) | `:armor` | Absorb one hit |
| [0.30, 0.35) | `:heart` | +1 life (suppressed at max health) |
| [0.35, 1.00) | nothing | ~65% of kills |

Drops push into `:hearts` / `:armors` / `:ammo-boxes` vectors (same as level spawns). `pickup-ammos` reads box's `:weapon` tag and refills that weapon's reserve.

## Hitscan shooting

Two-step scan per shot:

1. **Shot ray** along player facing via `cast-ray`, returns distance to the first wall blocker.
2. **Enemy scan**: project each alive enemy onto heading (dot product). Nearest one in front, closer than wall, within max-range, within hit-radius perpendicular, AND vertically on the sprite (see below) = hit. Flip `:alive false`, arm respawn timer (3-6s uniform).

On hit: `play-shot-sfx` emits weapon report + kill cue (distance-attenuated). `on-shot-hit` bumps `:kills`, chains streak, pushes blood splatter, arms hit-stop if tough enemy dies, and stamps the crosshair hit-marker (see below).

### Vertical aim gate (look up/down)

Camera pitch breaks the XY cylinder test alone: a shot would hit any enemy in the horizontal cone while the crosshair points at floor or sky. So each hit is also gated on the crosshair being on the enemy's drawn billboard.

The crosshair sits at screen-centre (`svh/2`); an enemy at distance `d` projects to a sprite of half-height `projection/sprite-half-rows(svh, d, scale)` rows. `pr = projection/pitch-rows((:pitch player), svh)` is the pitch shear in scene rows. The crosshair is on the sprite iff the absolute pitch offset is within those half-rows. The gate (`enemy/vertical-hit?`) wraps the perp test in `shoot`, `pierce`, and `spread-shoot`. `sprite-half-rows` mirrors the renderer's billboard height, so the check is screen-space exact: close enemies (taller sprites) forgive more, distant ones demand near-level aim, and the cyberdemon's 2x sprite is easiest to hold.

The game loop supplies `svh` (scene rows) from `render/scene-rows`; combat stays pure, `svh`/`pr` are plain ints in. A world without `:scene-rows` disables the gate (identical to level aim). `bfg-fire` is splash around an impact, not a crosshair hitscan, so it is not gated.

### Hit-marker (crosshair feedback)

Every connecting shot stamps `:hit-fx {:kill? :ttl}` via `stamp-hit-fx`: `:kill?` true on a killing blow, false on a wound; `:ttl` starts at `hit-marker-seconds` (0.12 s). `decay-timers` ticks it down each frame and clears the field at 0. All three hit tails set it: `on-shot-hit` (single-target), `finish-multikill` (pierce/spread, one stamp per aggregate volley), `bfg-fire` (kill is the hit proxy, splash has no wound-only signal). Render reads `stats[:hit-fx]`; `paint-crosshair` swaps the `+` reticle for a bold-red `✗` on a kill or a bold-yellow `×` on a wound for the ttl window. Single-shot feedback, no strobe, so it stays in the calm 3D view (see [rendering.md](rendering.md#calm-3d-view-no-decorative-blinks)).

On miss: weapon report only, attenuated by distance to the wall hit (near wall loud, far wall / open level quiet).

Killed enemy stays in vector with `:respawn-after` timer. See [monsters.md](monsters.md).

Weapons flagged `:pierce?` (pistol) or `:spread?` (shotgun) take a different path. `pierce` (in `enemy.phel`) damages **every** enemy in the line; `spread-shoot` damages a primary plus grazed neighbours in a cone. Both aggregate kills through the shared `finish-multikill` tail: blood + sfx on the nearest target, hit-stop sized by the meatiest kill, no per-enemy loot.

### Blood splatter

`{:x :y :ttl fx-ttl-seconds}` pushed into `:fx`. Render paints RGB gradient (bright-pink → mid-red → dim-red).

## Damage + knockback

`damage-step` decays timers each frame, then applies touch hit if no i-frames and alive enemy in range (0.7 units).

`:lives` is a half-heart HP pool: `state/max-lives` = 10, drawn as 5 hearts of 2 HP each. A hit costs `enemy-hit-damage` HP by attacker type: 1 (half heart) for light melee, 2 (full heart) for heavy bruisers + casters (caco/baron/archvile/mancubus), 3 for the cyberdemon boss. `hit-damage-for` falls back to 1 for unlisted/nil types.

On contact:
- Armor absorbs the whole hit (drop one armor unit, no life lost whatever the damage size); otherwise lose `hit-damage-for (:type attacker)` HP.
- Arm 1.0s i-frames (prevent double-drain).
- 0.05s dark-red flash (impact jolt, issue #465). Doom's pain language; the white wash it replaced was the last full-screen strobe in the calm 3D view.
- Knockback away from attacker (try 1.0 / 0.5 / 0.25 units on wall collision).
- Stamp `:hurt-side` (`:front` / `:back` / `:left` / `:right`, via `attacker-side`) for the 4-way blood-drip edge columns. Front/back use ±30° wedges around facing; everything else routes to left/right.
- Stamp `:hurt-dir` (octant 0..7, via `attacker-octant`) for the precise 8-way directional damage arc (issue #201). Render paints a centred red bar on the matching edge for the four cardinals, or an L at the matching corner for the four diagonals, so the player reads the exact incoming bearing while i-frames are active. Single-shot feedback, kept in the calm 3D view.

`take-damage` (contact, reads the nearest attacker's `:type`) and `hit-player-at` (projectile, the bolt carries its caster's `:dmg`) share `apply-hit`. `player-immune?` gates both: i-frames, invuln sphere, or dev god mode.

## Hit-stop (kill weight)

On kill, stamp `:hit-stop-secs` based on enemy HP via `hit-stop-for`:

| Enemy max-HP | Freeze |
|---|---|
| 1-2 | none (fast cleanup) |
| 3-9 | 0.07s (tough) |
| 10+ | 0.16s (boss) |

While `:hit-stop-secs > 0`, `play/tick-world` skips the whole gameplay step (physics / AI / projectiles / shooting / damage); render holds the frozen frame. Only tough kills freeze, so rapid-fire stays fluid.

## Weapon specializations

### Pistol (pierce, slot 1)

The pistol's identity (issue #124) is `:pierce?`: the round passes through and damages every enemy along the ray, not just the nearest. That is its edge over the strictly-higher-DPS chaingun (20 vs 8 DPS). A corridor row of lined-up enemies takes one hit each; the chaingun chews through them one at a time. Neither dominates.

The pistol no longer overheats: jamming the fallback weapon when ammo runs out is anti-fun. The chaingun's mag burn and the shotgun's slow cadence brake enough. The generic `:overheats?` / heat / jam machinery remains (data-driven, dormant) for any future weapon that opts in; `heat-per-shot` and `jam-seconds` are unused until then.

### Shotgun (spread, slot 2)

The shotgun's `:spread?` flag makes it a multi-target graze (issue #125). Instead of one big single-target hit, the nearest enemy in a cone (`:spread-half-angle`, default `shotgun-spread-half-angle` ~17 degrees) takes the full `:damage` (3), and up to `:spread-targets - 1` others are grazed for the smaller `:graze-damage` (1). `spread-shoot` (in `enemy.phel`) finds the primary, then grazes the rest in index order up to the cap. `spread-fire` routes the result through the shared `finish-multikill` tail: blood + sfx on the primary, hit-stop sized by the meatiest kill, no per-enemy loot. That makes the slow-cadence shotgun a crowd weapon, distinct from the chaingun's single-target spray.

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

Its point is the damage type. Caco / baron / archvile / mancubus carry `:resists #{:fire}`, so the flame does **zero** to them. It is what makes the resist system bite: before it, no player weapon emitted a resisted type. Switch off it for fire-resist heavies; use plasma (BFG), ballistic, or melee.

### Rocket launcher (splash, slot 7, found L5)

Mid-tier AoE (issue #123), filling the gap between the chaingun (no splash) and the rare BFG nuke. Carries `:splash-radius 2.0` + `:splash-damage 3`, direct-hit damage 4 (so 4 + 3 splash total). Same `bfg-fire` path as the BFG, smaller numbers (BFG is radius 3.0 / splash 6). Single-action, `:fire-cooldown 0.9`, mag 1 / reserve cap 30. Damage type `:ballistic` (explosive shell), so no enemy resists it. The everyday crowd tool; the BFG stays the rare panic button.

## Berserk pickup

Berserk sphere (`Ω` glyph, 1-in-8 levels). Melee-biased, DOOM-style (issue #127): a "go punch everything" surge plus a full heal, not a flat all-weapon buff.

1. `pickup-berserks` removes sphere, plays `:berserk` sfx, calls `arm-berserk`.
2. `arm-berserk` stamps `:berserk-secs` to 18s (refresh, not stack) AND full-heals the player to `max-lives` (never lowering an over-cap soulsphere count).
3. `decay-timers` ticks down. While active, `berserk-mul-for` scales weapon damage by `damage-type`: `:melee` (the chainsaw) gets the big `berserk-melee-mul` (6), every ranged type the modest `berserk-damage-mul` (2). So berserk turns the chainsaw into a tank shredder while only mildly buffing guns.
4. Render paints red pulsing border (suppressed by i-frames, which take priority).

## Damage resistance

`shoot` reads active weapon's `:damage-type` and passes to `enemy/shoot`. If target type has `:resists` set containing that type, damage is 0. Hit registration (splatter, flash, sfx, wake) still fires.

Current resistances:
- caco, baron, archvile, mancubus: `:fire`

The incinerator (slot 6) deals `:fire`, so those four mobs take zero from it. The BFG deals `:plasma`, which is NOT in any resist set, so it bypasses the fire resist by design. Pistol / shotgun / chaingun deal `:ballistic` and the chainsaw deals `:melee`; no current enemy resists either.

## Hostile reticle (issue #458)

`frame-stats` asks `combat/target-in-sights?` once per frame: would a shot fired right now connect? It runs what the trigger runs, `enemy/target-index`, the damage-free half of `enemy/shoot`: same aim angle, wall probe, weapon range, hit radius and vertical billboard gate. The crosshair paints steady red while the answer is yes.

Asking the real rule beats re-deriving it. Since #243 a shot lands only when the crosshair is on the drawn sprite, so aiming slightly at floor or sky misses, and that miss read as lag. A reticle on its own approximation would drift from the gun about where the shot goes, which is worse than no reticle. Hit-marker, wound and muzzle-flash states still outrank the tint, being newer information.

The rule is per weapon, since the guns do not share one. The shotgun fires a cone with no perpendicular corridor (`enemy/spread-target-index`, the damage-free half of `spread-shoot`). The two rules disagree both ways at shotgun range: 0.45 off axis at point blank is inside the corridor, outside the cone; 0.8 off axis at five units is outside the corridor, inside the cone. The piercing pistol needs no special case: `pierce` gates each enemy on exactly the single-target predicate set, so "some enemy passes" is the same question. Splash weapons are the loose end: red still means the blast connects, but it can also catch an enemy the reticle left white, since it clips everything near the impact.

It answers where the shot goes, not whether the trigger works: an empty mag or a running reload keeps the target under the crosshair and the reticle red. The dry CLICK and the reload prompt own the ammo story, and a reticle dropping out mid-reload would read as the target having moved. Paused frames skip the probe.

## Nightmare respawn

`--difficulty=nightmare` stamps `:nightmare? true` on every enemy. Two effects:

- Respawn cooldown draws a tighter band (1.0-2.0s vs 3.0-6.0s).
- `:max-concurrent` cap skips, so the L10 boss-room minion swarm lives without a 1-alive-at-a-time limit.

## Shot knockback

Every wounding hit (non-killing) pushes the enemy ~1 cell back along shot direction. Walls clamp via half-step / quarter-step fallback. Killing blows skip knockback, so the corpse stays on the death cell for loot drops.
