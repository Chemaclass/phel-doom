# World + player state

Pure data shapes that every other module operates on. `src/core/state.phel`.

## The world map

`new-world` returns a Phel map:

```phel
{:grid       <vector of vectors of cell ints>
 :pgrid      <PHP nested array, fast-path twin of :grid>
 :light-grid <PHP array (y*width+x) of per-cell shade bias, derived from :grid (#418)>
 :width      <int>
 :height     <int>
 :player     <player map>
 :show-map   <bool>     ; minimap toggle (default OFF, M toggles)
 :full-map?  <bool>     ; --full-map: minimap starts fully revealed
 :visited    <PHP array keyed (y*width+x)>  ; fog-of-war automap; 1 = seen, nil = unseen
 :switches   <vector of {:at [x y] :targets [[x y] ...]}>  ; wall switches (#62), F-key toggles
 :paused     <bool>     ; P toggle
 :help?      <bool>     ; H overlay
 :debug?     <bool>     ; F3 perf overlay
 :sound-on   <bool>     ; N toggle
 :enemies    <vector of {:x :y :alive :lives :max-lives :type :hit-flash-secs [:respawn-after] [:max-concurrent] [:fire-now]}>
             ; a spawned enemy also carries the AI slots (:state :lkp :wander-angle :aggression ...) - see docs/monsters.md
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
 :streak     <int>            ; consecutive kills inside the streak window
 :streak-secs <float seconds> ; time left to extend the streak
 :lives      <int, 0..max-lives>
 :iframes    <float seconds>  ; post-hit invulnerability
 :shake-secs <float seconds>  ; screen-shake kick (damage + heavy-weapon fire/blast)
 :fire-anim  <float seconds>  ; muzzle flash visibility
 :intro-secs <float seconds>  ; level intro splash countdown
 :flash-secs <float seconds>  ; 1-frame dark-red impact flash
 :msg-text   <string|nil>     ; message line: what was just picked up / revealed / switched to
 :msg-secs   <float seconds>  ; how long that line stays up
 :fx         <vector of blood splatters>
 :blood-drops <vector>        ; screen-edge drips during i-frames
 :game-time  <float seconds>  ; pause-aware clock for render pulses
 :bob-phase  <float radians>  ; head-bob walk cycle (#411); 0.0 at rest, advanced by distance in apply-physics
 :heartbeat-phase <float>     ; low-health heartbeat cycle
 :heartbeat-tick? <bool>      ; true on the frame the heartbeat beats (sfx cue)
 :prev-min-enemy-dist <float> ; last frame's nearest-enemy distance; drives the scare cue
 :scare-secs <float seconds>  ; jump-scare sting timer
 :aim-col    <int|nil>        ; movable reticle cell (#324); nil = centred (mouse off)
 :aim-row    <int|nil>
 :locked-door-bump-secs   <float seconds>  ; 'NEED <COLOUR> KEY' prompt timer
 :locked-door-bump-colour <kw|nil>         ; which key the bumped door wants
 :fire-cooldown <float seconds>  ; per-shot rate limit
 :mag           <int 0..mag-size>     ; rounds in the loaded magazine
 :ammo-reserve  <int 0..reserve-cap>  ; spare ammo pool (per-weapon cap); drained on reload
 :reload-cooldown  <float seconds>    ; drives the reload drop animation
 :empty-click-secs <float seconds>    ; dry-fire CLICK prompt timer
 :heat          <float 0..1>          ; pistol heat; ≥ 1 triggers jam
 :jam-secs      <float seconds>       ; jammed-pistol lockout
 :stamina              <float 0..max-stamina>  ; sprint pool, default 100.0
 :sprint-cooldown-secs <float seconds>         ; regen lockout post-sprint
 :sprint-blocked?      <bool>                  ; latches at 0, clears at threshold
 :moves      {:fwd :back :strafe-left :strafe-right :turn-left :turn-right :sprint :pitch-up :pitch-down}}
```

After `build-world` from `core/level.phel` stamps level metadata, the world also carries:

```phel
{:level            <int 1..10>
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

`:grid` is a Phel persistent vector of vectors, good for pure updates via `assoc-in`. `:pgrid` is a PHP-native `array(array(...))` mirror, read by the raycaster and minimap hot loops to dodge Phel's polymorphic collection dispatch. `new-world` creates both:

```phel
:grid  grid
:pgrid (to-array (map to-array grid))
```

On grid mutation (a door turning into floor) **both** must update. See `pickup-hearts` in `core/pickups.phel` and the door logic in `commands/play.phel`. `rebuild-pgrid` runs after any grid edit to keep the PHP mirror in sync.

`:light-grid` (#418) is a third grid-derived array in that family: a PHP array keyed `(y*width + x)` of per-cell shade biases from `core/light/build-light-grid`, read one-per-column by the wall shader when the `:light` setting is on. BOTH `new-world` and `rebuild-pgrid` derive it, so a revealed secret or toggled switch re-lights correctly. Like `:pgrid` it is never serialized: `world->savestring` drops it, load re-derives it.

## The player

```phel
{:x       <float world units>
 :y       <float>
 :angle   <float radians>
 :pitch   <float look up/down fraction in [-1, 1], 0 = level>}
```

`new-player x y angle` places the player at a world position and facing angle. `move-player` does delta translation (no collision), `turn-player` delta angle, `change-pitch` camera look. Collision lives in `physics/try-move`: a cell blocks only when it is a wall, or a locked door the player lacks the key for. Any open floor cell is walkable.

## Movement counters (`:moves`)

Nine time-limited counters drive directional motion, look up/down, and sprint intent. Each holds **seconds remaining**, not a frame count:

```phel
{:fwd          <float seconds remaining>
 :back         <float>
 :strafe-left  <float>
 :strafe-right <float>
 :turn-left    <float>
 :turn-right   <float>
 :sprint       <float>}    ; SHIFT+WASD or `x` press refresh
 :pitch-up     <float>     ; ↑ arrow
 :pitch-down   <float>     ; ↓ arrow
```

Each input byte from `glue/controls.phel` refreshes the matching counter to its hold-secs value. Every frame `core/physics.phel` consumes whatever is non-zero (scaled by `dt`), then decays every counter by `dt` seconds (clamped at 0.0). A hold lasts the same wall-clock time at any frame rate. Counter hits 0 = direction stops.

`:sprint` is intent only. The speed boost is gated by `:stamina > 0` AND `not :sprint-blocked?`. See `physics.phel`'s `tick-stamina` + `sprinting?`.

Hold-secs is the only "feel" knob: shorter = snappier stop, longer = smoother sustained hold (it bridges OS auto-repeat gaps). Current: `move-hold-secs=0.30` (~300ms), `turn-hold-secs=0.05` / `pitch-hold-secs=0.05` / `sprint-hold-secs=0.05` (~50ms). All frame-rate independent, defined in `glue/controls.phel`.

## Lives (half-heart HP pool)

`:lives` is an HP pool capped by `max-lives` (10), drawn as 5 hearts of 2 HP each, so a hit can cost half a heart. New worlds start at `max-lives`. Heart pickups heal a whole heart (`gain-life` adds 2, clamped). `take-damage` (contact) and `hit-player-at` (bolt) in `core/combat.phel` subtract the attacker's `enemy-hit-damage` (1 light / 2 heavy + caster / 3 boss). Armor absorbs a whole hit whatever its size. Soulsphere pushes the pool past the cap toward `soulsphere-cap` (14), decaying back down over time.

HUD draws 5 heart slots from the pool: `♥` full, `◖` half, `·` empty (over-cap soul HP shows as extra full hearts). Sized from `:max-lives` in the stats map, so the cap can change without touching the renderer.

## Timers

Float-seconds countdowns on the world, decayed by `decay-timers` in `core/combat.phel`:

| Timer | Set by | Drives |
|---|---|---|
| `:iframes` | `take-damage` (1.0s) | Red palette flush + immunity window |
| `:shake-secs` | `take-damage` (0.25s), heavy-weapon fire/blast (splash-radius-scaled) | Cursor-home offset screen-shake |
| `:flash-secs` | `take-damage` (0.05s) | 1-frame all-red impact wash (#465) |
| `:fire-anim` | `fire-shot` (0.09s) | Muzzle flash visibility |
| `:intro-secs` | `build-world` (1.5s) | "LEVEL N · NAME" splash overlay |
| `:msg-secs` | `push-msg` (2.0s) | Message line naming the pickup / secret / weapon (#456) |

`:fx` is a vector of blood splatters with their own `:ttl` ticked by `decay-fx`.

### `:game-time` - the pause-aware clock

`advance-game-time` adds `dt` to `:game-time` on every non-paused frame. A paused frame returns early from `tick-world`, leaving the value put. Render samples this clock for every blink and pulse (door, behind warning, jam, pickup throb, enemy face/body cycle, screen-shake), so `p` freezes every animation the wall clock used to drive. Resume picks up where the freeze caught it.

## Flat world design

Every level is flat: the floor a single plane (z = 0), the ceiling a full-height plane (z = 1). Construction stays simple (one `new-world` call), updates lightweight (`assoc`/`update`), tests literal (`(is (= expected (tick-world ...)))`). Trade-off: no compiler help on key names, so `frame-stats` centralizes every read to catch typos.
