## Rendering

- 256-color ANSI raycaster, full viewport
- Textured stone walls: baked Freedoom flat sampled per cell by wall-hit fraction + depth fog (`PHEL_DOOM_FLAT_WALLS=1` for flat shading)
- Textured floor: floor-casting samples the stone flat on the ground plane, distance-fogged + shadowed (`PHEL_DOOM_FLAT_FLOOR=1` for the flat gradient)
- Half-block sub-pixel floor/walls/sky: `▀` cells with independent top/bottom colours give 2x vertical resolution (smaller pixels, no colour loss), memoized so CPU cost is ~+2% (`PHEL_DOOM_NO_SUBPIXEL=1` for the one-colour-per-cell path)
- Sub-5ms `frame->string` at 180x40 (2ms at 80x24, 3ms at 120x30)
- Uniform ~120fps target + crisp 1:1 walls at every terminal size (no big-screen 30fps / chunky-scale degradation)
- Auto-calibrated pixel detail, always full screen: startup measures the machine. When full detail can't hold a smooth framerate it pixel-doubles the scene (2x2 blocks, ~4x cheaper, same FOV/framing), but only on big screens (cell area beyond 200x45). Smaller terminals always keep full detail. Recalibrates on resize. `--max-cols=0` forces full detail, `--max-cols=N` insets to N columns
- `proj-dist` decoupled from viewport width: resize widens FOV, not zoom. FOV clamps at 100° on wide terminals, so they gain horizontal resolution instead of edge fisheye
- Half-block sub-cell shading on wall edges; brick glyphs (4% of cells)
- 5-stage death animation: flash -> slump -> collapse -> blood mid -> blood dim
- Responsive help panel, collapses on tight screens
- Alt screen buffer + cursor-home redraw, zero scrollback

See [rendering.md](rendering.md), [raycaster.md](raycaster.md), [performance.md](performance.md).

## Levels + map

- 10 levels: L1 pure imps (tutorial), L2-L9 hand-authored or mixed-type with a headline monster + secondaries, L10 hand-authored boss arena (cyber 50 HP + 2 imps, cap 1 alive)
- Per-level floor theme: `:theme` tints the floor gradient (grey / steel / moss / clay / rust / hell), so episodes read as distinct places. Walls + sky stay shared grayscale.
- Pickups: hearts (heal one full heart; pool is 5 hearts / 10 HP), armor (cap 5, absorbs one whole hit), armor shards (+1 over-cap to 10), soulsphere (over-cap to 14 HP, decays), ammo boxes, berserk (18s 2x dmg), invuln (10s immune), stacking backpack (L2+, reserve tier per pickup)
- Keycards: L4 blue, L5 red, L7 yellow. Locked door pulses on bump without key. L10 boss door unlocks via synthetic :boss keycard after cyber kill. Compass tints facing letter in lock color.
- Secrets: up to 2 per procgen level (L10 has hand-authored pair). Bump with F to reveal ammo + shard + rotating powerup. Skipped on locked levels.
- Walk-into-door auto-advance. Pulsing minimap + bright 3D glyph.
- Cross-level carry: lives, kills, time, weapons, active weapon, mag/reserve state, backpack, toggles. Retry/restart resets.

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters + combat

- 10 types: imps, demons, cacodemons, barons, cyberdemons, spectres, revenants, archviles, mancubi, pinkies. Distinct color, texture, animated face, close-range aggro pulse.
- AI: `:dormant` (LOS/noise wake) -> `:aware` (chase, contact dmg) -> `:hunting` (lost LOS, walk to last cell) -> `:attacking` (telegraphed). `:pain` (0.3s stagger) and `:wander` (opt-in patrol). Noise-wake: 4-connected BFS on every shot (walls + doors block, same-room feel).
- Per-level HP: L1 imp 1, L2 demon 2, L3 caco 3, L4 baron 4, L5 cyber 5, L6 spectre 3, L7 revenant 4, L8 archvile 5, L9 pinky 2, L10 cyber 50. Body shades darker on damage. Yellow HP digit floats 1.2s after hit.
- Shot knockback: wounding hit shoves ~1 cell back along shot direction (wall-clamped). Killing blow skips push.
- Hit-stop: meaty kills (caco/baron 70ms, cyber 160ms) freeze step briefly. Trash mobs skip it for flow.
- Pain chance per type: heavy bosses ignore most hits, fragile monsters flinch often.
- Projectile casters: cacodemons + barons fire dodgeable fireballs (telegraphed windup, orange bolt). Bolts pass doors, stop at walls. Cost one armor/life on impact (i-frames cap burst to one hit). Strafe to dodge.
- Cyber chase speed 0.55x for playability.
- Hitscan: distance-attenuated kill/wound sfx, blood splatter, muzzle flash, 5-stage death, 3-6s respawn.
- 7-slot loadout, DPS-balanced:
  - 1: pistol (1 dmg, 0.12s cd, mag 10, auto-fire, pierces every enemy in line)
  - 2: shotgun (3 dmg + 1 graze x3 cone, 0.6s cd, mag 4)
  - 3: chaingun (1 dmg, 0.05s cd, mag 30, auto-fire)
  - 4: chainsaw (1 melee, 0.10s cd, melee 1.5-cell, halves move)
  - 5: BFG (10 + 6 splash, 1.2s cd, mag 1, plasma AoE 3-cell, rare L7)
  - 6: incinerator (1 fire dmg, 0.06s cd, mag 40, auto-fire; fire-resist mobs take 0, L6)
  - 7: rocket launcher (4 + 3 splash r2.0, 0.9s cd, mag 1, single-action, ballistic AoE, L5)
- Pistol + chaingun + chainsaw auto-spray while held. Shotgun + BFG + rocket single-action. Mag/reserve persist across switches, auto-switch on first pickup.
- Kill-loot skips pistol when other weapons owned, biases shotgun/chaingun. Level boxes refill active weapon.
- Half-heart health: 10 HP drawn as 5 hearts (2 HP each), starting full. Hits cost by attacker type: 1 (half heart) for light melee, 2 (full heart) for heavy bruisers + casters, 3 for the cyberdemon boss. 1s i-frame, 4-way directional red hurt band, knockback on contact. Armor absorbs a whole hit.

See [monsters.md](monsters.md), [combat.md](combat.md).

## HUD + screens

- Top-left strip: hearts + armor + GOD badge (dev). Row 2: level/monster count, kills, weapon, ammo, backpack tier, stamina bar, keycard, difficulty tag.
- Compass top-center: facing letter yellow. A quest-target letter tints toward the objective: the un-picked keycard (lock colour) on a locked level, or the exit door (orange) once the key is in hand or on a plain level.
- Objective subtitle on the level-intro splash: `FIND THE <COLOUR> KEY` on locked levels, `KILL THE BOSS TO ESCAPE` on the boss arena, `FIND THE EXIT` (orange, matching the compass arrow) on plain levels. Every level states its goal.
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

- Heartbeat (last 2 hearts, <=4 HP): steady dim-red edge vignette + low thump every 0.90s, accelerating to 0.55s in the last heart. The edge no longer throbs (calm 3D view); the thump audio still pulses.
- Sudden silence (enemy 1.5 units): all sfx muted 400ms.
- Wall haze (last 3 hearts, <=6 HP): wall shades darken as health drops, doors stay bright (nav cue).
- Blood drops (last 3 hearts, <=6 HP): random red trails from ceiling.
- Behind: steady dim-red `‹ behind ›` cue below compass when alive enemy in rear 90° wedge, 10 units.

The decorative lights-flicker, the jump-scare face flash, and the blinking door-eye were removed for a calmer 3D view (see [Accessibility](#accessibility) and [rendering.md](rendering.md#calm-3d-view-no-decorative-blinks)).

## Accessibility

- High contrast (Settings toggle, default off): un-dims the dim/grey HUD elements (compass non-facing letters, empty heart pips, healthy ammo reserve) to bold white so the HUD reads on washed-out / low-quality terminals. Pure overlay branch, no frame-speed cost.
- Calm 3D view (default for everyone): the gameplay view carries no decorative blinks or strobes. Removed entirely (decoration, no info): the lights-flicker overlay, the jump-scare face flash, the blinking door-eye. Held steady (info kept, on/off pulse dropped): the low-health heartbeat edge, the berserk border, the low-ammo / behind-you / reload HUD labels, the powerup banners, the JAMMED chip, the low-health hearts strip. Doors and aggro heads stay steady-bright. No `\e[5` terminal hardware-blink anywhere in the renderer. Kept: the essential single-shot feedback (directional hit-vignette, kill flash, CLICK prompt, crosshair hit-marker) and the gentle interactive-pickup glow. Pure overlay branch, no frame-speed cost. See [rendering.md](rendering.md#calm-3d-view-no-decorative-blinks).

## Audio

OS audio: `afplay` (macOS) / `paplay`/`aplay`/`play` (Linux) or terminal bell. Distance-scaled kill volume. N key toggles sound. Background OST: an original, license-clean riff synthesised to a 16-bit mono 22050 Hz WAV, looped by a crash-safe shell. Tests mute with `PHEL_DOOM_SILENT=1`.

See [audio.md](audio.md).

## Persistence

High-scores: `$HOME/.phel-doom-scores.json` (best kills, best level, fastest victory). F5/F9 quick-save (slot 1): whole world to `$HOME/.phel-doom/saves/slot-<n>.json`, versioned tagged JSON codec, fog re-reveals on load. Slots 1-9 valid.

See [scores.md](scores.md), [savegame.md](savegame.md).

## CLI

- `-d/--difficulty=easy|normal|hard|nightmare`: scales enemy speed, HP, count, the ammo-box budget, and the heal/armor pickup counts (hard x1.2, nightmare x1.5: nightmare seeds 2 hearts + 5 armor shards vs the 1 + 3 baseline). Rare powerup odds stay flat.
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
- **Mouse look (#246)**: FPS-style mouselook in the terminal via xterm SGR mouse reports. Move the pointer to turn the camera (yaw) and look up/down (pitch), left-click to fire (held = auto-fire). The fixed-centre crosshair is the gun's aim point. Mouse edges sustain the turn when the pointer hits the terminal border. On by default, toggled by the **Mouse** setting. Turn speed scales with **Sensitivity** (50% = neutral 1.0x). Additive only: the keyboard path is untouched. See [input.md](input.md#mouse-look-issue-246).
- **Look up/down + vertical-aware aim (#243)**: camera pitch (arrow keys or mouse) shears the horizon as a pure render offset. Hitscan is gated on the crosshair landing on the enemy's drawn sprite, so aiming at the floor or sky misses. Pitch-0 renders byte-for-byte like no pitch. See [input.md](input.md#look-updown-pitch), [combat.md](combat.md), [raycaster.md](raycaster.md#look-updown-pitch-horizon-shear).
- **Sprint**: SHIFT+WASD or x for 1.6x speed. Drains 100-unit stamina at 30/s; regen 20/s after 0.5s cooldown. At empty, locked until recover to 20. HUD bar: amber <33%, red at 0.
