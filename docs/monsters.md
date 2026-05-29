# Monsters

- `src/core/enemies.phel` - type catalog (visuals + default HP)
- `src/core/enemy.phel` - record + spawn + chase step
- `src/core/enemy_ai.phel` - AI state machine (LOS-gated wake)
- Visual rendering in `io/render.phel` (per-enemy `:type` lookup).

## Catalog (`enemy-types`)

Each entry has: `:name :default-lives :head-code :body-code :legs-code :body-glyph :body-glyph-alt :body-glyph-fg :face :face-alt :face-attack`. Render reads them by kw per enemy.

| Kw | Name | Default HP | Head | Body | Face | Notes |
|---|---|---|---|---|---|---|
| `:imp`      | imp        | 1 | 196 red    | 124 red    | ●/◯ yellow      | L1 default |
| `:demon`    | demon      | 2 | 165 magenta| 126 purple | ▼/▾ white       | L2 default |
| `:caco`     | cacodemon  | 3 | 51  cyan   | 38  cyan   | ◉/◎ black       | L3 default |
| `:baron`    | baron      | 4 | 46  green  | 34  green  | Λ/λ black       | L4 default |
| `:cyber`    | cyberdemon | 5 | 240 grey   | 124 red    | ■/□ red blink   | L5 default |
| `:spectre`  | spectre    | 3 | 117 cyan   | 67  steel  | ○/◌ white       | L6+ stub |
| `:revenant` | revenant   | 4 | 255 bone   | 245 grey   | ☠/◔ black       | L6+ stub |
| `:archvile` | archvile   | 5 | 208 orange | 166 amber  | ∺/≋ black       | L6+ stub |
| `:mancubus` | mancubus   | 4 | 137 tan    | 94  brown  | ═/─ black       | L6+ stub |
| `:pinky`    | pinky      | 2 | 213 pink   | 199 hot-pk | ≣/≡ black       | L6+ stub |

Adding a new type = append one entry to `enemy-types`. Adding a level that uses it = one entry in `levels` (see [level-system.md](level-system.md)).

Each enemy carries `:lives` / `:max-lives` / `:type`. `enemy/shoot` drops `:lives` per hit; only flips `:alive false` and arms respawn when 0. `damage-ratio = 1 - lives/max-lives` darkens the body shade - wounded enemies read as "bloodied" from across the room without a HUD bar. Non-killing hits also stamp `:hit-flash-secs 1.2` so a yellow HP digit floats above the head.

## Stats comparison

Combat numbers per type. HP is the catalog `:default-lives` (a level may override). Speed = level `:chase` x the type's `enemy/type-speed-mul` (1.0 when unlisted). Range / windup / cooldown come from `enemy_ai/attack-spec` (melee) or `enemy_ai/caster-spec` (ranged); types not listed in `attack-spec` use `default-attack-spec` (1.4 / 0.4 / 1.0). Cooldown shown is the level-1 value: it shrinks with depth (see "Depth-scaled aggression" below). Every hit, melee or bolt, costs the player exactly 1 unit (armor first, else a life).

| Type | Debut | HP | Speed x | Attack | Range (u) | Windup (s) | Cooldown (s) | Bolt spd | Resists |
|---|---|---|---|---|---|---|---|---|---|
| `:imp`      | L1    | 1 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | -      |
| `:demon`    | L2    | 2 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | -      |
| `:caco`     | L3    | 3 | 0.70 | ranged | 7.0 | 0.6 | 1.0 | 2.5 | `:fire` |
| `:baron`    | L4    | 4 | 0.65 | ranged | 8.0 | 0.8 | 1.3 | 3.0 | `:fire` |
| `:cyber`    | L5    | 5 | 0.55 | melee  | 1.8 | 0.8 | 1.8 | -   | -      |
| `:spectre`  | L6    | 3 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | -      |
| `:revenant` | L7    | 4 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | -      |
| `:archvile` | L8    | 5 | 1.0  | ranged | 6.5 | 0.5 | 1.1 | 4.0 | `:fire` |
| `:mancubus` | L8    | 4 | 1.0  | melee  | 1.6 | 0.5 | 1.3 | -   | `:fire` |
| `:pinky`    | L9    | 2 | 1.0  | melee  | 1.4 | 0.3 | 0.8 | -   | -      |

Reading it:

- **Range** is melee reach (~1 cell) for everyone except the casters, who commit from across the room. **Windup** is the frozen telegraph before the strike/bolt; **cooldown** is the gap before they can attack again (smaller = more pressure).
- **Casters** (`:caco`, `:baron`, `:archvile`) are the types that fire projectiles (`caster-spec`). They move slower than the melee rushers to stay fair: keep distance and strafe the bolts, or close in and trade the dodge window for melee range. Bolt speed is world-units/sec (deliberately low so a fireball is dodge-able, not near-hitscan). The archvile is the escalated caster: shortest windup, fastest bolt (4.0).
- `:cyber` is the heaviest: top HP, slowest move (0.55x), long telegraph. The L10 boss spawns it with 50 HP.
- `:pinky` is the glass rusher: low HP, full speed, shortest windup + cooldown.
- **Resists** zeroes incoming damage of that type (`enemy/shoot` checks `enemies/resists?`). `:fire` resistance is why the BFG's `:plasma` shot matters against caco / baron / archvile / mancubus.

### Depth-scaled aggression

The cooldowns above are the level-1 baseline. `build-world` stamps each enemy with an `:aggression` cooldown multiplier from `enemy_ai/aggression-for level`: `1.0` on L1, dropping `aggression-per-level` (0.03) each level and clamped at `aggression-floor` (0.7). `tick-attack` multiplies the per-type cooldown by it, so the same monster recovers faster and attacks more often the deeper you are (L10 ~= 0.73x cooldown). Windup is left alone, so the telegraph stays honest at every depth.

## Spawning

- `spawn-enemies grid n min-dist px py [max-lives [type-kw]]` - single-type rooms.
- `spawn-enemies-mixed grid specs min-dist px py` - multi-type. Spec shape: `{:type :count [:lives N] [:max-concurrent K]}`. Each enemy carries `:type` for render lookup and optional `:max-concurrent` cap. Used by `build-world` whenever a level's `:enemies` field is a vector (and for the L10 boss arena where `{:type :cyber :count 1 :lives 50}` + `{:type :imp :count 2 :max-concurrent 1}` paints one boss with 2 minions but only 1 alive at a time).

## AI state machine

Each enemy carries `:state` + optional `:lkp` (last-known player position). State gates move + contact damage:

| State | Move | Attack | Notes |
|-------|------|--------|-------|
| `:dormant` | no | no | Waiting for LOS / noise |
| `:aware` | yes | yes | Has LOS to player |
| `:hunting` | yes | no | Lost LOS, walking to `:lkp` |
| `:pain` | no | no | Stagger flinch (~0.3s) |
| `:attacking` | no | yes | Telegraph before melee/projectile |
| `:wander` | yes | no | Opt-in patrol, reacts to wake events |

Test defaults to `:aware`. Real spawns use `:dormant` (sneaking-friendly).

**`:dormant`** - Passive until LOS, noise, or being shot wakes to `:aware` or `:hunting`.

**`:aware`** - Full chase + contact damage. `:lkp` refreshes every frame. Lose LOS → `:hunting`.

**`:hunting`** - Walks frozen `:lkp`. Lose LOS → stays `:hunting`. Regain LOS → `:aware`. Reach `:lkp` + still no LOS → `:dormant` (give up).

**`:pain`** - Stagger on hit (per-type roll; imp 35%, cyber 5%). Freezes for `pain-stagger-secs` (0.3s). `tick-pain` decays timer; expiry → `:aware`. Heavy monsters stagger rarely; fragile ones on nearly every shot.

**`:attacking`** - Telegraphed strike window. When `:aware` + in range + cooldown done, arm `:attack-windup-secs`. Enemy freezes (visible telegraph) but still deals contact damage. Windup expiry → `:aware` + cooldown arm. Melee types have one `attack-spec`; casters have different ranges/windup/cooldown.

**`:wander`** - Opt-in patrol. `start-wander` rolls angle + timer. `tick-wander` refreshes angle per cycle. Wakes same as `:dormant` (LOS → `:aware`, noise → `:hunting`).

### Ranged casters (projectiles)

`:caco`, `:baron`, and `:archvile` fire projectiles on windup-release instead of meleeing. Each has a longer attack range (caco 7.0, baron 8.0, archvile 6.5), a bolt speed kept low enough to dodge (caco 2.5, baron 3.0, archvile 4.0 world-units/sec), and a tight cooldown (caco 1.0s, baron 1.3s, archvile 1.1s) for sustained pressure. The archvile is the escalated caster: shortest windup (0.5s) and fastest bolt, so L8 ranged steps up from the caco / baron lobs. Telegraphed strike window same as melee: freeze, windup, release → `:fire-now` flag. Melee enemies leave the flag false.

Speed tuning: `type-speed-mul` scales level chase by 0.7 (caco), 0.65 (baron), 0.55 (cyber). Melee types unlisted → full 1.0 speed. Ranged balance: distance + strafe to dodge bolts; close in to trade dodge window for melee pressure.

Projectile pipeline (runs between `tick-enemies` + `damage-step` in `play/tick-world`):
- `spawn-from-enemies`: harvest `:fire-now`, aim bolt at player, clear flag.
- `step`: march bolt along velocity; drop on solid cell or after 4s ttl.
- `resolve-hits`: hit player if bolt within 0.6 units + player not immune. I-frames absorb burst. Bolt + contact can't both land one frame.

Render: white-hot core on orange glow. Occluded by walls only (always reads in front of caster).

Casters still melee on contact (touch test ignores range), so cornering is dangerous.

### Wake triggers

**LOS** - Every tick, `observe` casts ray from enemy to player via `cast-ray`. Wall blocks before player cell → no LOS. Ray capped at `max-depth` (12 units). Beyond = "too far to see".

**Being shot** - `shoot` stamps `:state :aware` on hit target unconditionally.

**Noise** - `fire-shot` BFS from player cell up to 3 cells through open floor only (doors + walls block). Dormant enemies in visited cells → `:hunting` at fire origin; hunters refresh `:lkp` to fresher origin; aware enemies unchanged (already tracking).

### Chase + target selection

Per alive enemy: `target-pos` picks walk target based on state - `:aware` uses live player, `:hunting` uses frozen `:lkp`, `:dormant` → nil (no step).

`step-toward` then:
1. Heading = atan2 (enemy → target).
2. Try stepping `speed * dt` along heading.
3. Wall collision: try ±45°, ±90°, ±135° offsets (slide around corners).

Stop at 0.6 units (no pile-up). Arrival at `:lkp` = 0.9 units → `:dormant`.

### Breaking contact

Player ducks around corner while aware enemy chases:
1. Aware → chase, `:lkp` refreshes each frame.
2. Duck behind wall → LOS drops, state → `:hunting`, `:lkp` freezes.
3. Hunter walks to frozen `:lkp`. Player keeps running.
4. Hunter arrives at `:lkp` with no LOS → `:dormant`. Escape.

## Respawn

Killed enemy stays in vector with `:alive false` + `:respawn-after` timer (uniform 3-6s). Nightmare enemies use tighter band (1-2s).

`tick-one` decays timer; on expiry, spawn at random cell ≥ 3.0 units away. If no slot found, bump timer to 0.5s + retry next frame (no ambush spawn).

Optional `:max-concurrent` cap (per-type) enforces max-alive count. Revival checks live count; respawn delayed until a sibling dies. `:type` preserved across respawn.

L10 boss death uses 7-arity `advance es g x y dt sp revive?` with `revive? false` to freeze all timers. Victory lap unbothered by fresh spawns.

## Rendering

Sprite column splits into 3 vertical zones (head / body with glyph / legs). Face glyph overlays enemy's centre column at head-mid. Occluded by walls.

**Distance fade**: `t = min(0.85, (dist/max-depth)²)`. RGB cube (16-231) scaled by `(1-t)`; grayscale (232-255) pulled toward 232. Squared curve keeps close vivid; fade past mid-range; capped at 0.85 for silhouette.

**Idle face animation**: Two glyphs per type (`:face` + `:face-alt`). Wall-clock sin wave at 3 rad/sec (~2s cycle). All enemies of a type pulse in sync.

**Aggro pulse**: Within 1.8 units (just over 2× touch-dist), head paints SGR blink + skips fade. Steady face + pulsing head = danger cue.

**Colors stored as integer codes** (`196` not `"\e[48;5;196m "`): `fade-256` needs raw codes to calculate fade dynamically. Compose at paint time, reuse code for face BG attribute.
