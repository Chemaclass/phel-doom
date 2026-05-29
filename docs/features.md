# Features

What the game actually does, grouped by subsystem so you know where to
look in the source. Per-subsystem write-ups are linked from [README.md](README.md).

## Rendering

- 256-color ANSI raycaster, full-terminal viewport
- Sub-5ms `frame->string` at 180×40 (~2ms at 80×24, ~3ms at 120×30)
- **Perf mode** (auto-engage on terminals ≥ 200 cols or > 12k cells): 30 fps + 2× horizontal render-scale
- `proj-dist` decoupled from viewport width - resizing widens FOV instead of zooming walls
- Half-block sub-cell shading on wall top/bottom edges; brick-texture glyphs (~4% of cells)
- 5-stage death animation: kill flash → slump → collapse → blood mid → blood dim
- Responsive help panel (collapses sections on tight screens)
- Alt screen buffer + cursor-home redraw (zero scrollback noise)

See [rendering.md](rendering.md), [raycaster.md](raycaster.md), [performance.md](performance.md).

## Levels + map

- 10 levels: 5 procedurally-generated escalating rooms (L1-L5), 4 mixed-monster rooms (L6-L9), and L10 a hand-authored boss arena (cyberdemon HP 50 + 2 imp minions, cap 1 alive)
- Per-level wall + sky + floor palette
- Pickups: hearts (cap 5), armor (cap 5, absorbs one hit each), armor shards (+1 over-cap up to 10, no decay), soulsphere (+1 life over-cap, decays back to cap), ammo boxes (per-weapon `:ammo-per-box`), berserk (20s ×2 dmg), invuln (10s immune), stacking backpack (L2+, each pickup adds one tier of reserve cap, up to `max-backpacks`)
- Keycards + locked exits on L4 (blue) / L5 (red). Intro splash adds a `FIND THE <COLOUR> KEY` subtitle on locked levels; compass top-centre tints the E/S/W/N letter pointing at the un-picked card in the lock colour; bumping the door without the matching key pulses `⚿ NEED <COLOUR> KEY ⚿` for 1.5s. L10 boss door unlocks via synthetic `:boss` keycard granted on cyberdemon kill (no physical pickup); intro splash: `KILL THE BOSS TO ESCAPE`, door pulse: `☠ KILL THE BOSS ☠`
- Walk-into-door auto-advance; pulsing minimap door + bright 3D door glyph
- Cross-level carry: lives, kills, time, owned-weapons, **active weapon**, **per-weapon mag/reserve**, backpack, minimap + sound toggles. Retry/restart resets to fresh defaults.

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters + combat

- 5 monster types - imps, demons, cacodemons, barons, cyberdemons - each with distinct color, body texture, animated face glyph, aggro pulse at close range
- **AI state machine**: `:dormant` (passive until LOS/noise), `:aware` (chasing w/ contact dmg), `:hunting` (lost LOS, walks toward last-seen cell), `:pain` (hit-stagger 0.3s), `:attacking` (telegraphed strike window), `:wander` (opt-in random patrol). Wake triggers: LOS via raycaster, noise via 3-cell BFS around player fire, being hit. Noise-wake on every shot fires a 4-connected BFS to wake dormant enemies (walls + doors block, same-room feel).
- Per-level HP (L1 imp 1, L2 demon 2, L3 caco 3, L4 baron 4, L5 cyber 5; L10 boss cyber 50). Wounded body shades darker as HP drops; a yellow HP digit floats above the head for 1.2s after each hit
- Shot knockback: every wounding hit shoves the enemy ~1 cell back along the shot direction (wall-clamped; killing blow skips push so corpse lands on death cell)
- Hit-stop: a meaty kill (caco / baron ~70ms, boss ~160ms) briefly freezes the gameplay step so the blow lands with weight. Trash mobs (imps / demons) skip it so chaingun flow stays fast. See `combat/hit-stop-for`.
- Pain chance per type (`cyber 0.05`, `imp 0.35`, etc.) - heavier bosses ignore most hits; fragile monsters flinch on nearly every shot
- Projectile casters: cacodemons + barons fire dodgeable fireballs (long-range telegraphed windup, then an orange bolt aimed at your position). Bolts pass doorways, stop at walls, cost one armor/life on impact (i-frames gate a burst to one hit). Strafe or break line of fire to dodge. See `core/projectile.phel`.
- Cyberdemon chase speed scaled to 0.55× for playability
- Hitscan combat: distance-attenuated kill/wound sfx, blood splatter, muzzle flash, 5-stage death anim, 3-6s respawn cooldown
- 4-slot loadout (1/2/3/4), DPS-balanced niches. Pistol on every run; rest must be found.

  | Slot | Weapon | Dmg | Cd | Mag | DPS | Tier |
  |---|---|---|---|---|---|---|
  | 1 | pistol | 1 | 0.12s | 10 | 8 | L1 (auto-fire, overheats) |
  | 2 | shotgun | 3 | 0.6s | 4 | 5 | L2 (single-action) |
  | 3 | chaingun | 1 | 0.05s | 30 | 20 | L3 (auto-fire) |
  | 4 | chainsaw | 1 (`:melee`) | 0.10s | ∞ | 10 | melee 1.5-cell range, halves movement while ticking |

  Pistol + chaingun + chainsaw spray while space is held; shotgun needs a fresh pull per shell. Pistol is the only weapon that overheats / jams. Distinct silhouette + palette per slot. Per-weapon mag/reserve persists across switches. First-time pickup auto-switches. Drop/refill/raise reload anim; sprite recoils 2 rows per shot.
- Kill-loot ammo skips the pistol when other weapons are owned - biases toward the scarce shotgun + chaingun the player had to hunt for. Level-spawn boxes still refill the active weapon.
- 5 lives, 1s i-frame, 4-way directional red hurt-side band (left / right edge bar OR top / bottom row depending on attacker bearing), knockback shove on contact damage.

See [monsters.md](monsters.md), [combat.md](combat.md).

## HUD + screens

- Top-left strip: row 1 hearts + armor + `GOD` badge (dev mode), row 2 `L1 imps · kills · weapon · ammo · +pack · STA ████████░░ · ⚿ · [diff]`
- Compass top-centre (facing letter yellow; on locked levels the letter pointing at the un-picked key tints blue/red).
- **Minimap** (`m` toggle, **default OFF**) - top-right, auto-scales to ≤ 1/3 width on narrow terminals. Perf mode caps at 40 cols. Separate toggle from help menu.
- F3 debug overlay (frame-ms, cast/render split, bytes, RLE, mem, pos, angle, fps) - off by default, zero overhead when off
- Ammo cues: pulsing `! LOW AMMO N !` top-right when firepower drops to 3/2/1; periodic `press R to RELOAD`; dry-fire `CLICK` prompt
- **H / ESC** info menu - overlay panel with run stats / player status / per-weapon table / full controls. Responsive layout (sections collapse on narrow terminals). Couples with pause (opening freezes the game).
- Pause panel (`p`) is minimal: PAUSED + "H for info menu" + credits
- Start menu (any key dives in, `q` exits)
- End screens (death + victory) with cumulative kills + time + persisted bests. Restart: `r` fresh seed / `R` same map; both restart on the level you died on (victory restarts at L1)
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
  400ms - strike lands in silence
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
- Ambient drone loop: a low, slow-pulsing background bed runs the whole
  session for dread. Synthesised at runtime (no shipped asset), looped
  by a crash-safe background process, gated by the N toggle. See
  `io/ambient.phel`.
- Distance-scaled kill volume
- All sfx gated by sound-on toggle (`n`)
- Tests run with `PHEL_DOOM_SILENT=1` - no audio during the suite

See [audio.md](audio.md).

## Persistence

- High-scores in `$HOME/.phel-doom-scores.json`: per-level best
  kills + best time + last-run timestamp
- Pure `merge-run` fn (testable) wrapping the IO writer

See [scores.md](scores.md).

## CLI

- `--difficulty=easy|normal|hard|nightmare` (`-d`) - scales enemy chase speed, per-enemy HP, per-level enemy count. HUD tag suppressed for `normal`.
- `--god` (`-g`) - contact damage suppressed; GOD badge in HUD. Dev.
- `--armory` (`-a`) - own every weapon + infinite reserves (per-frame refill). Pairs with `--god` for mechanic testing.
- `--full-map` (`-f`) - reveal whole minimap (skip fog-of-war). Level-editor + screenshots.
- `--level=N` (`-l`) - start at level N (clamped). Pairs with `--god` to drop into boss rooms.

## Misc

- **WAD parser** (header + lump directory + VERTEXES / LINEDEFS) - toy reader, not wired to render yet. See [wad-parser.md](wad-parser.md).
- **Keyboard**: kitty protocol for instant release on supported terminals (kitty, WezTerm, Ghostty, Alacritty ≥0.13, iTerm2 ≥3.5); legacy hold-frame fallback on Terminal.app / GNOME Terminal / xterm. See [input.md](input.md).
- **Sprint**: hold **SHIFT+WASD** or **`x`** (anywhere) for 1.6× move/strafe speed. Drains a 100-unit `:stamina` pool at 30/s; regenerates at 20/s after a 0.5s cooldown. At empty, sprint stays locked until stamina recovers to 20. HUD shows a 10-cell `STA ████████░░` bar that turns amber under 33% and red at 0.
