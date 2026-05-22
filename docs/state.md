# World + player state

Pure data shapes that every other module operates on. `src/modules/core/state.phel`.

## The world map

`new-world` returns a Phel map:

```phel
{:grid       <vector of vectors of cell ints>
 :pgrid      <PHP nested array, fast-path twin of :grid>
 :width      <int>
 :height     <int>
 :player     <player map>
 :show-map   <bool>     ; minimap toggle
 :paused     <bool>     ; P toggle
 :sound-on   <bool>     ; N toggle
 :enemies    <vector of enemy maps>
 :hearts     <vector of {:x :y}>
 :kills      <int>
 :lives      <int, 0..max-lives>
 :iframes    <float seconds>  ; post-hit invulnerability
 :fire-anim  <float seconds>  ; muzzle flash visibility
 :intro-secs <float seconds>  ; level intro splash countdown
 :flash-secs <float seconds>  ; 1-frame white impact flash
 :fx         <vector of blood splatters>
 :game-time  <float seconds>  ; pause-aware clock for render pulses
 :moves      {:fwd :back :strafe-left :strafe-right :turn-left :turn-right}}
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

Six time-limited counters drive directional motion:

```phel
{:fwd          <int frames remaining>
 :back         <int>
 :strafe-left  <int>
 :strafe-right <int>
 :turn-left    <int>
 :turn-right   <int>}
```

Each input byte from `glue/controls.phel` refreshes the matching counter. Each frame `core/physics.phel` consumes whatever is non-zero (scaled by `dt`) and decays every counter by 1. Counter hits 0 = direction stops.

Hold-frame size is the only "feel" knob: shorter = snappier stop, longer = smoother sustained-hold (bridges OS auto-repeat gaps). Current: `move-hold-frames=12`, `turn-hold-frames=3`.

## Lives

Capped by `max-lives` (default 5). New worlds start at `max-lives`. Heart pickups increment via `gain-life` (clamped). Contact damage decrements via `take-damage` in `core/combat.phel`.

HUD shows `♥` per remaining life and `♡` for spent slots up to `max-lives`. Sized from `:max-lives` in the stats map so the cap can change without touching the renderer.

## Timers

Float-seconds countdowns on the world, decayed by `decay-timers` in `core/combat.phel`:

| Timer | Set by | Drives |
|---|---|---|
| `:iframes` | `take-damage` (1.0s) | Red palette flush + immunity window |
| `:flash-secs` | `take-damage` (0.05s) | 1-frame all-white impact |
| `:fire-anim` | `fire-shot` (0.09s) | Muzzle flash visibility |
| `:intro-secs` | `build-world` (1.5s) | "LEVEL N · NAME" splash overlay |

`:fx` is a vector of blood splatters with their own `:ttl` ticked by `decay-fx`.

### `:game-time` — the pause-aware clock

`advance-game-time` adds `dt` to `:game-time` on every non-paused frame; on a paused frame `tick-world` returns early so the value is left untouched. Render samples this clock for every blink/pulse (door, behind warning, jam, pickup throb, enemy face/body cycle, screen-shake) so pressing `p` freezes every visual animation that was driven by the wall clock before. Resume picks up exactly where the freeze caught it.

## Why the world is a flat map, not a record

Phel has `defrecord`, backed by its map-like `defstruct`. This world still stays
a plain map because it is a broad state aggregate assembled in stages:

- one-liner construction
- assoc / update without ceremony
- direct serialization for tests (`(is (= expected (tick-world ...)))`)

Cost: call sites do not get `defstruct`'s fixed key shape. Mitigated by
documenting the keyset here and centralising key reads in `frame-stats` (so a
typo is loud).
