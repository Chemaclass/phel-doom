# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

**Weapons + combat**
- 3-slot loadout (1/2/3) with DPS-balanced niches: pistol 1 dmg @ 0.12s cd (8 dps fallback), shotgun 3 dmg @ 0.6s cd (5 dps burst killer — 1-shots L1-L3 enemies, 2-shots the L5 baron), chaingun 1 dmg @ 0.05s cd (20 dps sustained spray, ammo hog). Picking up a chaingun does NOT obsolete the shotgun — they own different niches. Per-weapon mag + reserve persist across switches. Each weapon has its own SGR palette so the bottom sprite reads as a distinct piece of kit.
- Auto-fire while space held for pistol + chaingun (`:auto-fire? true` in weapons spec). Without it, the chaingun's 0.05s cd was capped by the player's tap rate, so the 20 dps niche was unreachable. Shotgun stays single-action — each shell requires a fresh trigger pull.
- Overheat / jam is now pistol-only (`:overheats? true`). Chaingun would otherwise jam in ~0.4s of held auto-fire (0.30 heat-per-shot × 20 shots/s) — that's anti-feature for a "sustained spray" weapon. Pistol still risks jam if you mash the trigger; trade-off for its high-tap-rate niche.
- Kill-loot ammo drops now carry a `:weapon` tag chosen uniformly from the player's `:owned-weapons` set. Walking over the box tops up THAT weapon's reserve, even if you're holding something else — so every kill seeds usable ammo regardless of what's in your hand. Level-spawned ammo boxes still refill the active weapon.
- Finite ammo (closes #5): reserve + scaled box pickups + 1.2s reload animation + layered reload cues (LOW AMMO pulse, periodic press-R, dry-fire CLICK).
- Per-level enemy HP 1→5; wounded body shades darker, yellow HP digit above head 1.2s post-hit. Kill rolls a loot drop (ammo > armor > heart, ~75% nothing).
- Pistol sprite recoils up 2 rows on shoot (no more screen tilt).

**Powerups + pickups**
- Berserk sphere — 20s × 2 damage (~1 in 8 levels).
- Invulnerability sphere — 10s damage immunity (~1 in 12 levels).
- Backpack (L2+, one-shot, ~1 in 5 qualifying levels) — doubles every weapon's reserve cap for the rest of the run.
- Keycards + locked exit on L4 (blue) and L5 (red). Walk over the matching `⚿` to unlock.
- Armor caps at 3.

**Map + HUD**
- Minimap auto-scales to ≤ 1/3 vw on narrow terminals.
- HUD top-left strip shows level / kills / active weapon / ammo / `+pack` / held keys / difficulty tag.
- Death + victory boxes auto-size 22–36 cols and drop best-scores on short rows.
- Pos / angle / fps moved into F3 debug overlay. Pause menu lists every key binding.
- New `H` info menu — overlay shows run stats (level / kills / streak / time / difficulty), player status (lives / armor / keys / active powerups), a per-weapon table with damage / mag / reserve and the active-weapon marker `>`, and the full controls reference. Opening H freezes the game so you can read it; closing H resumes. The PAUSED panel itself is now minimal (title + credits + "H for info menu" hint) — every control binding lives in the H panel.
- `pause-pad` switched to `mb_strlen` so multi-byte glyphs (`← →`, `· `) no longer over-count and shrink the menu's trailing pad — the broken right border on the `← →    turn` row is fixed.

**CLI**
- `--difficulty=easy|normal|hard|nightmare` (`-d`) scales chase speed, enemy HP, enemy count. Default `normal`.
- `--god` (`-g`) dev mode + `make play-dev` shortcut: contact damage suppressed end-to-end so the player can walk every room / test every weapon without dying. HUD paints a yellow `GOD` badge after the hearts strip.

**Render**
- HUD lives strip now caps the filled-heart count at `:max-lives` so the row stays one line even when `:lives` is inflated (dev god mode). Engine still tracks the real value for take-damage / heart-pickup math.

### Fixed

- One-shot keys (`1` / `2` / `3` weapon switch, `r` reload, `p`, `n`, `m`, `e`, space) now fire under kitty CSI-u protocol too — `key-states` matches both plain ASCII bytes and `\\e[<code>u` / `\\e[<code>;...u` variants so Ghostty / WezTerm / kitty users can actually swap weapons.
- Weapon-slot keys no longer revert on release under kitty CSI-u. The release event `\e[<code>;<mods>:3u` embeds the digits `1` and `3` as mods/event, which the old substring check mis-read as a fresh press of `1` or `3`. `key-pressed?` now strips CSI escapes before the plain-byte test and matches only press events (`\e[<code>u`, `\e[<code>;<mods>(:1)?u`), so a held `2` switches to shotgun once and stays put.

### Changed

- Loot drop chances tuned DOWN after v0.3 playtest: per-kill drop ~25% (was 50%), berserk spawn ~12% (was 25%), invuln ~8% (was 16%), backpack ~20% (was 30%). Floor no longer fills with pickups.
- Weapons must be found on the map. Fresh runs only own the pistol. Shotgun pickup (`╪`) seeds on L2 and the chaingun (`≣`) on L3 — pickup auto-switches to the new weapon DOOM-style. `1`/`2`/`3` only switches to weapons in `:owned-weapons` so pressing 2 before finding the shotgun does nothing. Owned weapons persist across level cuts.
- 3D loot glyphs differentiated by **shape** (not just colour) so the pickup type reads at a glance across the room: heart `♥`, armor `◆`, ammo `◉` (was square `▣`), berserk `Ω`, invuln `★`, backpack `⊞`, shotgun `╪`, chaingun `≣`, keycard `⚿` (was square `⌷`).
- Locked-door cues. L4 (blue) / L5 (red) intro splash now stamps a 2nd line — `FIND THE BLUE KEY` / `FIND THE RED KEY` — under the level name so the lock mechanic is discoverable. Bumping the locked exit without the matching keycard pulses `⚿ NEED BLUE KEY ⚿` (or red) over the upper third of the 3D view for 1.5s; render-only, no gameplay change.
- Compass top-centre now doubles as a quest-target hint. The cardinal letter pointing at the player's next goal tints:
  - **orange** (door colour) → exit door
  - **blue / red** (lock colour) → keycard, when the level is locked and the matching card is still on the floor
  Tint flips from key → door the instant the player picks up the card, so the compass alone is enough to navigate without the 2D map. Yellow facing-letter still shown; quest tint wins on overlap. Explained in the start menu (`COMPASS HINT` section, full-height layout) and the H info menu (`COMPASS HINT` section).
- `ESC` closes the H info menu and the PAUSE panel. No-op when nothing is open (won't pause the game by accident). `key-states` detects bare ESC by stripping CSI / SS3 sequences first so arrow keys, kitty CSI-u events, and F-keys never register as ESC presses.
- L4 enemy count trimmed 9 → 7 → 5, L5 trimmed 12 → 9 → 7. Late-game toughness now comes mostly from per-enemy HP (4 / 5) and chase speed, not crowd density — leaves room to explore for the keycard without a meat-grinder. Ammo-box budget scales with `enemies × HP` so it auto-rebalances down.
- Kill-loot ammo drops now exclude the pistol when other weapons are owned. Pistol has a guaranteed refill path via level-spawned ammo boxes, so kill-loot biases toward the scarce shotgun + chaingun the player had to hunt down. Pistol-only loadouts (fresh L1 runs) still fall back to pistol ammo.
- Cross-level state now carries the **active weapon slot** + every weapon's **mag / reserve** across the door — stepping into L2 with a half-empty shotgun no longer resets the mag. User-preference toggles (minimap, sound) also follow the player through the door. Retry / restart still resets to fresh defaults (pistol, full minimap + sound).
- Each weapon now has its own silhouette: pistol slim single-barrel, shotgun wide twin-barrel with broad stock, chaingun multi-barrel cluster on a heavy housing.

## [0.2.0] - 2026-05-22

### Added

- F3 toggles a per-frame perf overlay (frame-ms, cast-ms, render-ms, bytes emitted, avg RLE run-length, PHP memory). Off by default and fully gated, so the off path pays zero overhead. The canonical way to validate future cast/render optimisations. Closes #9.
- 10-round magazine + R-to-reload. Empty mags drop the trigger silently; HUD shows `ammo N/10` (amber under 3, red on empty). Phase 1 of issue #5 — reloads are free for now; finite ammo from map pickups comes in phase 2.

### Performance

- DDA raycaster replaces the fixed-step march in `cast-ray` / `cast-ray-hit`. ~20-24% faster cast phase across all viewports (`80×24` 0.81 → 0.65 ms, `120×30` 1.26 → 0.99 ms, `180×40` 2.04 → 1.55 ms). As a side-effect `cast-frame` now also surfaces `:hxs` / `:hys` (hit-cell coords) so the renderer's brick-texture hash gets real inputs. Closes #2.

### Investigated, not shipping

- **Differential rendering** (issue #3) — evaluated, closed without merge. Bench shows ~60 % bytes saved in still-but-animating scenes and 100 % saved on pause, but a 2 % regression once the player moves or turns. Active gameplay = net loss; complexity cost not justified. Full numbers + rationale in `docs/performance.md` *Evaluated and shelved*.
- **Sprite occlusion z-buffer** (issue #4) — evaluated, closed without merge. Going from 0 to 15 overlapping enemies adds ~0.3-0.8 ms to `frame->string` total; a best-case z-buffer would shave a fraction of that already-tiny slice while introducing a paint-order/fill-order invariant. Existing `:dists` + `:edists` + back-to-front sort already cover most of the proposed savings. Numbers + rationale in `docs/performance.md` *Evaluated and shelved*.

### Changed

- "Enemy behind you" warning radius tightened from 10 to 5 world-units so the cue fires only when something is genuinely close behind. Closes #6.

### Fixed

- Pause menu credits row: right border now renders white like the other rows (was gray because the dim attribute leaked through the SGR reset). Closes #8.
- Pause now freezes every time-driven animation: door blink on the 2D map, "‹ behind ›" warning, JAMMED label, low-life heart pulse, pickup throb, enemy face/body walk cycle, and the aggro-head pulse. Render samples a pause-aware `:game-time` clock instead of wall-clock `microtime`, and terminal-side `SGR 5` blinks were replaced with code-driven swaps so the freeze is observable. Closes #7.

## [0.1.0] - 2026-05-22

### Added

- 256-color ANSI raycaster, runs in any modern terminal.
- FPS combat: pistol, jam mechanic, knockback, kill streaks.
- Enemies with AI, hit reactions, and procedural levels with doors.
- Pickups: hearts (refill life), armor.
- Horror layer: heartbeat vignette, jump-scares, behind-you warning, atmospheric haze, blood drops, eyes on doors, lights flicker, silence-before-strike.
- Minimap, HUD (pos / angle / level / kills / fps), start menu, pause menu.
- Persisted scores.
- WAD parser (DOOM `.wad` reader).
- Sound on/off toggle.

### Performance

- `cast + render` under 5 ms per frame at 120×30.
- Flat PHP arrays on hot paths; `:tag` types for OPcache JIT tracing.

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Chemaclass/phel-doom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Chemaclass/phel-doom/releases/tag/v0.1.0
