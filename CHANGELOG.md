# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

**Weapons + combat**
- 3-slot loadout (1/2/3): pistol, shotgun (3 dmg), chaingun (spray). Per-weapon mag + reserve persist across switches. Each weapon has its own SGR palette so the bottom sprite reads as a distinct piece of kit.
- Finite ammo (closes #5): reserve + scaled box pickups + 1.2s reload animation + layered reload cues (LOW AMMO pulse, periodic press-R, dry-fire CLICK).
- Per-level enemy HP 1→5; wounded body shades darker, yellow HP digit above head 1.2s post-hit. Kill rolls a loot drop (ammo > armor > heart, ~75% nothing).
- Pistol sprite recoils up 2 rows on shoot (no more screen tilt).

**Powerups + pickups**
- Berserk sphere — 20s × 2 damage (~1 in 8 levels).
- Invulnerability sphere — 10s damage immunity (~1 in 12 levels).
- Backpack (L2+, one-shot, ~1 in 5 qualifying levels) — doubles every weapon's reserve cap for the rest of the run.
- Keycards + locked exit on L4 (blue) and L5 (red). Walk over the matching `⌷` to unlock.
- Armor caps at 3.

**Map + HUD**
- Minimap auto-scales to ≤ 1/3 vw on narrow terminals.
- HUD top-left strip shows level / kills / active weapon / ammo / `+pack` / held keys / difficulty tag.
- Death + victory boxes auto-size 22–36 cols and drop best-scores on short rows.
- Pos / angle / fps moved into F3 debug overlay. Pause menu lists every key binding.

**CLI**
- `--difficulty=easy|normal|hard|nightmare` (`-d`) scales chase speed, enemy HP, enemy count. Default `normal`.

### Fixed

- One-shot keys (`1` / `2` / `3` weapon switch, `r` reload, `p`, `n`, `m`, `e`, space) now fire under kitty CSI-u protocol too — `key-states` matches both plain ASCII bytes and `\\e[<code>u` / `\\e[<code>;...u` variants so Ghostty / WezTerm / kitty users can actually swap weapons.

### Changed

- Loot drop chances tuned DOWN after v0.3 playtest: per-kill drop ~25% (was 50%), berserk spawn ~12% (was 25%), invuln ~8% (was 16%), backpack ~20% (was 30%). Floor no longer fills with pickups.

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
