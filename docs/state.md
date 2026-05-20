# World + player state

Pure data shapes that every other module operates on. Lives in
`src/modules/core/state.phel`.

## The world map

`new-world` returns a Phel map with the following keys:

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
 :moves      {:fwd :back :strafe-left :strafe-right :turn-left :turn-right}}
```

After `build-world` from `core/level.phel` stamps level metadata,
the world also carries:

```phel
{:level            <int 1..5>
 :level-name       <string>           ; "imps", "demons", ...
 :chase-speed      <float>            ; enemy speed for this level
 :enemy-head-code  <int 256-color>    ; head zone BG
 :enemy-body-code  <int>              ; body zone BG
 :enemy-legs-code  <int>              ; legs zone BG
 :enemy-body-glyph <1-char string>    ; per-type body texture
 :enemy-body-glyph-fg <int>           ; FG color for the texture glyph
 :enemy-face       <ANSI escape string>
 :enemy-face-alt   <ANSI escape string>}
```

## :grid vs :pgrid

`:grid` is a Phel persistent vector of vectors. Useful for pure
updates via `assoc-in`. `:pgrid` is a PHP-native `array(array(...))`
mirror, used by the raycaster + minimap hot loops to avoid Phel's
polymorphic collection dispatch. They're created together by
`new-world`:

```phel
:grid  grid
:pgrid (to-php-array (map to-php-array grid))
```

Whenever the grid is mutated (e.g. a door turning into floor),
**both** must update. See `pickup-hearts` and the door logic in
`commands/play.phel`.

## The player

```phel
{:x     <float world units>
 :y     <float>
 :angle <float radians>}
```

Created by `new-player x y angle`. Mutated by `move-player` (delta
translation, no collision check) and `turn-player` (delta angle).
Collision is handled at the `physics/try-move` layer.

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

Each input byte from `glue/controls.phel` refreshes the matching
counter. Each frame `core/physics.phel` consumes whatever is
non-zero (scaled by `dt`) and decays every counter by 1. When a
counter hits 0 the direction stops.

The hold-frame size is the only knob that controls "feel": shorter
= snappier stop, longer = smoother sustained-hold (bridges OS
auto-repeat gaps). Current values: `move-hold-frames=12`,
`turn-hold-frames=3`.

## Lives

Capped by `max-lives` (default 5). New worlds start at `max-lives`;
heart pickups increment via `gain-life` (clamped to the cap);
contact damage decrements via `take-damage` in `core/combat.phel`.

The HUD shows `♥` per remaining life and `♡` for spent slots up to
`max-lives` — sized from `:max-lives` in the stats map so the cap
can change without touching the renderer.

## Timers

Several float-seconds countdowns live on the world and are decayed
by `decay-timers` in `core/combat.phel` each frame:

| Timer | Set by | Drives |
|---|---|---|
| `:iframes` | `take-damage` (1.0s) | Red palette flush + immunity window |
| `:flash-secs` | `take-damage` (0.05s) | 1-frame all-white impact frame |
| `:fire-anim` | `fire-shot` (0.09s) | Muzzle flash visibility |
| `:intro-secs` | `build-world` (1.5s) | "LEVEL N · NAME" splash overlay |

`:fx` is a vector of blood splatters with their own `:ttl` field
ticked by `decay-fx`.

## Why the world is a flat map and not records

Phel doesn't have a built-in record type with the ergonomics of
Clojure's `defrecord`. Plain maps win on:

- one-liner construction
- assoc / update without ceremony
- direct serialization for tests (`(is (= expected (tick-world ...)))`)

Cost: no compile-time validation that a key exists. Mitigated by
keeping the keyset documented here and by `frame-stats` being the
one place that pulls keys out for the renderer (so a typo is loud).
