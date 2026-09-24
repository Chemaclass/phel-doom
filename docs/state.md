# World + player state

Pure data shapes every other module operates on. `src/core/state.phel`. This page owns the world shape; the per-frame flow is in [game-loop.md](game-loop.md).

## The world map

The world is one immutable Phel map, threaded through the loop and replaced every frame. `new-world` builds the base, `build-world` (`core/level.phel`) stamps the level on top, and the play loop adds session keys.

### From `new-world`

```phel
{;; Grid (see ":grid vs :pgrid")
 :grid        <vector of vectors of cell ints>
 :pgrid       <PHP nested array, fast-path twin of :grid>
 :light-grid  <PHP array (y*width+x) of per-cell shade bias (#418)>
 :width :height <int>
 :visited     <PHP array keyed (y*width+x)>  ; minimap fog: 1 = seen, missing = unseen
 :switches    <vector of {:at [x y] :targets [[x y] ...]}>  ; F-key switches (#62)

 :player      <player map, see below>
 :moves       {:fwd :back :strafe-left :strafe-right :turn-left :turn-right :sprint :pitch-up :pitch-down}

 ;; Toggles
 :show-map    <bool>   ; M, default off
 :full-map?   <bool>   ; --full-map: minimap starts revealed
 :paused      <bool>   ; P, H, focus loss
 :help?       <bool>   ; H / Esc panel
 :debug?      <bool>   ; F3 perf overlay
 :sound-on    <bool>   ; N

 ;; Actors
 :enemies     <vector of {:x :y :alive :lives :max-lives :type :hit-flash-secs ...}>
              ; plus AI slots (:state :lkp :wander-angle :aggression ...), see monsters.md
 :projectiles <vector of {:x :y :vx :vy :ttl :type}>   ; enemy bolts (core/projectile)

 ;; Pickups on the floor (vectors of {:x :y})
 :hearts :armors :armor-shards :ammo-boxes :berserks :invulns :soulspheres :backpacks

 ;; Player resources
 :lives           <int 0..14>        ; HP pool, see "Lives"
 :soul-decay-secs <float>            ; over-cap decay clock: -1 HP every 5 s while above 10
 :armor           <int 0..10>        ; each unit absorbs one whole hit; 5 normal cap, shards bank to 10
 :backpack-level  <int 0..3>         ; reserve cap = base * (1 + level)
 :held-keys       <set of :blue :red :boss>   ; :boss is stamped when the boss dies
 :keycards        <vector of {:x :y :colour}>
 :stamina              <float 0..100>
 :sprint-cooldown-secs <float>       ; regen lockout after sprinting
 :sprint-blocked?      <bool>        ; latches at 0, clears at 20

 ;; Weapons
 :weapon          <kw :pistol|:shotgun|:chaingun|:chainsaw|:bfg|:incinerator|:rocket>
 :owned-weapons   <set of kw>        ; pistol only at start
 :weapon-state    {<kw> {:mag :reserve}}
 :mag             <int>              ; active weapon mirror, kept in sync by switch-weapon
 :ammo-reserve    <int>
 :fire-cooldown :reload-cooldown :empty-click-secs <float seconds>
 :heat            <float 0..1>       ; pistol only (:overheats?); >= 1 jams
 :jam-secs        <float seconds>
 :aim-col :aim-row <nil>             ; centred-crosshair sentinel, reset every frame (#324)

 ;; Scoring
 :kills :streak <int>
 :streak-secs     <float seconds>

 ;; Feel timers and effects (see "Timers")
 :iframes :shake-secs :fire-anim :intro-secs :flash-secs :msg-secs :hint-secs
 :berserk-secs :invuln-secs :locked-door-bump-secs <float seconds>
 :hit-stop-secs   <float seconds>    ; > 0 freezes the gameplay step (kill weight)
 :locked-door-bump-colour <kw|nil>   ; which key the bumped door wants
 :msg-text        <string|nil>       ; message line (#456)
 :fx              <vector of blood splatters, each with :ttl>
 :blood-drops     <vector>           ; screen-edge drips during i-frames
 :game-time       <float seconds>    ; pause-aware clock for render pulses
 :bob-phase       <float radians>    ; head-bob walk cycle (#411); 0.0 at rest
 :heartbeat-phase <float>
 :heartbeat-tick? <bool>             ; true on the frame the heartbeat beats
 :prev-min-enemy-dist <float>        ; drives tick-scare
 :scare-secs      <float seconds>    ; still set by tick-scare, no longer painted
}
```

### From `build-world`

```phel
{:level         <int 1..10>
 :level-name    <string>             ; "imps", "demons", ... "the final"
 :difficulty    <kw :easy|:normal|:hard|:nightmare>
 :theme         <kw>                 ; floor palette, :base when unset
 :enemy         <kw>                 ; primary enemy type, render fallback
 :chase-speed   <float>
 :door-lock     <kw :blue|:red|:boss|nil>
 :weapon-pickups <vector of {:x :y :weapon}>
 :secrets-total :secrets-found <int>
 :intro-secs    1.5                  ; "LEVEL N · NAME" splash
 :hint-secs     <15.0 on L1, else 0.0>   ; first-run key hints (#467)
}
```

It also fills `:lives`, `:backpack-level`, `:owned-weapons`, `:switches` and the pickup vectors, and runs the enemy spawn.

### Added at runtime

| Keys | Writer | Purpose |
|------|--------|---------|
| `:god?`, `:armory?` | `run-levels` | `--god` (no damage), `--armory` (every weapon, ammo refill) |
| `:settings`, `:settings-cursor` | `run-levels`, settings page | Live options ([settings.md](settings.md)) |
| `:pause-screen`, `:pause-cursor`, `:pause-action`, `:pause-confirm` | pause menu | Menu state; `:pause-confirm` arms Restart |
| `:sfx` | every tick step | Queue of `{:name :vol}` cues, reset each tick, played by the loop |
| `:scene-rows`, `:scene-cols` | game loop | The view size the hitscan gates project against |
| `:save-flash-secs`, `:save-flash-msg` | `handle-save-load` | `SAVED` / `LOADED` / `NO SAVE` cue |
| `:reload-ready-secs` | `tick-world` | `READY!` cue after a reload |
| `:silence-tick?` | `tick-scare` | One-frame audio-silence cue |
| `:hints-seen` | `note-hint-progress` | Moved / turned / fired so far |
| `:shots-fired`, `:shots-hit`, `:damage-taken`, `:kills-by-weapon` | `core/combat` | Run summary counters ([scores.md](scores.md)) |
| `:hit-fx`, `:shot-tracers`, `:hurt-side`, `:hurt-dir` | `core/combat` | Hit marker, tracers, damage direction |
| `:visited-at` | `mark-visible-cells` | Cell the fog scan last ran from; cleared by `rebuild-pgrid` |

A missing key reads as nil, so readers default with `(or (:k world) 0)`. `frame-stats` centralises the render-side reads so a typo shows up in one place.

## :grid vs :pgrid

`:grid` is a persistent vector of vectors, good for pure updates. `:pgrid` is a PHP-native `array(array(...))` mirror that the raycaster and minimap hot loops read with `php/aget`, skipping Phel's polymorphic collection dispatch.

Both must change together. After any grid edit (secret reveal, switch toggle, a demo phase, a savegame load) call `rebuild-pgrid`. It re-derives `:pgrid` and `:light-grid` and clears `:visited-at`. Without it the 3D view paints the old cell, and the player walks through a wall that still looks solid.

`:light-grid` (#418) is the third derived array: per-cell shade biases from `core/light/build-light-grid`, read once per column when the Room light setting is on. None of the three is saved ([savegame.md](savegame.md#dropped-fields)).

## The player

```phel
{:x     <float world units>
 :y     <float>
 :angle <float radians>
 :pitch <float in [-1, 1]>}   ; look up/down, 0 = level
```

`new-player x y angle` spawns looking level. `move-player` translates with no collision, `turn-player` rotates, `clamp-pitch` saturates pitch at +-1.

Collision lives in `physics/try-move`. A cell blocks only when it is a wall or a locked door without the matching key; bumping one also arms the `NEED <COLOUR> KEY` prompt. Any open floor cell is walkable, and the world is flat: one floor plane, one ceiling plane (see [adr/0001](adr/0001-remove-verticality-tier-system.md)).

`apply-physics` also advances `:bob-phase` by the ground covered times `bob-phase-per-unit` (pi per unit, one nod every two cells), wrapped into `[0, 2*pi)`. Zero distance settles it to exactly 0.0, so a standing frame renders byte-identical. Amplitude is render-side (the View bob setting); physics tracks only the phase.

## Movement counters (`:moves`)

Nine counters, each holding **seconds remaining**. `empty-moves` is the all-zero map used at spawn, on focus loss, on the quit prompt and on savegame load.

| Slot | Armed by |
|------|----------|
| `:fwd` `:back` `:strafe-left` `:strafe-right` | `w` `s` `a` `d` |
| `:turn-left` `:turn-right` | `←` `→` |
| `:pitch-up` `:pitch-down` | `↑` `↓` |
| `:sprint` | `Shift`+WASD or `x` |

Each input byte sets its slot to a hold time (`glue/controls.phel`). Every frame `core/physics.phel` applies the non-zero slots scaled by `dt`, then subtracts `dt` from each (floored at 0). A hold lasts the same wall-clock time at any frame rate. The hold values and their trade-offs are in [input.md](input.md#movement-slots-and-hold-time).

`:sprint` is intent only. The boost needs `:stamina > 0` and not `:sprint-blocked?` (`physics/sprinting?`).

## Lives (half-heart HP pool)

`:lives` is an HP pool capped at `max-lives` (10), drawn as 5 hearts of 2 HP, so a hit can cost half a heart. New runs start full.

- Heart pickups heal a whole heart (`gain-life`, +2, clamped).
- `take-damage` (contact) and `hit-player-at` (bolt) in `core/combat.phel` subtract `enemy-hit-damage`: 1 light, 2 heavy or caster, 3 boss.
- Armor absorbs a whole hit of any size.
- A soulsphere pushes the pool up to `soulsphere-cap` (14); the excess decays by 1 every 5 s.

The HUD draws 5 slots: `♥` full, `◖` half, `·` empty, with over-cap HP as extra full hearts. It sizes from `:max-lives` in the stats map, so the cap can change without touching the renderer.

## Timers

Float-seconds countdowns, decayed by `decay-timers` in `core/combat.phel`. A timer that is absent or already 0.0 is not rewritten (`combat/decay-key`), so a quiet frame writes only running timers. Latches and phases are written with a plain `assoc`: on Phel 0.53 rewriting the stored value returns the map itself.

| Timer | Set by | Drives |
|-------|--------|--------|
| `:iframes` | a landed hit (1.0 s) | Red palette wash and immunity window |
| `:shake-secs` | a landed hit (0.25 s), heavy-weapon fire and blasts | Screen shake |
| `:flash-secs` | a landed hit (0.03 s) | One-frame dark-red impact wash (#465) |
| `:fire-anim` | a shot (0.13 s) | Muzzle flash |
| `:intro-secs` | `build-world` (1.5 s) | Level splash |
| `:msg-secs` | `push-msg` (2.0 s) | Message line naming a pickup, secret or weapon (#456) |
| `:hint-secs` | `build-world` (15 s on L1) | First-run key hints (#467) |

Also decayed there: `:streak-secs`, `:fire-cooldown`, `:reload-cooldown`, `:empty-click-secs`, `:berserk-secs`, `:invuln-secs`, `:jam-secs`, `:locked-door-bump-secs`, pistol `:heat`, and the `:ttl` of each `:fx` entry and `:hit-fx`.

### `:game-time`: the pause-aware clock

`advance-game-time` adds `dt` on every unpaused frame; a paused frame returns before it. Render samples this clock for every blink and pulse (door, behind warning, jam, pickup throb, enemy face cycle, screen shake), so `P` freezes every animation, and resume continues from the same instant.
