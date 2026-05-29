# Rendering

`src/io/render.phel`. Composes one ANSI string per frame, writes to stdout. Side-effecting IO layer.

Entry point: `render! [world stats cols rows]` - cursor home, pick impact flash or normal frame, flush.

```phel
(print "\e[H")                      ; cursor home
(if (php/> (get stats :flash-secs) 0.0)
  (print (white-flash-frame ...))   ; hit flash overlay
  (print (frame->string ...)))
(php/flush)
```

## frame->string pipeline

Base: raycast frame (run-length encoded). Overlays paint on top via absolute cursor positioning (`\e[r;cH`).

```
cast-frame            -> dists, sides, hxs, hys
build wall shades     -> shades-normal, shades-top-edge, shades-bot-edge per col
project enemies       -> eheads, ebodys, elegss (fade-shaded)
project pickups       -> blood-paint overlay buffer
project blood FX      -> blood-paint overlay buffer
layout                -> minimap scale/position
main row loop:        -> base frame (wall/sky/floor, enemy priority, blood overlay)
concat via php/implode
overlays (cursor-positioned):
  - bottom HUD tagline
  - F3 debug row (if :debug?)
  - minimap + fog-of-war
  - enemy faces (depth-culled)
  - crosshair, kill-streak, compass
  - game-info strip (level, kills, weapon, ammo, keys, diff)
  - health + armor HUD
  - pistol sprite + reload animation
  - muzzle flash (when firing)
  - dry-fire CLICK (out of ammo)
  - reload reminder (cadence)
  - HP digits (wounded multi-life enemies)
  - pause menu (if paused)
```

## Per-column shade composition

```
shade-idx = clamp(0, 23,
  distance-to-shade(dist)         ; base by distance
  + (side == 0 ? 1 : 0)           ; vertical face darker
  + cell-variation-hash(hx, hy))  ; ±1 mottling
```

Indexes `shade-table[0..23]`: pre-baked ANSI for 256-color grays (codes 232-255). One lookup per column.

Doors: `door-shade` (orange for unlocked, blue/red for keycards, bright red for boss-lock). Half-block edges mix door with sky/floor. Locked messages ("NEED BLUE KEY", "KILL THE BOSS") painted separately.

## Half-block edge anti-aliasing

Wall top/bottom: `▀` (upper half block) with BG for one zone, FG for the other:

```
Top:    \e[48;5;<wall>;38;5;<sky>m▀      (wall BG, sky FG)
Bottom: \e[48;5;<floor>;38;5;<wall>m▀    (floor BG, wall FG)
```

Sub-cell boundary, halves vertical aliasing.

## Distance-shaded sky and floor

Per-row shade by distance from horizon (`vh/2`): rows near horizon darkest (atmospheric haze), overhead/feet brightest. Sky and floor share the gradient, pre-baked per viewport height in `build-horizon-gradient`.

## Enemy sprite paint

Per enemy in `collect-enemy-projs`:

1. Fade `t = (dist/max-depth)²` capped at 0.85
2. Three fade-shaded strings (head/body/legs) via `fade-256` on color codes
3. Body glyph (e.g. `▒`) distinct per type for material texture
4. Writes to `eheads`, `ebodys`, `elegss` arrays per column

`project-enemy` scale factor (1.0 default, 2.0 for `:cyber`): multiplies both half-width and sprite height, so cyberdemons 2x wider AND taller (proportional). Centred vertically: feet at player horizon.

Stores `tops/bots/mids/lowers` so row loop picks correct zone per row.

Aggro blink at distance < 1.8 units.

## Face overlay (post-pass)

Per-enemy face glyph (`:enemy-face` or `:enemy-face-alt` on sin wave) at centre column, upper-third row. Depth-culled: paint only if enemy dist < wall dist at that column.

## blood-paint overlay buffer

Blood splatters + heart pickups paint into PHP array (indexed `row*vw + col`). Inner loop reads first, so overlays override walls/floors/enemies.

### Front-most-enemy gate (shadows + faces)

Two per-enemy overlays need depth-culling (issues #86, #91):

- **Grounding shadow**: `sprite-shadow` at feet, written to `blood-paint` (top layer). Deferred pass after `edists` computed.
- **Face glyph**: cursor-positioned after frame, gates on front-most enemy.

Both use `enemy-front-visible-at?`: paint only if `d < dists[c]` (in front of wall) AND `d <= edists[c]` (nearest enemy at column). `edists` (per-column nearest depth) built during zone pass.

## Run-length encoding

Consecutive same-color cells coalesce: one escape + N spaces (terminal repeats BG). Cuts output 5-10x on monochrome rows. State machine tracks `prev` + `run`, flushes on color change.

## Render-scale on big screens

Perf mode (>= 200 cols or > 12k cell area): `render-scale = 2` - cast once per 2 cols, horizontally replicate. Wall data accurate per original ray; horizontally stretched but not distorted.

## Responsive help panel

H/ESC info menu width-adaptive: max width `help-inner-width` (44), min `help-min-inner-width` (36). Drops CONTROLS section first (largest), then COMPASS HINT on squeeze. Content always fits in viewport.

## Why so many overlay passes

Walls/sky/floor/enemies go into one string via the inner row loop, top-to-bottom left-to-right. HUD, minimap, crosshair, pause menu use absolute cursor positioning escapes (`\e[r;cH`) to jump anywhere. Painted in any order; each knows where it goes.

Alternate screen buffer + cursor-home redraw means each frame overwrites the previous in place. No flicker, no scroll, no full clear.

See [performance.md](performance.md).

## Minimap fog-of-war (issue #67)

Minimap cells stay hidden behind a uniform dim `minimap-unseen` block until the player has visually crossed them. `core/engine/mark-visible-cells` runs once per frame in `tick-world`: scans a `visit-radius = 8` bounding box around the player, runs a Bresenham `los-clear?` test per candidate cell, and stamps an entry into the world's `:visited` PHP array (keyed by `y * width + x`). PHP arrays are copy-on-write so the local mutation is `assoc`d back into the world under `:visited`.

`minimap-rows` reads `:visited` via the same key and short-circuits the wall / door / pickup paint when the block is unseen, painting `minimap-unseen` instead. The pulsing pickup glyphs (heart / ammo / berserk / etc.) are only painted if the underlying cell is already visited, so a hidden treasure room reveals its contents only after the player walks within line of sight.

`:full-map?` (set by the `--full-map` / `-f` CLI flag) short-circuits the LOS scan and flips every cell; the minimap reads exactly as before this feature landed. Useful for level editors + screenshot capture.
