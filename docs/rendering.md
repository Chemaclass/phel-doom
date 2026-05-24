# Rendering

`src/modules/io/render.phel`. Composes one ANSI string per frame and writes to stdout. Side-effecting, hence `io/`.

## Entry point

```phel
(defn render! [world stats cols rows]
  (print "\e[H")                                  ; cursor home
  (if (php/> (or (get stats :flash-secs) 0.0) 0.0)
    (print (white-flash-frame cols rows))         ; on-hit jolt
    (print (frame->string world stats cols rows)))
  (php/flush))
```

`render!` picks normal frame vs the 1-frame all-white impact flash.

## frame->string pipeline

```
(frame->string world stats cols rows)
  │
  ├── layout cols rows grid-w → vw, vh, map-col, map-row, map-step, map-mw
  │     (map-step >= 2 collapses every step×step grid block into one
  │      minimap cell so the map stays under ~1/3 of the screen width)
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
  │     - bottom HUD line (hud-line — dim tagline)
  │     - F3 debug row (hud-debug-line, when :debug? is on)
  │     - minimap (top-right rows, auto-scaled to ≤ 1/3 vw)
  │     - face glyphs (per enemy, occluded by walls)
  │     - wall-mounted torches, door-face indicator
  │     - crosshair (centre), kill-streak counter, compass
  │     - rear-warning (centre row 2 when :rear-warning?)
  │     - LOW AMMO N pulse (right row 1 when firepower ≤ 3)
  │     - game-info strip (top-left row 2: L# · kills · weapon · ammo · +pack · STA bar · keys · [diff])
  │     - top-left hearts + armor HUD (row 1)
  │     - pistol sprite + reload-drop animation (centre-bottom)
  │     - muzzle flash (when :fire-anim > 0 and drop = 0)
  │     - dry-fire CLICK prompt (above pistol on empty trigger)
  │     - periodic press-R-to-RELOAD reminder (mag-keyed cadence)
  │     - floating HP digits above wounded multi-life enemies
  │     - pause menu (if :paused)
  └── concat everything via php/implode into one string
```

Base layer is the raycast frame encoded as run-length-coalesced ANSI cells. Overlays paint on top via absolute cursor positioning.

## Per-column shade composition

```phel
idx = clamp(0, 23,
            distance-to-shade(dist)        ; base by distance
            + (side == 0 ? 1 : 0)          ; vertical-face darken
            + cell-variation-hash(hx, hy)) ; ±1 mottling
```

Indexes `shade-table[0..23]`: pre-baked ANSI strings for the 256-color grayscale palette (232..255). One PHP-array lookup per column.

Door columns get solid `door-shade` (orange for unlocked, blue/red for locked keycards, bright red for boss-lock) in `shades-normal` and a half-block edge mix in `shades-top-edge`/`shades-bot-edge`. Paint function `paint-locked-bump` handles door-locked state messaging (e.g. "NEED BLUE KEY" or "KILL THE BOSS").

## Half-block edge anti-aliasing

Wall tops/bottoms emit `▀` (UPPER HALF BLOCK) with FG painting the top half and BG the bottom half:

```phel
;; Top of wall column: sky above, wall below in the same cell
"\e[48;5;<wall-code>;38;5;<sky-code>m▀"

;; Bottom of wall column: wall above, floor below in the same cell
"\e[48;5;<floor-code>;38;5;<wall-code>m▀"
```

Sub-cell wall boundary instead of flat stair. Halves vertical aliasing.

## Distance-shaded sky + floor

```phel
(build-horizon-gradient vh shade-table)
```

Each row gets a pre-baked sky/floor shade by distance from horizon (`vh/2`). Rows near horizon darkest (atmospheric haze); overhead and feet brightest. Sky and floor share the gradient.

## Enemy sprite paint

Each visible enemy projects to centre column + half-width (`collect-enemy-projs`):

1. Fade factor `t = (dist/max-depth)²` capped at 0.85.
2. Three fade-shaded ANSI strings (`fhead`, `fbody`, `flegs`) via `fade-256` on `:head-code` / `:body-code` / `:legs-code`.
3. Body embeds `:body-glyph` (e.g. `▒`) in a darker FG so each monster has a distinct material pattern.
4. Writes into per-column arrays `eheads` / `ebodys` / `elegss`.
5. Records `tops` / `bots` / `mids` / `lowers` so the inner row loop picks head/body/legs per row.

Aggro branch swaps in a blink-attributed cell within `aggro-distance` (1.8 world units).

## Face overlay (post-pass)

Iterates visible enemies after the main frame composes; paints one face glyph (`:enemy-face` or `:enemy-face-alt` on a sin wave) at the enemy's centre column, upper-third row. Occluded by walls: paints only when enemy distance < wall distance at that column.

## blood-paint overlay buffer

Blood splatters from kills + heart pickups paint into a PHP array `blood-paint` indexed by `row * vw + col`. Inner loop reads first via `(or (php/aget blood-paint ...) main-cond)` so overlays override wall/floor/enemy paint.

## Run-length encoding

Consecutive cells with the same ANSI escape coalesce into one paint + N spaces:

```
\e[48;5;240m     (set BG once)
"         "      (12 spaces, terminal repeats the BG)
\e[48;5;238m     (BG change)
"     "          (5 spaces)
```

Cuts output 5-10× on same-colour rows. In-line state machine tracks `prev` + `run`, flushes on colour change.

## Why so many overlay passes

Walls/sky/floor/enemies go into one string via the inner row loop, top-to-bottom left-to-right. HUD, minimap, crosshair, pause menu use absolute cursor positioning escapes (`\e[r;cH`) to jump anywhere. Painted in any order; each knows where it goes.

Alternate screen buffer + cursor-home redraw means each frame overwrites the previous in place. No flicker, no scroll, no full clear.

See [performance.md](performance.md).
