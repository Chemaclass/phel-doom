# Features

What the game actually does, grouped by subsystem so you know where to
look in the source. Per-subsystem write-ups are linked from [README.md](README.md).

## Rendering

- 256-color ANSI raycaster, full-terminal viewport
- Sub-5ms `frame->string` at 180×40 (~2ms at 80×24, ~3ms at 120×30)
- `proj-dist` decoupled from viewport width — resizing widens FOV
  instead of zooming walls
- Half-block sub-cell shading on wall top/bottom edges; brick-texture
  glyphs (~4% of cells)
- 5-stage death animation: kill flash → slump → collapse → blood mid
  → blood dim
- Alt screen buffer + cursor-home redraw (zero scrollback noise)

See [rendering.md](rendering.md), [raycaster.md](raycaster.md),
[performance.md](performance.md).

## Levels + map

- 5 procedurally-generated levels, escalating difficulty
- Per-level wall + sky + floor palette
- Heart pickups (refill life, capped at 5) + armor pickups (absorb
  one hit)
- Walk-into-door auto-advance, pulsing minimap door + bright 3D door
  glyph

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters + combat

- 5 monster types — imps, demons, cacodemons, barons, cyberdemons —
  each with distinct color, body texture, animated face glyph, aggro
  pulse at close range
- Attack telegraph: face swaps to `:face-attack` glyph within
  aggro-distance (1.8 units)
- Hitscan combat: blood splatter, muzzle flash, 5-stage death anim,
  3-6s respawn cooldown
- Pistol with fire cooldown + heat / overheat jam
- 5 lives, 1s i-frame window post-hit, directional red band on the
  side the hit came from, knockback shove

See [monsters.md](monsters.md), [combat.md](combat.md).

## HUD + screens

- Top-left heart + armor HUD, bottom HUD line
- Compass strip, kill-streak counter, live minimap
- Pause menu (`p`), start menu (any key dives in, `q` exits)
- End screens (death + victory) with cumulative kills + time and
  persisted bests
- Restart from end screen: `r` fresh seed, `R` same map; both
  restart on the level you died on (victory restarts at L1)
- About-face on `e` (snap 180°)

## Horror beats

Triggered as the player's lives drop or enemies cross thresholds:

- **Heartbeat** (≤ 2 lives): pulsing red edge vignette + low thump
  every ~0.85s, accelerating to ~0.55s at 1 life
- **Lights flicker**: brief scanline darken every ~20-30s (calm),
  ~6-12s at 1-2 lives
- **Jump-scare** (enemy crosses 3.5 units inbound): wide-eyed
  magenta skull on the enemy face for 600ms
- **Sudden silence** (enemy crosses 1.5 units): all sfx muted for
  400ms — strike lands in silence
- **Wall haze** (≤ 3 lives): wall shade-table index shifts toward
  black as life drops; doors keep full brightness as nav cue
- **Blood drops** (≤ 3 lives): random red trails drip from the
  ceiling
- **Disembodied door eye**: blinking red `ʘ` flashes on every
  visible door cell for ~500ms every 8-18s
- **`‹ behind ›`**: dim red blinker below the compass when an alive
  enemy sits in the player's rear 90° wedge within 10 units

## Audio

- OS audio via `afplay` (macOS) / `paplay` / `aplay` / `play`
  (Linux) with terminal-bell fallback on bare systems
- Distance-scaled kill volume
- All sfx gated by sound-on toggle (`n`)
- Tests run with `PHEL_DOOM_SILENT=1` — no audio during the suite

See [audio.md](audio.md).

## Persistence

- High-scores in `$HOME/.phel-doom-scores.json`: per-level best
  kills + best time + last-run timestamp
- Pure `merge-run` fn (testable) wrapping the IO writer

See [scores.md](scores.md).

## Misc

- WAD parser (header + lump directory + VERTEXES / LINEDEFS) — toy
  reader, not wired to render yet
- Movement uses kitty keyboard protocol for instant release on
  supported terminals; legacy hold-frames fallback elsewhere

See [wad-parser.md](wad-parser.md), [input.md](input.md).
