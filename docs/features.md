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
- Pickups: hearts (capped at 5), armor (capped at 3, absorbs hits),
  ammo boxes (`+10` to active weapon's reserve), berserk sphere (20s
  ×2 damage), invulnerability sphere (10s i-frames), backpack
  (one-shot, doubles every weapon's reserve cap)
- Keycards + locked exit doors on L4 (blue) and L5 (red): walk over
  the `⌷` keycard to add the colour to held keys; physics blocks
  the locked door until you do
- Walk-into-door auto-advance, pulsing minimap door + bright 3D door
  glyph

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters + combat

- 5 monster types — imps, demons, cacodemons, barons, cyberdemons —
  each with distinct color, body texture, animated face glyph, aggro
  pulse at close range
- Per-level HP (L1 imp 1, L2 demon 2, L3 caco 3, L4 baron 4, L5
  cyber 5). Wounded body shades darker as HP drops; a yellow HP
  digit floats above the head for 1.2s after each hit
- Attack telegraph: face swaps to `:face-attack` glyph within
  aggro-distance (1.8 units)
- Hitscan combat: blood splatter, muzzle flash, 5-stage death anim,
  3-6s respawn cooldown
- 3-slot weapon loadout (1/2/3): pistol (10-mag, 0.12s cd, 1 dmg),
  shotgun (4-mag, 0.6s cd, 3 dmg), chaingun (30-mag, 0.05s cd, 1 dmg).
  Each weapon has its own mag size, fire cooldown, reload duration,
  damage, reserve cap, and ammo-per-box rate. Switches preserve
  per-weapon mag + reserve. Pistol-sprite drop / refill / raise
  reload animation; sprite kicks up 2 rows on every shot.
- 5 lives, 1s i-frame window post-hit, directional red band on the
  side the hit came from, knockback shove

See [monsters.md](monsters.md), [combat.md](combat.md).

## HUD + screens

- Top-left strip: row 1 hearts + armor, row 2 `L1 imps · kills · ammo`
- Compass top-centre, top-right minimap (auto-scales to ≤ 1/3 screen
  width on narrow terminals)
- Bottom strip: single dim tagline pointing at pause + F3 toggles
- F3 perf overlay (frame-ms, cast-ms, render-ms, bytes, RLE, mem,
  pos, angle, fps) — off by default, zero overhead when off
- Ammo cues: `! LOW AMMO N !` pulse top-right when firepower drops
  to 3/2/1; periodic `press R to RELOAD` above the pistol on a
  mag-keyed cadence; dry-fire `CLICK` prompt centred above pistol
- Pause menu (`p`) lists every key binding
- Start menu (any key dives in, `q` exits)
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

## Difficulty

- `--difficulty=easy|normal|hard|nightmare` (`-d`) at launch. Per-mode
  multipliers scale enemy chase speed, per-enemy HP, and per-level
  enemy count. HUD strip tags the active mode (skipped for normal).

## Misc

- WAD parser (header + lump directory + VERTEXES / LINEDEFS) — toy
  reader, not wired to render yet
- Movement uses kitty keyboard protocol for instant release on
  supported terminals; legacy hold-frames fallback elsewhere

See [wad-parser.md](wad-parser.md), [input.md](input.md).
