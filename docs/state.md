# World + player state

Pure data shapes that every other module operates on. `src/core/state.phel`.

## The world map

`new-world` returns a Phel map:

```phel
{:grid       <vector of vectors of cell ints>
 :pgrid      <PHP nested array, fast-path twin of :grid>
 :width      <int>
 :height     <int>
 :player     <player map>
 :show-map   <bool>     ; minimap toggle (default OFF, M toggles)
 :paused     <bool>     ; P toggle
 :sound-on   <bool>     ; N toggle
 :enemies    <vector of {:x :y :alive :lives :max-lives :type :hit-flash-secs [:respawn-after] [:max-concurrent] [:fire-now]}>
 :projectiles <vector of {:x :y :vx :vy :ttl :type}>  ; enemy fireballs (core/projectile)
 :hit-stop-secs <float>  ; >0 freezes the gameplay step (kill weight); decays each frame
 :hearts     <vector of {:x :y}>
 :armors     <vector of {:x :y}>
 :ammo-boxes <vector of {:x :y}>
 :berserks   <vector of {:x :y}>           ; rage spheres (20s ×2 damage)
 :invulns    <vector of {:x :y}>           ; immunity spheres (10s invincible)
 :soulspheres <vector of {:x :y}>          ; over-cap lives pickup (issue #68)
 :soul-decay-secs <float seconds>          ; over-cap decay clock; decrements lives once per 5s while > max-lives
 :armor-shards <vector of {:x :y}>         ; +1 over-cap armor; banks up to armor-shard-cap (10), no decay
 :backpacks  <vector of {:x :y}>           ; per-level pickup spawn vector (stacks via :backpack-level)
 :backpack-level <int 0..max-backpacks>    ; 0 = no backpack, 1+ = stacked; effective reserve cap = base * (1 + level)
 :keycards   <vector of {:x :y :colour}>   ; :blue / :red / :boss keycards for locked exits (boss = synthetic, no pickup)
 :held-keys  <set of colour kws>           ; #{:blue :red :boss} collected so far
 :armor      <int 0..max-armor, hits absorbed before lives drop>
 :backpack?  <bool, persists across level cuts>
 :armory?    <bool, --armory flag; infinite ammo per-frame refill>
 :berserk-secs <float seconds>             ; while > 0: 2x weapon damage
 :invuln-secs  <float seconds>             ; while > 0: contact hits skipped
 :difficulty <kw :easy|:normal|:hard|:nightmare>
 :god?       <bool, --god flag; no damage>
 :door-lock  <kw :blue|:red|:boss|nil>     ; lock colour on this level's exit (:boss = synthetic, no keycard pickup)
 :weapon     <kw :pistol|:shotgun|:chaingun|:chainsaw|:bfg|:incinerator|:rocket>  ; active weapon
 :owned-weapons <set of kw>                ; pistol owned by default; others must be picked up
 :weapon-pickups <vector of {:x :y :weapon}>
 :weapon-state {<kw> {:mag :reserve}}      ; per-weapon ammo bookkeeping
 :kills      <int>
 :lives      <int, 0..max-lives>
 :iframes    <float seconds>  ; post-hit invulnerability
 :fire-anim  <float seconds>  ; muzzle flash visibility
 :intro-secs <float seconds>  ; level intro splash countdown
 :flash-secs <float seconds>  ; 1-frame white impact flash
 :fx         <vector of blood splatters>
 :game-time  <float seconds>  ; pause-aware clock for render pulses
 :mag           <int 0..mag-size>     ; rounds in the loaded magazine
 :ammo-reserve  <int 0..max-reserve>  ; spare ammo pool; drained on reload
 :reload-cooldown  <float seconds>    ; drives the reload drop animation
 :empty-click-secs <float seconds>    ; dry-fire CLICK prompt timer
 :heat          <float 0..1>          ; pistol heat; ≥ 1 triggers jam
 :jam-secs      <float seconds>       ; jammed-pistol lockout
 :stamina              <float 0..max-stamina>  ; sprint pool, default 100.0
 :sprint-cooldown-secs <float seconds>         ; regen lockout post-sprint
 :sprint-blocked?      <bool>                  ; latches at 0, clears at threshold
 :moves      {:fwd :back :strafe-left :strafe-right :turn-left :turn-right :sprint}}
```

After `build-world` from `core/level.phel` stamps level metadata, the world also carries:

```phel
{:level            <int 1..5>
 :level-name       <string>           ; "imps", "demons", ...
 :chase-speed      <float>            ; enemy speed for this level
 :enemy-head-code  <int 256-color>    ; head zone BG
 :enemy-body-code  <int>              ; body zone BG
 :enemy-legs-code  <int>              ; legs zone BG
 :enemy-body-glyph <1-char string>    ; per-type body texture
 :enemy-body-glyph-fg <int>           ; FG color for texture glyph
 :enemy-face       <ANSI escape string>
 :enemy-face-alt   <ANSI escape string>}
```

## :grid vs :pgrid

`:grid` is a Phel persistent vector of vectors; great for pure updates via `assoc-in`. `:pgrid` is a PHP-native `array(array(...))` mirror used by raycaster + minimap hot loops to avoid Phel's polymorphic collection dispatch. Created together by `new-world`:

```phel
:grid  grid
:pgrid (to-php-array (map to-php-array grid))
```

On grid mutation (door turning into floor, etc.) **both** must update. See `pickup-hearts` and door logic in `commands/play.phel`.

## The player

```phel
{:x     <float world units>
 :y     <float>
 :angle <float radians>}
```

`new-player x y angle` creates. `move-player` does delta translation (no collision); `turn-player` does delta angle. Collision handled at `physics/try-move`.

## Movement counters (`:moves`)

Seven time-limited counters drive directional motion + sprint intent:

```phel
{:fwd          <int frames remaining>
 :back         <int>
 :strafe-left  <int>
 :strafe-right <int>
 :turn-left    <int>
 :turn-right   <int>
 :sprint       <int>}    ; SHIFT+WASD or `x` press refresh
```

Each input byte from `glue/controls.phel` refreshes the matching counter. Each frame `core/physics.phel` consumes whatever is non-zero (scaled by `dt`) and decays every counter by 1. Counter hits 0 = direction stops.

`:sprint` is intent only - the actual speed boost is gated by `:stamina > 0` AND `not :sprint-blocked?`. See `physics.phel`'s `tick-stamina` + `sprinting?`.

Hold-frame size is the only "feel" knob: shorter = snappier stop, longer = smoother sustained-hold (bridges OS auto-repeat gaps). Current: `move-hold-frames=18` (~300ms at 60fps), `turn-hold-frames=3` (~50ms).

## Lives (half-heart HP pool)

`:lives` is an HP pool capped by `max-lives` (10), drawn as 5 hearts of 2 HP each, so a hit can cost half a heart. New worlds start at `max-lives` (full). Heart pickups heal a whole heart (`gain-life` adds 2, clamped). Damage decrements via `take-damage` (contact) / `hit-player-at` (bolt) in `core/combat.phel`, by the attacker's `enemy-hit-damage` (1 light / 2 heavy + caster / 3 boss); armor absorbs a whole hit regardless of size. Soulsphere pushes the pool over the cap toward `soulsphere-cap` (14), decaying back down over time.

HUD draws 5 heart slots from the pool: `♥` full, `◖` half, `·` empty (over-cap soul HP shows as extra full hearts). Sized from `:max-lives` in the stats map so the cap can change without touching the renderer.

## Timers

Float-seconds countdowns on the world, decayed by `decay-timers` in `core/combat.phel`:

| Timer | Set by | Drives |
|---|---|---|
| `:iframes` | `take-damage` (1.0s) | Red palette flush + immunity window |
| `:flash-secs` | `take-damage` (0.05s) | 1-frame all-white impact |
| `:fire-anim` | `fire-shot` (0.09s) | Muzzle flash visibility |
| `:intro-secs` | `build-world` (1.5s) | "LEVEL N · NAME" splash overlay |

`:fx` is a vector of blood splatters with their own `:ttl` ticked by `decay-fx`.

### `:game-time` - the pause-aware clock

`advance-game-time` adds `dt` to `:game-time` on every non-paused frame; on a paused frame `tick-world` returns early so the value is left untouched. Render samples this clock for every blink/pulse (door, behind warning, jam, pickup throb, enemy face/body cycle, screen-shake) so pressing `p` freezes every visual animation that was driven by the wall clock before. Resume picks up exactly where the freeze caught it.

## Why a flat map

Keeps construction simple (one `new-world` call), updates lightweight (`assoc`/`update`), and tests literal (`(is (= expected (tick-world ...)))`). Trade-off: no compiler help on key names, so `frame-stats` centralizes all reads to catch typos.
