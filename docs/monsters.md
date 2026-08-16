# Monsters

- `src/core/enemies.phel` - type catalog (visuals + default HP)
- `src/core/enemy.phel` - record + spawn + chase step (the body)
- `src/core/enemy_ai.phel` - AI state machine, LOS, attack windows (the brain)
- Visual rendering in the `io/render` layer (`render/frame-math` projects sprites, `render/paint` draws faces), keyed by per-enemy `:type`.

## Catalog (`enemy-types`)

Ten types. Each entry carries `:name :default-lives :head-code :body-code :legs-code :body-glyph :body-glyph-alt :body-glyph-fg :face :face-alt :face-attack`. Render reads them by kw per enemy.

| Kw | Name | Default HP | Head | Body | Face | Notes |
|---|---|---|---|---|---|---|
| `:imp`      | imp        | 1 | 196 red    | 124 red    | ●/◯ yellow      | L1 default |
| `:demon`    | demon      | 2 | 165 magenta| 126 purple | ▼/▾ white       | L2 default |
| `:caco`     | cacodemon  | 3 | 51  cyan   | 38  cyan   | ◉/◎ black       | L3 default |
| `:baron`    | baron      | 4 | 46  green  | 34  green  | Λ/λ black       | L4 default |
| `:cyber`    | cyberdemon | 5 | 240 grey   | 124 red    | ■/□ red blink   | L5 default |
| `:spectre`  | spectre    | 3 | 117 cyan   | 67  steel  | ○/◌ white       | L6+ |
| `:revenant` | revenant   | 4 | 255 bone   | 245 grey   | ☠/◔ black       | L6+ |
| `:archvile` | archvile   | 5 | 208 orange | 166 amber  | ∺/≋ black       | L6+ |
| `:mancubus` | mancubus   | 4 | 137 tan    | 94  brown  | ═/─ black       | L6+ |
| `:pinky`    | pinky      | 2 | 213 pink   | 199 hot-pk | ≣/≡ black       | L9+ |

Adding a new type: append one entry to `enemy-types` and add a level that uses it.

Each enemy carries `:lives`, `:max-lives`, `:type`. Shots decrement `:lives`; death flips `:alive false` + arms respawn timer. `damage-ratio = 1 - lives/max-lives` darkens the body - wounded enemies read as "bloodied" without a HUD bar. Wounds stamp `:hit-flash-secs 1.2` so a yellow HP digit floats above the head.

## Stats comparison

Combat numbers per type. HP is the catalog `:default-lives` (a level may override). Speed = level `:chase` x the type's `enemy/type-speed-mul` (1.0 when unlisted). Range / windup / cooldown come from `enemy_ai/attack-spec` (melee) or `enemy_ai/caster-spec` (ranged); types not listed in `attack-spec` use `default-attack-spec` (1.4 / 0.4 / 1.0). Cooldown shown is the level-1 value: it shrinks with depth (see "Depth-scaled aggression" below). Dmg is the half-heart HP a hit costs the player (`combat/enemy-hit-damage`); the pool is 10 HP = 5 hearts of 2 HP each, so 1 = half a heart. Armor absorbs a whole hit regardless of size.

| Type | Debut | HP | Speed x | Attack | Range (u) | Windup (s) | Cooldown (s) | Bolt spd | Dmg | Resists |
|---|---|---|---|---|---|---|---|---|---|---|
| `:imp`      | L1    | 1 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | -      |
| `:demon`    | L2    | 2 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | -      |
| `:caco`     | L3    | 3 | 0.70 | ranged | 7.0 | 0.6 | 1.0 | 2.5 | 2 | fire   |
| `:baron`    | L4    | 4 | 0.65 | ranged | 8.0 | 0.8 | 1.3 | 3.0 | 2 | fire   |
| `:cyber`    | L5    | 5 | 0.55 | melee  | 1.8 | 0.8 | 1.8 | -   | 3 | -      |
| `:spectre`  | L6    | 3 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | -      |
| `:revenant` | L7    | 4 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | -      |
| `:archvile` | L8    | 5 | 1.0  | ranged | 6.5 | 0.6 | 1.1 | 3.4 | 2 | fire   |
| `:mancubus` | L8    | 4 | 1.0  | melee  | 1.6 | 0.5 | 1.3 | -   | 2 | fire   |
| `:pinky`    | L9    | 2 | 1.0  | melee  | 1.4 | 0.3 | 0.8 | -   | 1 | -      |

Reading the table:

- **Range** is melee reach for everyone except casters (who commit from across the room). **Windup** is the freeze-frame telegraph. **Cooldown** is the gap before the next attack (smaller = more pressure).
- **Dmg** by role: light melee (1 half-heart), heavy melee + casters (2 full hearts), cyber boss (3 = 1.5 hearts). Same damage whether melee or bolt.
- **Casters** (caco, baron, archvile) fire projectiles. They move slower to stay fair: keep range and strafe bolts, or close for melee pressure. Bolt speed is low enough to dodge. The archvile is the escalated caster: fastest bolt (3.4) + tightest range, but its windup (0.6s) matches the caco so the telegraph reads reactable.
- Cyber is the heaviest: most HP, slowest move (0.55x), longest telegraph. The L10 boss spawns with 50 HP.
- Pinky is the glass rusher: low HP, full speed, shortest windup + cooldown.
- **Resists** zero damage of that type. Fire resistance means the incinerator (the only fire weapon) does zero to caco, baron, archvile, mancubus. The BFG's plasma is NOT resisted, so it's the answer against those four.

### Depth-scaled aggression

Cooldowns above are L1 baseline. `build-world` stamps `:aggression` from `enemy_ai/aggression-for`: starts 1.0, drops 0.03 per level, clamps at 0.8. `tick-attack` scales cooldown by this multiplier, so enemies recover faster and attack more often deeper (L7+ = +25% attack rate). Windup stays honest at all depths. The 0.8 floor ensures the deepest levels stay dodgeable despite key-repeat lag.

## Spawning

Two entry points:
- `spawn-enemies` - single-type rooms.
- `spawn-enemies-mixed` - multi-type. Spec shape: `{:type :count [:lives N] [:max-concurrent K]}`. Omit `:lives` and the type's catalog default applies. Each enemy carries `:type` for render lookup and optional `:max-concurrent` cap. Used by `build-world` for any vector-based `:enemies` field (e.g. L2-L9 mixes, and L10 boss arena where `{:type :cyber :count 1 :lives 50}` + `{:type :imp :count 2 :max-concurrent 1}` paints one boss + 2 minions with only 1 minion alive at once).

## AI state machine

Each enemy carries `:state` + optional `:lkp` (last-known player position). State gates move + contact damage:

| State | Move | Attack | Notes |
|-------|------|--------|-------|
| `:dormant` | no | no | Waiting for LOS / noise |
| `:aware` | yes | yes | Has LOS to player |
| `:hunting` | yes | no | Lost LOS, walking to `:lkp` |
| `:pain` | no | no | Stagger flinch (0.3s) |
| `:attacking` | no | yes | Windup before melee/bolt |
| `:wander` | yes | no | Patrol mode, reacts to wake |

Test default: `:aware`. Real spawns: `:dormant` (sneaking-friendly).

**`:dormant`** - Passive until LOS, noise, or being shot triggers `:aware` or `:hunting`.

**`:aware`** - Chase + contact damage. `:lkp` refreshes each frame. Lose LOS → `:hunting`.

**`:hunting`** - Walk to frozen `:lkp`. Lose LOS → stay. Regain LOS → `:aware`. Reach `:lkp` with no LOS → `:dormant` (give up).

**`:pain`** - Hit stagger (per-type roll: imp 35%, cyber 5%). Freeze 0.3s. `tick-pain` decays; expiry → `:aware`. Heavy monsters stagger rarely; fragile ones almost always.

**`:attacking`** - Telegraphed strike. Arm `:attack-windup-secs` when `:aware` + in range + cooldown done. Enemy freezes (visible) but still deals contact. Windup expiry → `:aware` + cooldown arm. Melee types use one `attack-spec`; casters use `caster-spec`.

**`:wander`** - Patrol. `start-wander` rolls angle + timer. `tick-wander` refreshes angle per cycle. Wakes like `:dormant` (LOS → `:aware`, noise → `:hunting`).

### Ranged casters (projectiles)

Caco, baron, archvile fire projectiles on windup-release. Each has long attack range (caco 7.0, baron 8.0, archvile 6.5), dodge-able bolt speed (caco 2.5, baron 3.0, archvile 3.4 u/s), and tight cooldown (caco 1.0s, baron 1.3s, archvile 1.1s). The archvile is escalated via fastest bolt, but its windup (0.6s) matches the caco so the telegraph stays reactable. Telegraph same as melee: freeze, windup, release → `:fire-now` flag. Melee types leave the flag false.

Speed tuning: `type-speed-mul` scales chase by 0.7 (caco), 0.65 (baron), 0.55 (cyber). Unlisted melee types = 1.0. Balance: keep distance to strafe bolts, or close in to trade dodge for melee pressure.

Projectile pipeline (runs between `tick-enemies` + `damage-step`):
- `spawn-from-enemies`: harvest `:fire-now`, aim at player, clear flag.
- `step`: march along velocity, drop on solid / after 4s ttl.
- `resolve-hits`: hit player if within 0.6 units + not immune. I-frames absorb burst. Bolt + contact don't both hit one frame.

Render: white-hot core on orange glow. Walls only occlude (always reads in front of caster).

Casters still melee on contact (touch ignores range), so cornering is dangerous.

### Wake triggers

**LOS** - `observe` casts ray enemy→player. Wall blocks before player → no LOS. Ray capped at 12 units (beyond = too far to see).

**Being shot** - `shoot` stamps `:state :aware` unconditionally.

**Noise** - `fire-shot` BFS from player cell up to 3 cells through open floor (doors + walls block). Dormant enemies in visited cells → `:hunting` at fire origin; hunters refresh `:lkp` to fresher origin; aware enemies unchanged.

### Chase + target selection

`target-pos` picks walk target by state: `:aware` = live player, `:hunting` = frozen `:lkp`, otherwise nil.

`step-toward`: heading = atan2(enemy→target), step `speed * dt` along heading, slide ±45° / ±90° / ±135° on wall collision. Stop at 0.6 units (no pile-up). Arrival at `:lkp` = 0.9 units → `:dormant`. Each candidate step checks walls only; the ground is flat, so the greedy heading suffices.

### Breaking contact

Player ducks around corner:
1. `:aware` → chase, `:lkp` refreshes each frame.
2. Duck behind wall → LOS drops, state → `:hunting`, `:lkp` freezes.
3. Hunter walks to frozen `:lkp` while player runs.
4. Hunter reaches `:lkp` with no LOS → `:dormant`. Escape.

## Attack telegraph

An enemy in `:attacking` (the frozen windup before a swing or a bolt) switches to its baked attack pose (issue #463) and carries a steady `!` above its head, in its own head colour. See [rendering.md](rendering.md#attack-telegraph-issue-457) - without it the windup was invisible in sprite mode, and dodging depends on reading it.

## Respawn

Killed enemy stays in vector with `:alive false` + `:respawn-after` timer (uniform 3-6s; nightmare: 1-2s).

`tick-one` decays timer; on expiry, spawn at random cell >= 3.0 units away AND out of the player's line of sight (issue #455) - distance alone is a few cells, which is well inside the frustum, so monsters used to pop into existence mid-room in plain view. Up to 8 candidates are drawn; the first unseen one wins, and a merely-far-enough candidate is kept as a fallback so an open arena with nowhere to hide still revives its dead. No slot found at all: bump timer to 0.5s + retry next frame (no ambush spawn).

Optional `:max-concurrent` cap (per-type) enforces max-alive count. Revival checks live count; respawn delayed until a sibling dies. `:type` preserved across respawn.

L10 boss death: call 7-arity `advance` with `revive? false` to freeze all timers. Victory lap unbothered by fresh spawns.

## Rendering

Column split: 3 zones (head / body+glyph / legs). Face overlays centre column at head-mid. Walls occlude.

**Feet anchoring**: A sprite is anchored by its feet on the flat floor row (`round(svh/2 + 0.5*wall-px) + pr`), not centred on the horizon. The renderer stands each billboard on that row and draws the body upward by its pixel height. The grounding shadow, the face glyph, and the floating HP digit all derive from the same foot row. Combat's vertical hit gate (`enemy/vertical-hit?`, via `aim-pr` / `sprite-half-rows`) anchors on the same screen-centre crosshair (issue #243), so a shot lands on the drawn body: looking up slides the sprite down past the crosshair and looking down lifts it up, so aiming at the floor or sky misses.

**Distance fade**: `t = min(0.65, (dist/max-depth)²)`. RGB cube (16-231) scaled (1-t); grayscale (232-255) pulled to 232. Squared curve: close vivid, mid-range fade, 0.65 cap so a monster at max range stays at least 35% lit. For the textured sprite path the `sfade` LUT index uses half-strength fog: `(1 - t*0.5) * 23`, so sprite texels receive ~15-30% darkening at mid/far range rather than the full wall-fog amount. This keeps baked shading bands visible on dark-toned sprites. Wound tint (damage ratio * 0.35, also capped at 0.65) is NOT halved so health-state readability is preserved.

**Idle animation**: Two glyphs per type (`:face` + `:face-alt`). Sin wave 3 rad/s (~2s cycle). All of a type pulse in sync.

**Aggro pulse**: Within 1.8 units (2× touch-dist), head paints SGR blink + skips fade. Steady face + pulsing head = danger cue.

**Colors as integers** (`196` not `"\e[48;5;196m "`): `fade-256` needs raw codes for dynamic fade. Compose at paint time, reuse for face BG.
