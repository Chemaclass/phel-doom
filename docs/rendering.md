# Rendering

Lives in `src/modules/io/render.phel`. Composes one full ANSI string
per frame and writes it to stdout. Side-effecting (it `print`s) so
it lives under `io/`.

## Entry point

```phel
(defn render! [world stats cols rows]
  (print "\e[H")                                  ; cursor home
  (if (php/> (or (get stats :flash-secs) 0.0) 0.0)
    (print (white-flash-frame cols rows))         ; on-hit jolt
    (print (frame->string world stats cols rows)))
  (php/flush))
```

`render!` decides whether to draw a normal frame or the 1-frame
all-white impact flash. The bulk of the work is in `frame->string`.

## frame->string pipeline

```
(frame->string world stats cols rows)
  │
  ├── layout cols rows mw → vw, vh, map-col, map-row
  ├── cast-frame world vw → :dists :hits :hxs :hys :sides
  ├── build per-column wall shades (3 strings × vw cols)
  │     - shades-normal     interior wall cell
  │     - shades-top-edge   ▀ char mixing wall + sky (anti-alias)
  │     - shades-bot-edge   ▀ char mixing wall + floor (anti-alias)
  ├── project enemies → write to per-column arrays:
  │     tops, bots, mids, lowers, emask, eheads, ebodys, elegss
  ├── project blood fx → write to blood-paint overlay
  ├── project heart pickups → write to blood-paint overlay
  ├── walk vh rows × vw cols, emit one cell per (row, col):
  │     - blood-paint overlay wins first
  │     - enemy mask: head/body/legs by row vs mids/lowers
  │     - else wall: top-edge / bot-edge / normal by row vs tops/bots
  │     - sky / floor for rows outside [tops, bots)
  ├── overlay layers via absolute cursor positioning:
  │     - bottom HUD line (hud-line)
  │     - minimap (top-right rows)
  │     - face glyphs (per enemy, occluded by walls)
  │     - crosshair (centre)
  │     - level intro splash (if :intro-secs > 0)
  │     - top-left hearts HUD
  │     - pistol sprite (centre-bottom)
  │     - muzzle flash (when :fire-anim > 0)
  │     - pause menu (if :paused)
  └── concat everything via php/implode into one string
```

The render is **layered**: the base layer is the raycast frame
encoded as run-length-coalesced ANSI cells; everything else is
painted on top using absolute cursor positioning escapes.

## Per-column shade composition

For each non-door wall column, three steps combine into the final
shade index:

```phel
idx = clamp(0, 23,
            distance-to-shade(dist)        ; base by distance
            + (side == 0 ? 1 : 0)          ; vertical-face darken
            + cell-variation-hash(hx, hy)) ; ±1 mottling
```

The result indexes `shade-table[0..23]` — pre-baked ANSI strings for
the 256-color grayscale palette (codes 232..255). One PHP-array
lookup per column.

Door columns get the solid `door-shade` (orange) in `shades-normal`
and a half-block edge mix in `shades-top-edge`/`shades-bot-edge`.

## Half-block edge anti-aliasing

Wall tops and bottoms used to look like a hard staircase. They now
emit the `▀` (UPPER HALF BLOCK) character with a foreground colour
that paints the **top half** of the cell and a background colour
that paints the **bottom half**:

```phel
;; Top of wall column: sky above, wall below in the same cell
"\e[48;5;<wall-code>;38;5;<sky-code>m▀"

;; Bottom of wall column: wall above, floor below in the same cell
"\e[48;5;<floor-code>;38;5;<wall-code>m▀"
```

Eye reads it as a sub-cell wall boundary instead of a flat stair.
Halves vertical aliasing for free.

## Distance-shaded sky + floor

Each row of the viewport gets a pre-baked sky/floor shade tied to
its distance from the horizon line (`vh/2`):

```phel
(build-horizon-gradient vh shade-table)
```

Rows near the horizon are darkest (atmospheric haze); rows at the
top edge (overhead) or bottom edge (at your feet) are brightest.
Sky and floor share the same gradient since past a certain distance
the eye stops distinguishing them anyway.

## Enemy sprite paint

Each visible enemy projects to a centre column + half-width
(`collect-enemy-projs`). The renderer:

1. Computes a fade factor `t = (dist/max-depth)²` capped at 0.85.
2. Builds three fade-shaded ANSI strings — `fhead`, `fbody`, `flegs`
   — by passing the level's `:head-code` / `:body-code` / `:legs-code`
   through `fade-256`.
3. For the body, embeds the level's `:body-glyph` (e.g. `▒`) in a
   darker foreground colour so each monster has a distinct material
   pattern (scales, muscle, armor).
4. Writes these strings into per-column arrays `eheads` / `ebodys` /
   `elegss` for the columns the enemy covers.
5. Records `tops` / `bots` / `mids` / `lowers` so the inner row loop
   can pick the right zone (head/body/legs) for each row.

A separate **aggro branch** swaps in a blink-attributed paint cell
when the enemy is within `aggro-distance` (1.8 world units) — head
pulses to warn the player.

## Face overlay (post-pass)

After the main frame is composed, the renderer iterates visible
enemies and paints a single face glyph (`:enemy-face` or
`:enemy-face-alt` on a sin wave) at the enemy's centre column,
upper-third row. **Occluded by walls** — the face only paints when
the enemy's distance is less than the wall distance at that
column. Without that check, faces would x-ray through walls.

## blood-paint overlay buffer

Blood splatters from kills + heart pickups paint into a single PHP
array `blood-paint` indexed by `row * vw + col`. The inner row loop
reads it first (via `(or (php/aget blood-paint ...) main-cond)`) so
overlay cells override the underlying wall/floor/enemy paint.

## Run-length encoding

Inside the per-row loop, consecutive cells with the same ANSI escape
are coalesced into one paint + N spaces:

```
\e[48;5;240m     (set BG once)
"         "      (12 spaces — terminal repeats the BG)
\e[48;5;238m     (BG change)
"     "          (5 spaces)
```

Cuts output size by 5-10× on rows that share a wall colour. Done
without a separate buffer: a small state machine in the inner loop
tracks `prev` + `run` and flushes when the colour changes.

## Why so many overlay passes

Walls/sky/floor/enemies all go into one big string via the inner
row loop with absolute coordinates implicit in the order (top-to-
bottom, left-to-right). HUD elements, minimap, crosshair, pause
menu, etc. use **absolute cursor positioning escapes** (`\e[r;cH`)
to jump anywhere on screen. That's why they can be painted in any
order — each one knows exactly where it goes.

The alternate screen buffer + cursor-home redraw means each frame
overwrites the previous one in place — no flicker, no scroll, no
full clear (which would flash).

See [performance.md](performance.md) for the cost optimizations.
