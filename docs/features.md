## Rendering

- 256-color ANSI raycaster, full viewport
- Sub-5ms `frame->string` at 180x40 (2ms at 80x24, 3ms at 120x30)
- Perf mode (auto-engage >= 200 cols or > 12k cells): 30 fps + 2x horizontal scale
- `proj-dist` decoupled from viewport width - resize widens FOV, not zoom
- Half-block sub-cell shading on wall edges; brick glyphs (4% of cells)
- 5-stage death animation: flash -> slump -> collapse -> blood mid -> blood dim
- Responsive help panel, collapses on tight screens
- Alt screen buffer + cursor-home redraw, zero scrollback

See [rendering.md](rendering.md), [raycaster.md](raycaster.md), [performance.md](performance.md).

## Levels + map

- 10 levels: L1-L5 procgen single-type, L6-L9 procgen mixed-type, L10 hand-authored boss arena (cyber 50 HP + 2 imps, cap 1 alive)
- Per-level wall, sky, floor palette
- Pickups: hearts (cap 5), armor (cap 5, one-hit absorb), armor shards (+1 over-cap to 10), soulsphere (+1 over-cap, decay), ammo boxes, berserk (20s 2x dmg), invuln (10s immune), stacking backpack (L2+, reserve tier per pickup)
- Keycards: L4 blue, L5 red. Locked door pulses on bump without key. L10 boss door unlocks via synthetic :boss keycard after cyber kill. Compass tints facing letter in lock color.
- Secrets: up to 2 per procgen level (L10 has hand-authored pair). Bump with F to reveal ammo + shard + rotating powerup. Skipped on locked levels.
- Walk-into-door auto-advance. Pulsing minimap + bright 3D glyph.
- Cross-level carry: lives, kills, time, weapons, active weapon, mag/reserve state, backpack, toggles. Retry/restart resets.

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters + combat

- 5 types: imps, demons, cacodemons, barons, cyberdemons. Distinct color, texture, animated face, close-range aggro pulse.
- AI: `:dormant` (LOS/noise wake) -> `:aware` (chase, contact dmg) -> `:hunting` (lost LOS, walk to last cell) -> `:attacking` (telegraphed). `:pain` (0.3s stagger) and `:wander` (opt-in patrol). Noise-wake: 4-connected BFS on every shot (walls + doors block, same-room feel).
- Per-level HP: L1 imp 1, L2 demon 2, L3 caco 3, L4 baron 4, L5 cyber 5, L10 cyber 50. Body shades darker on damage. Yellow HP digit floats 1.2s after hit.
- Shot knockback: wounding hit shoves ~1 cell back along shot direction (wall-clamped). Killing blow skips push.
- Hit-stop: meaty kills (caco/baron 70ms, cyber 160ms) freeze step briefly. Trash mobs skip it for flow.
- Pain chance per type: heavy bosses ignore most hits, fragile monsters flinch often.
- Projectile casters: cacodemons + barons fire dodgeable fireballs (telegraphed windup, orange bolt). Bolts pass doors, stop at walls. Cost one armor/life on impact (i-frames cap burst to one hit). Strafe to dodge.
- Cyber chase speed 0.55x for playability.
- Hitscan: distance-attenuated kill/wound sfx, blood splatter, muzzle flash, 5-stage death, 3-6s respawn.
- 5-slot loadout, DPS-balanced:
  - 1: pistol (1 dmg, 0.12s cd, mag 10, auto-fire, overheats)
  - 2: shotgun (3 dmg, 0.6s cd, mag 4)
  - 3: chaingun (1 dmg, 0.05s cd, mag 30, auto-fire)
  - 4: chainsaw (1 melee, 0.10s cd, melee 1.5-cell, halves move)
  - 5: BFG (10+6 splash, 1.2s cd, mag 1, plasma AoE 3-cell, rare L7)
- Pistol + chaingun + chainsaw auto-spray while held. Shotgun + BFG single-action. Pistol overheats. Mag/reserve persist across switches, auto-switch on first pickup.
- Kill-loot skips pistol when other weapons owned, biases shotgun/chaingun. Level boxes refill active weapon.
- 5 lives, 1s i-frame, 4-way directional red hurt band, knockback on contact.

See [monsters.md](monsters.md), [combat.md](combat.md).

## HUD + screens

- Top-left strip: hearts + armor + GOD badge (dev). Row 2: level/monster count, kills, weapon, ammo, backpack tier, stamina bar, keycard, difficulty tag.
- Compass top-center: facing letter yellow, locked level letter tints lock color.
- Minimap (m toggle, default OFF): top-right, auto-scales <= 1/3 width on narrow terminals. Perf mode caps 40 cols.
- F3 debug: frame-ms, cast/render split, bytes, RLE, mem, pos, angle, fps (off by default, zero overhead when off).
- Ammo cues: pulsing `! LOW AMMO N !` when <= 3 rounds; dry-fire `CLICK` prompt.
- H/ESC info menu: overlay with run stats, player status, per-weapon table, controls. Pause-coupled (freeze on open).
- P pause: minimal panel + credits.
- Start menu: any key enters, q exits.
- End screens (death + victory): cumulative kills + time + persisted bests. Restart: r (fresh seed) / R (same map), both restart on death level (victory -> L1).
- E key: snap 180° (about-face).

## Horror beats

Triggered on life drop or enemy proximity:

- Heartbeat (<=2 lives): red edge vignette + low thump every 0.85s, accelerating to 0.55s at 1 life.
- Lights flicker: brief scanline darken every 20-30s (calm), 6-12s at 1-2 lives.
- Jump-scare (enemy 3.5 units): magenta wide-eyed skull on face for 600ms.
- Sudden silence (enemy 1.5 units): all sfx muted 400ms.
- Wall haze (<=3 lives): wall shades darken as lives drop, doors stay bright (nav cue).
- Blood drops (<=3 lives): random red trails from ceiling.
- Door eye: blinking red o flashes on every visible door every 8-18s for 500ms.
- Behind: dim red blinker below compass when alive enemy in rear 90° wedge, 10 units.

## Audio

OS audio: `afplay` (macOS) / `paplay`/`aplay`/`play` (Linux) or terminal bell. Distance-scaled kill volume. N key toggles sound. Ambient drone loop: synthesised 2s 16-bit mono 22050 Hz clip, crash-safe shell loop. Tests mute with `PHEL_DOOM_SILENT=1`.

See [audio.md](audio.md).

## Persistence

High-scores: `$HOME/.phel-doom-scores.json` (best kills, best level, fastest victory). F5/F9 quick-save (slot 1): whole world to `$HOME/.phel-doom/saves/slot-<n>.json`, versioned tagged JSON codec, fog re-reveals on load. Slots 1-9 valid.

See [scores.md](scores.md), [savegame.md](savegame.md).

## CLI

- `-d/--difficulty=easy|normal|hard|nightmare`: scales enemy speed, HP, count.
- `-g/--god`: suppress contact damage, GOD badge. Dev.
- `-a/--armory`: own all weapons, infinite reserves. Pairs with --god.
- `-f/--full-map`: reveal minimap fog. Editor + screenshots.
- `-l/--level=N`: start at level N.
- `--record=FILE`: seed + per-frame input stream to demo file.
- `--demo=FILE`: replay demo deterministically (skip start menu).

All gameplay randomness via single seeded Park-Miller LCG (`core/rng`) instead of `random_int`/`mt_rand`. Seed + input stream fully determine run. Powers `--record/--demo` and fixes `R` (restart same map) to reproduce geometry.

See [demo.md](demo.md), [input.md](input.md).

## Misc

- **WAD parser**: header + lump directory + VERTEXES/LINEDEFS. Toy reader, not yet wired to render. See [wad-parser.md](wad-parser.md).
- **Keyboard**: kitty protocol (instant release: kitty, WezTerm, Ghostty, Alacritty >=0.13, iTerm2 >=3.5) or hold-frame fallback (Terminal.app, GNOME Terminal, xterm).
- **Sprint**: SHIFT+WASD or x for 1.6x speed. Drains 100-unit stamina at 30/s; regen 20/s after 0.5s cooldown. At empty, locked until recover to 20. HUD bar: amber <33%, red at 0.
