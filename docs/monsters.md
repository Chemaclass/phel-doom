# Monsters

Lives in `src/modules/core/enemy.phel` (data + AI) and
`src/modules/core/level.phel` (per-type catalog). Visual rendering
done by `io/render.phel`.

## Five types

| Level | Name | Head | Body | Legs | Face | Body pattern |
|---|---|---|---|---|---|---|
| 1 | imps        | 196 (bright red) | 124 (dark red) | 52 (black-red) | ●/◯ yellow | `░` |
| 2 | demons      | 165 (magenta) | 126 (purple) | 90 (deep magenta) | ▼/▾ white | `▒` |
| 3 | cacodemons  | 51 (bright cyan) | 38 (cyan) | 24 (dark cyan) | ◉/◎ black | `⋄` |
| 4 | barons      | 46 (bright green) | 34 (green) | 22 (forest) | Λ/λ black | `▓` |
| 5 | cyberdemons | 240 (grey helmet) | 124 (red flesh) | 238 (grey legs) | ■/□ red blink | `▦` |

Each row of the table is one map entry under `levels` in
`core/level.phel`. Adding a 6th monster is a single map literal.

## Spawning

`spawn-enemies` from `core/enemy.phel` places N enemies on random
open cells at least `min-dist-from` units away from the player. Used
both at level start (`build-world`) and on respawn from a kill.

## Chase AI

`advance enemies grid player-x player-y dt speed` walks every alive
enemy one frame toward the player. Per enemy, `step-toward`:

1. Computes the desired heading (atan2 from enemy to player).
2. Tries to step `speed * dt` units along that heading.
3. If that destination is inside a wall, falls back through a small
   list of angle offsets (±45°, ±90°, ±135°) — slides around
   corners and walks out of dead ends without bumping forever.

Stop distance: enemies don't close in past `stop-dist = 0.6` so they
don't pile up inside the player's cell.

## Respawn cooldown

Killed enemies aren't deleted — they sit in the vector with
`:alive false` and `:respawn-after` set to a random 3–6s.

`tick-one` (the per-enemy advance helper) routes dead enemies
through the timer:

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

`respawn-min-dist = 3.0` keeps revivals away from the player. If no
valid cell is found this frame, the timer is bumped 0.5s and we try
again next frame instead of forcing an ambush spawn.

## Rendering: 3 zones + face overlay

A sprite column splits into three vertical zones based on the
projected sprite height `h`:

```
row in [top,        top + h/3)        → head
row in [top + h/3,  top + 2h/3)       → body  (has texture glyph)
row in [top + 2h/3, bot)              → legs
```

The face glyph is painted as a **post-pass overlay** at the enemy's
centre column, head-mid row. One glyph per enemy (not smeared across
the whole head width). Occluded by walls — only paints when the
enemy's distance is less than the wall distance at that column.

## Distance fade

```phel
t = min(0.85, (dist / max-depth)²)
faded-code = fade-256(original-code, t)
```

`fade-256` darkens a 256-color code:

- 6×6×6 cube (16-231): scale each RGB component by `(1 - t)`
- 24-step grayscale (232-255): pull toward 232

Squared distance curve so close enemies stay vivid; the fade only
kicks in past mid-range. Capped at 0.85 so far enemies remain
identifiable silhouettes, not pure black.

## Idle face animation

Two glyphs per type (`:face` + `:face-alt`). The renderer picks
between them on a wall-clock sin wave at 3 rad/sec (~2s full
cycle). No per-enemy state tracked — the chooser is purely time-
driven so all enemies of the same type pulse in sync.

## Aggro pulse

When an enemy is within `aggro-distance = 1.8` world units (just
over 2× the touch-damage-dist of 0.7), its head paints with the
SGR blink attribute and skips the distance fade:

```phel
"\e[5;48;5;<head-code>m "
```

Reads as "this one is about to hit you" the moment they cross into
striking range. The face glyph overlay still paints after, so the
face stays steady against the pulsing head cells — that contrast is
the danger cue.

## Why monster colours are passed as integer codes

The renderer fades each colour per frame per enemy via `fade-256`,
which needs the raw 256-colour code (e.g. `196`). Storing the
already-composed ANSI string (e.g. `"\e[48;5;196m "`) would require
parsing the code back out. Cleaner to store the code, compose the
string at paint time. The same code feeds the face overlay's BG
attribute.
