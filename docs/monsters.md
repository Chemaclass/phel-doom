# Monsters

- `src/modules/core/enemies.phel` — type catalog (visuals + default HP)
- `src/modules/core/enemy.phel` — record + spawn + chase step
- `src/modules/core/enemy_ai.phel` — AI state machine (LOS-gated wake)
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

Each enemy carries `:lives` / `:max-lives` / `:type`. `enemy/shoot` drops `:lives` per hit; only flips `:alive false` and arms respawn when 0. `damage-ratio = 1 - lives/max-lives` darkens the body shade — wounded enemies read as "bloodied" from across the room without a HUD bar. Non-killing hits also stamp `:hit-flash-secs 1.2` so a yellow HP digit floats above the head.

## Spawning

- `spawn-enemies grid n min-dist px py [max-lives [type-kw]]` — single-type rooms.
- `spawn-enemies-mixed grid specs min-dist px py` — multi-type. Spec shape: `{:type :count [:lives N] [:max-concurrent K]}`. Each enemy carries `:type` for render lookup and optional `:max-concurrent` cap. Used by `build-world` whenever a level's `:enemies` field is a vector (and for the L10 boss arena where `{:type :cyber :count 1 :lives 50}` + `{:type :imp :count 2 :max-concurrent 1}` paints one boss with 2 minions but only 1 alive at a time).

## AI state machine

Each enemy carries a `:state` keyword that decides whether it moves + deals contact damage this tick. Spec lives in `enemy_ai.phel`:

```phel
{:dormant {:moves? false :attacks? false}
 :aware   {:moves? true  :attacks? true}}
```

`new-enemy` defaults to `:aware` (legacy test fixtures keep chasing). Real-game spawns (`spawn-enemies`, `spawn-enemies-mixed`) stamp `:state :dormant`, so the player can sneak / peek / plan until the room reacts.

### Wake triggers

- **Line-of-sight (LOS)** — every tick, `enemy-ai/observe` casts one ray from each alive enemy to the player. Ray hits a wall before reaching the player cell → no LOS, stays dormant. Reaches the player → flips to `:aware`. Reuses `engine/cast-ray`; capped at `max-depth` (12 units), so very long sectors read as "too far to see" — matches DOOM's sight cutoff.
- **Pain (being shot)** — `enemy/shoot` stamps `:state :aware` on the hit target unconditionally. A dormant enemy that took a bullet without reacting would read as broken AI.

Once aware the state is sticky (DOOM "wake once, stay awake"). Future state transitions (`:hunting` for LOS-lost-then-chase-to-LKP, `:pain` for stagger, `:attacking` for ranged windup) slot into the same `state-spec` map + `next-state` cond — call sites don't change.

### Chase step

Aware enemies route through `step-toward`:

1. Desired heading (atan2 enemy → player).
2. Try stepping `speed * dt` units along that heading.
3. If destination is inside a wall, try angle offsets ±45°, ±90°, ±135°. Slides around corners, walks out of dead ends.

Stop distance: enemies don't close past `stop-dist = 0.6` to avoid piling up inside the player's cell. Dormant enemies skip the chase step entirely.

## Respawn cooldown + max-concurrent cap

Killed enemies stay in the vector with `:alive false` and `:respawn-after` set to a random 3-6s.

`tick-one` routes dead enemies through the timer:

```phel
(cond
  (:alive e)                       (step-toward ...)
  (php/=== (:respawn-after e) nil) e                        ; back-compat
  :else
  (let [t (php/- (:respawn-after e) dt)]
    (if (php/> t 0.0)
      (assoc e :respawn-after t)
      (let [pos (random-spawn-far-from grid respawn-min-dist player-x player-y)]
        (if pos
          {:x (first pos) :y (second pos) :alive true}
          (assoc e :respawn-after 0.5))))))   ; retry next frame if no slot
```

`respawn-min-dist = 3.0` keeps revivals away from the player. No valid cell = bump 0.5s, try next frame instead of forcing an ambush spawn.

Optional `:max-concurrent` cap on a spawned enemy type enforces a max-alive count. Revival checks the count of `:alive` enemies of the same `:type`; respawn is delayed until a sibling dies (up to respawn cap). `:type` is now preserved across respawn (bug fix: revived enemies previously dropped `:type`).

The 7-arity `advance es g x y dt sp revive?` suspends the revive branch when `revive?` is false — dead enemies keep their `:respawn-after` value frozen instead of ticking down. Used on L10 once the cyberdemon dies: `play.phel`'s `boss-down?` predicate flips `revive?` to false, so the player's victory lap to the boss door isn't ambushed by a fresh boss spawn or a capped imp.

## Rendering: 3 zones + face overlay

Sprite column splits into three vertical zones by projected sprite height `h`:

```
row in [top,        top + h/3)        → head
row in [top + h/3,  top + 2h/3)       → body  (has texture glyph)
row in [top + 2h/3, bot)              → legs
```

Face glyph is a post-pass overlay at the enemy's centre column, head-mid row. One glyph per enemy (not smeared across head width). Occluded by walls: only paints when enemy distance < wall distance at that column.

## Distance fade

```phel
t = min(0.85, (dist / max-depth)²)
faded-code = fade-256(original-code, t)
```

`fade-256` darkens a 256-color code:

- 6×6×6 cube (16-231): scale each RGB component by `(1 - t)`
- 24-step grayscale (232-255): pull toward 232

Squared curve keeps close enemies vivid; fade kicks in past mid-range. Capped at 0.85 so far enemies remain identifiable silhouettes, not pure black.

## Idle face animation

Two glyphs per type (`:face` + `:face-alt`). Renderer picks between them on a wall-clock sin wave at 3 rad/sec (~2s cycle). No per-enemy state; time-driven, so all enemies of a type pulse in sync.

## Aggro pulse

Within `aggro-distance = 1.8` world units (just over 2× the touch-damage-dist of 0.7), the head paints with SGR blink and skips the distance fade:

```phel
"\e[5;48;5;<head-code>m "
```

Reads as "about to hit you" the moment they cross into striking range. Face glyph still paints after; steady face against pulsing head = danger cue.

## Why monster colours are integer codes

Renderer fades each colour per frame per enemy via `fade-256`, which needs the raw code (`196`). Storing the composed ANSI string (`"\e[48;5;196m "`) would require parsing the code back out. Cleaner: store code, compose at paint time. Same code feeds the face overlay's BG attribute.
