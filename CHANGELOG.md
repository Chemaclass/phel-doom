# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

- Ammo loop (closes #5): finite reserve (start 30, cap 50), per-level ammo-box pickups (L1 2 → L5 8), three layered reload cues (LOW AMMO pulse, periodic press-R reminder, dry-fire CLICK), 1.2s drop/refill/raise reload animation.
- Enemies have per-level HP (1→5). Wounded body shades darker, yellow HP digit floats above the head 1.2s after each hit. Every kill rolls a loot drop (ammo > armor > heart, 50% nothing).
- HUD reshuffle: game-info strip top-left under hearts; pos/angle/fps moved into the F3 overlay; pause menu lists every key binding; minimap auto-scales to ≤ 1/3 screen on narrow terminals.
- Armor caps at 3 (was unbounded). Pickups beyond cap consume the box but don't bump — same pattern as max-lives + heart pickups.
- Death + victory end screens responsive: box width adapts to viewport (22..36 cols, 4-col margin), and short terminals (< 20 rows) drop the best-scores block + extra padding so the screen never clips off the bottom.
- Shoot animation kicks the pistol sprite up ~2 rows instead of tilting the whole 3D view. Sine curve recoil settles back to rest as `:fire-anim` decays.
- Multi-weapon roster (DOOM-classic 3-slot): **pistol** (10-mag, 0.12s cd, 1 dmg, 1.2s reload), **shotgun** (4-mag, 0.6s cd, 3 dmg, 2.0s reload), **chaingun** (30-mag, 0.05s cd, 1 dmg, 1.8s reload). Number keys 1/2/3 snap to each slot (no-op mid-reload). Per-weapon mag + reserve persist across switches; ammo-box pickups feed the active weapon's reserve at its own `:ammo-per-box` rate capped at the weapon's own `:reserve-cap`. HUD strip shows the active weapon name (`L1 imps  kills 7  pistol 7/10 [23]`).

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
