# Monsters

`src/core/enemies.phel` (catalog), `enemy.phel` (record, spawn, chase, hitscan targeting, respawn), `enemy_ai.phel` (state machine, sight, attacks, noise), `projectile.phel` (caster bolts). Rendering: [rendering.md](rendering.md#enemy-sprite-paint).

## Catalog (`enemy-types`)

Ten types. Every entry carries the `required-keys` (name, HP, head/body/legs colour codes, body glyphs, idle/alt/attack faces; pinned by tests) and an optional `:resists` set.

| Kw | Name | HP | Head | Body | Face (idle / alt) |
|---|---|---|---|---|---|
| `:imp`      | imp        | 1 | 196 red     | 124 red      | ● / ◯ |
| `:demon`    | demon      | 2 | 165 magenta | 126 purple   | ▼ / ▾ |
| `:caco`     | cacodemon  | 3 | 51 cyan     | 38 cyan      | ◉ / ◎ |
| `:baron`    | baron      | 4 | 46 green    | 34 green     | Λ / λ |
| `:cyber`    | cyberdemon | 5 | 240 grey    | 124 red      | ■ / □ |
| `:spectre`  | spectre    | 3 | 117 cyan    | 67 steel     | ○ / ◌ |
| `:revenant` | revenant   | 4 | 255 bone    | 245 grey     | ☠ / ◔ |
| `:archvile` | archvile   | 5 | 208 orange  | 166 amber    | ∺ / ≋ |
| `:mancubus` | mancubus   | 4 | 137 tan     | 94 brown     | ═ / ─ |
| `:pinky`    | pinky      | 2 | 213 pink    | 199 hot pink | ≣ / ≡ |

Colours and faces drive the glyph renderer (`PHEL_DOOM_NO_SPRITES=1`); the default renderer draws baked Freedoom sprites. To add a type: one `enemy-types` entry, a `sprite-type-map` entry (`src/io/render/enemy_sprite.phel`), and a level that uses it.

Records carry `:type`, `:lives`, `:max-lives`. `1 - lives/max-lives` darkens the body, and a wound floats a yellow HP digit for 1.2s (`:hit-flash-secs`).

## Stats comparison

HP: catalog default (levels may override, difficulty scales). Speed: level `:chase` x `enemy/type-speed-mul`. Range, windup, cooldown: `enemy_ai/attack-spec` or `caster-spec`, else `default-attack-spec` (1.4 / 0.4 / 1.0); cooldown shown at L1. Dmg: player HP per hit (`combat/enemy-hit-damage`, 1 = half a heart). Pain: `type-pain-chance`, else 25%.

| Type | Debut | HP | Speed x | Attack | Range | Windup (s) | Cooldown (s) | Bolt speed | Dmg | Pain % | Resists |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `:imp`      | L1 | 1 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | 35 | - |
| `:demon`    | L2 | 2 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | 25 | - |
| `:caco`     | L3 | 3 | 0.70 | ranged | 7.0 | 0.6 | 1.0 | 2.5 | 2 | 25 | fire |
| `:baron`    | L4 | 4 | 0.65 | ranged | 8.0 | 0.8 | 1.3 | 3.0 | 2 | 15 | fire |
| `:cyber`    | L5 | 5 | 0.55 | melee  | 1.8 | 0.8 | 1.8 | -   | 3 | 5  | - |
| `:spectre`  | L6 | 3 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | 25 | - |
| `:revenant` | L7 | 4 | 1.0  | melee  | 1.4 | 0.4 | 1.0 | -   | 1 | 25 | - |
| `:archvile` | L8 | 5 | 1.0  | ranged | 6.5 | 0.6 | 1.1 | 3.4 | 2 | 25 | fire |
| `:mancubus` | L8 | 4 | 1.0  | melee  | 1.6 | 0.5 | 1.3 | -   | 2 | 18 | fire |
| `:pinky`    | L9 | 2 | 1.0  | melee  | 1.4 | 0.3 | 0.8 | -   | 1 | 20 | - |

Design intent:

- Casters move slower so a ranged threat stays fair: keep range and strafe, or close in for melee pressure. The archvile's bolt is fastest, but its 0.6s windup matches the caco's, so it stays reactable.
- The cyber is heaviest: most HP, slowest, longest telegraph. The L10 boss has 50 HP.
- The pinky is the glass rusher: low HP, shortest windup and cooldown.
- Resists: see [combat.md](combat.md#damage-resistance).

### Depth-scaled aggression

`enemy_ai/aggression-for` gives 1.0 on L1, minus 0.03 per level, floored at 0.8 from L8 on. `tick-attack` multiplies the cooldown by it: up to 25% more attacks deeper in. Windups never shrink, and the floor keeps deep levels dodgeable despite key-repeat lag.

## Spawning

`build-world` turns `:enemies` into specs `{:type :count [:lives N] [:max-concurrent K]}` and calls `spawn-enemies-mixed`, which places each on a random open cell at least 3.0 units from the player. Spawns start `:dormant`; `promote-wanderers` flips each to `:wander` with probability 0.5, so rooms have a pulse while sneaking stays viable. Nightmare stamps `:nightmare? true`.

## AI state machine

Each enemy carries `:state` and an optional `:lkp` (last-known player position). `state-spec` gates movement and contact damage:

| State | Moves | Attacks | Meaning |
|-------|------|--------|-------|
| `:dormant`   | no  | no  | Waiting for sight or noise |
| `:wander`    | yes | no  | Pacing: new random heading every 2s, 2 units ahead |
| `:aware`     | yes | yes | Sees the player, chases, `:lkp` refreshes every frame |
| `:hunting`   | yes | no  | Lost sight, walking to the frozen `:lkp` |
| `:pain`      | no  | no  | 0.3s stagger |
| `:attacking` | no  | yes | Frozen windup before a swing or a bolt |

An enemy with no `:state` (unit fixtures) reads as `:aware`.

Transitions (`next-state`, run by `observe` each frame):

- `:dormant` / `:wander` + sight → `:aware`.
- `:aware` loses sight → `:hunting`.
- `:hunting` regains sight → `:aware`; reaches `:lkp` (within 0.9 units) without sight → `:dormant`.
- `:aware` + in range + cooldown done → `:attacking` (`maybe-start-attack`). Windup expiry → `:aware`, arms the cooldown, and raises `:fire-now` for casters.
- A wound rolls `pain-chance-of` (table above): success → `:pain`, expiry → `:aware`. Only single-target hitscans roll it; pierce, spread and splash never stagger.

Breaking contact: duck behind a wall and the hunter walks to where it last saw you, finds nothing, and sleeps.

### Wake triggers

- **Sight**: `sees-player?` casts one ray from the enemy to the player. A closer wall, or a player beyond `max-depth` (12 units), means no sight.
- **Being shot**: every damage path sets the target `:aware`.
- **Noise**: every shot runs `noise-wake`, a 4-connected flood from the player's cell up to 3 cells over floor only (walls and every door variant block). Dormant and wandering enemies inside switch to `:hunting` toward the fire origin; hunters refresh their `:lkp`; aware enemies ignore it.

Waking plays one per-type sight cue for the nearest waker of the frame (#460).

### Chase

`target-pos` picks the player (`:aware`), the `:lkp` (`:hunting`) or a point 2 units along the wander heading. `step-toward` walks there and stops at 0.6 units so enemies do not pile up. A blocked step tries 45, 90 and 135 degree offsets both ways: cut the corner, slide the wall, back out. On a flat floor this greedy heading suffices.

### Ranged casters (projectiles)

Caster windups end by raising `:fire-now`. The projectile pass runs between `tick-enemies` and `damage-step`: `spawn-from-enemies` launches one bolt per flag at the player's position, carrying the caster's hit damage; `step` drops a bolt on a wall, secret or switch (doors let it through) or after 4s; `resolve-hits` lands the first bolt within 0.6 units unless the player is immune, and its i-frames absorb the rest of the burst. Casters still hurt on contact, so cornering one is dangerous.

## Attack telegraph

An `:attacking` enemy shows its baked attack pose (#463) and a steady `!` above its head in warning amber on a dark background (#457, `telegraph-sgr`), the same for every type. Dodging depends on reading it. See [rendering.md](rendering.md#attack-telegraph-issue-457).

## Respawn

A dead enemy stays in the vector with a `:respawn-after` timer: 3-6s, or 1-2s on nightmare. On expiry, `random-spawn-far-from` draws up to 8 cells at least 3.0 units away and takes the first the player cannot see (issue #455: distance alone popped monsters in mid-room). A visible fallback keeps open arenas reviving; no cell at all retries in 0.5s. The enemy returns at full HP with its type and flags.

`:max-concurrent` caps how many of a type are alive (the L10 imps: 1); a capped revival retries in 0.5s. Nightmare ignores the cap. Once the L10 boss is dead, `advance` gets `revive? false` and every timer freezes.

## Rendering

Detail in [rendering.md](rendering.md#enemy-sprite-paint). What ties back here: sprites stand on the floor row the vertical hit gate uses, the cyber draws at 2x (`enemy/boss-sprite-scale`) for both, and catalog colours stay raw ints (`196`) so `fade-256` can fade them. Within 1.8 units the head paints steady at full brightness.
