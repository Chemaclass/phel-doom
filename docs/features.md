# Features

One line per feature. The linked doc holds the detail.

## Rendering

- 256-colour ANSI raycaster, full viewport, alt screen buffer with cursor-home redraw (zero scrollback).
- Textured stone walls and a floor-cast textured floor, both distance-fogged. `PHEL_DOOM_FLAT_WALLS=1` / `PHEL_DOOM_FLAT_FLOOR=1` restore flat shading.
- Half-block sub-pixels: `▀` cells with independent top/bottom colours double vertical resolution for about +2% CPU. The **Sub-pixel** setting (or `PHEL_DOOM_NO_SUBPIXEL=1`) turns it off.
- Enemies, pickups, corpses and fireballs are baked Freedoom sprites. `PHEL_DOOM_NO_SPRITES=1` falls back to glyph monsters.
- Resizing widens the FOV (clamped at 100 degrees) instead of zooming.
- Full screen, ~120fps cap. Big screens (beyond 200x45 cells) that cannot hold the framerate pixel-double the scene. `--max-cols` / `--max-rows` override.

See [rendering.md](rendering.md), [raycaster.md](raycaster.md), [performance.md](performance.md).

## Levels + map

- 10 levels. L1 (imp tutorial) and L9 are fully procgen. L2-L8 use a fixed room shell with random interior walls. L10 is a hand-authored cyberdemon arena (50 HP boss). Table: [level-system.md](level-system.md#levels-at-a-glance).
- The exit door is placed at random on every level, every run. Walk into it to advance.
- Keycards: blue L4, red L5, yellow L7. The L10 exit opens when the boss dies.
- Secrets: up to 2 auto-seeded on L1 and L9, a hand-authored pair on L10. F reveals one and drops a reward stash.
- Switches (L10): F opens and shuts walls.
- Per-level floor tint themes.
- Lives, weapons, ammo and backpack carry across levels. A death retry replays the level with the loadout you entered it with.

See [level-system.md](level-system.md), [map.md](map.md).

## Monsters

- 10 types: imp, demon, cacodemon, baron, cyberdemon, spectre, revenant, archvile, mancubus, pinky. Stats: [monsters.md](monsters.md#stats-comparison).
- AI states: dormant, wander, aware, hunting, pain, attacking. Break line of sight and hunters search your last-known position, then give up.
- Wake on sight, on being shot, or on gunfire within 3 floor cells.
- Telegraphed attacks: a frozen windup, an attack pose and a `!` over the head.
- Casters (caco, baron, archvile) throw dodgeable fireballs.
- Respawn after 3-6s out of your sight. Deeper levels attack up to 25% more often.

See [monsters.md](monsters.md).

## Combat + weapons

- 7 weapons, niches not upgrades: pistol (pierces every enemy in line, not walls), shotgun (cone), chaingun, chainsaw, BFG (plasma splash), incinerator (fire), rocket launcher (splash). Table: [gameplay.md](gameplay.md#weapons).
- Fire resistance: caco, baron, archvile and mancubus take 0 from the incinerator.
- Vertical-aware aim (#243): a shot must land on the drawn sprite. The crosshair turns red while one would connect (#458).
- Hit feedback: blood, knockback, hit-stop on tough kills, pain stagger, HP digits, kill loot.
- 10 HP as 5 hearts; hits cost 1-3 HP; armor absorbs a whole hit; directional damage arc.
- Pickups: hearts, armor, shards, soulsphere, berserk, invuln, backpack. See [gameplay.md](gameplay.md#pickups).

See [combat.md](combat.md).

## HUD + screens

- Top-left: hearts and armor, then level, kills, weapon, ammo, and optional chips (stamina, backpack, key, difficulty, timer) while they fit.
- Compass: the letter toward your goal tints in the key colour or exit orange. The intro splash states the goal: `FIND THE <COLOUR> KEY`, `KILL THE BOSS TO ESCAPE`, or `FIND THE EXIT`.
- First-run key hints on L1.
- Minimap (`m`, off by default) with fog of war.
- Ammo cues: `LOW AMMO N` at 3 rounds or fewer, reload nag, dry-fire `CLICK`, ` READY! `.
- Menus: info (`h` / `ESC`), pause (`p`: Resume / Settings / Restart / Quit), start (ENTER or space plays, `s` settings, `q` quits).
- End screens: run summary, rank S-D, bests.
- `F3` debug overlay, zero cost when off.

## Horror beats

- Heartbeat at 4 HP or less: steady dim-red edge vignette and a thump every 0.90s, 0.55s at 2 HP or less.
- Wall haze at 6 HP or less: walls darken as health drops; doors stay bright.
- Blood drops at 6 HP or less: red trails fall from the ceiling.
- Sudden silence: all sfx mute for 0.4s when an enemy closes inside 1.5 units.
- Behind cue: a steady `‹ behind ›` under the compass when an enemy is within 5 units in your rear 90 degrees.

The lights-flicker, jump-scare face and blinking door-eyes were removed (see [Accessibility](#accessibility)).

## Accessibility

- Calm 3D view for everyone: no decorative blinks or strobes. Decoration was removed; information cues hold steady instead of pulsing; one-shot feedback (hit arc, kill flash, hit-marker) stays. See [rendering.md](rendering.md#calm-3d-view-no-decorative-blinks).
- High contrast setting: dim HUD elements render bold white.
- View bob is off by default.

## Audio

System audio player (`afplay`, `paplay`, `aplay`, `play`), else the terminal bell. Distance-scaled sfx, per-type monster cries, an original synthesised soundtrack. `n` toggles sound; `PHEL_DOOM_SILENT=1` mutes everything (tests). See [audio.md](audio.md).

## Persistence

- High scores in `$HOME/.phel-doom-scores.json`: best kills, deepest level, fastest victory. See [scores.md](scores.md).
- `F5` / `F9` quick-save / load slot 1 to `$HOME/.phel-doom/saves/slot-<n>.json` (slots 1-9). Fog of war re-reveals on load. See [savegame.md](savegame.md).
- Settings in `$HOME/.phel-doom-settings.json`. See [settings.md](settings.md).

## CLI + determinism

- Flags: `--difficulty`, `--level`, `--god`, `--armory`, `--full-map`, `--record`, `--demo`, `--max-cols`, `--max-rows`. See [gameplay.md](gameplay.md#cli-flags).
- 4 difficulties: easy, normal, hard, nightmare. See [level-system.md](level-system.md#difficulty).
- One seeded Park-Miller generator (`core/rng`) drives all gameplay randomness, so seed plus input determine a run: `--record` / `--demo` and `R` rely on it. See [demo.md](demo.md).

## Input

- WASD move and strafe, left/right arrows turn, up/down arrows look. See [gameplay.md](gameplay.md#controls).
- Mouse look (#246), on by default; left-click fires. See [input.md](input.md#mouse-look-issue-246).
- Look up/down (#243) shears the horizon; level gaze renders byte-for-byte like no pitch. See [raycaster.md](raycaster.md#look-updown-pitch-horizon-shear).
- Sprint: `SHIFT`+WASD or `x`, 1.6x speed on a 100-point stamina pool (drain 30/s, regen 20/s after 0.5s, locked until 20). The HUD chip is white, amber under 33%, red when latched. See [input.md](input.md#sprint).
- Kitty keyboard protocol for instant key release, hold-frame fallback elsewhere. See [input.md](input.md#kitty-keyboard-protocol).

## Misc

- WAD parser: header, lump directory, VERTEXES/LINEDEFS. A toy reader, not wired to the renderer. See [wad-parser.md](wad-parser.md).
