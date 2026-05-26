# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Performance

- `cast-frame` mean ~60% faster across 80 / 120 / 180 widths (2000-iter bench on `default-grid` at player spawn):
  - Per-column FOV `atan(offset)` + `cos(offset)` prebaked into width-keyed PHP-array tables and memoized; two trig calls per ray drop out of the hot loop.
  - `cast-ray-hit` inlined into `cast-frame`'s DDA loop. Return type switched from Phel persistent vector to `php/array` so the hot path no longer allocates a vector per ray.
- `cast-frame` short-circuits to a cached previous result on paused frames (single-slot atom keyed by player x / y / angle / width / scale). Pause + help-menu overlays now pay ~3 µs per frame for the cast instead of ~500 µs at 180×40, a ~99% drop on the paused render path. Active gameplay is unchanged.

## [0.5.0] - 2026-05-25

### Added

- Enemy AI state machine: `:dormant :wander :aware :hunting :pain :attacking`. Spawns start dormant (sneak past unseen). Wake on LOS / noise / hit. Lose contact: walk to last-known position, give up if not re-acquired. Attack telegraphs with per-type windup + cooldown. Pain stagger rolls against per-type chance (imp 0.35, cyber 0.05).
- Sound-wake. Trigger pulls flood-fill 3 cells through floor. Doors + walls block.
- Responsive help panel (`H` / `ESC`). Adapts width + drops optional sections on small terminals.
- Docker support: root `Dockerfile` (PHP 8.5 CLI alpine + Composer + deps) and `make docker-build` / `docker-play` / `docker-test` / `docker-shell` / `docker-clean` targets. No host PHP required.

### Performance

- Bumped `phel-lang` to dev-main (0.40: call-site caching, arithmetic specialisation, hash-memo).
- Type-hint pass on hot numeric fns.
- Big-screen perf mode (auto at `cols >= 200` or `cols * rows > 12000`): 40-col minimap cap, 30fps cadence, 2x horizontal render-scale.

### Changed

- 2D minimap OFF by default. `M` toggles.
- `ESC` aliased to `H`.
- Cyberdemon chase 0.55x level speed.
- Removed `make play-dev` / `play-armory` / `play-boss` / `play-level` shortcuts. `--god` / `--armory` / `--level=N` still valid on `play`.
- Source layout flattened: `src/modules/{core,glue,io}/` to `src/{core,glue,io}/`. Namespaces drop the `modules` segment. Tests mirror the change.
- Removed obsolete `build/Dockerfile` + `docker-compose.yml` (superseded by the new root Dockerfile + make targets).

### Fixed

- `ESC` works under kitty CSI-u terminals (kitty / WezTerm / Ghostty / iTerm2).
- Gray borders on help panel + start menu rows that used dim SGR (sticky `\e[2m` not cleared).
- `:hit` sfx attenuates with attacker distance.

## [0.4.1] - 2026-05-25

### Added

- L10 boss door visible in 3D + minimap (red/yellow palette).
- Cyberdemon sprite 2× scale + carved silhouette (helmet, arms, 2 legs) instead of a giant rectangle.

### Changed

- Armor stack cap raised 3 → 5 (matches life cap; more breathing room on late levels).

### Fixed

- L10 enemies stop respawning once the boss dies.
- L10 central pillar now has 2 openings (north + south) so enemies can't spawn-lock inside the box.

## [0.4.0] - 2026-05-24

### Added

- 5 new levels (L6-L10). L6-L9 mix monster types per room; L10 hand-authored boss arena.
- L10 boss arena: cyberdemon HP 50, 2 imps capped at 1 alive (`:max-concurrent`).
- L10 boss door is boss-locked — kill the cyberdemon to unlock the exit + win.
- Shot knockback: enemies shoved ~1 cell back per non-killing hit (wall-clamped).
- `--armory` (`-a`): own every weapon + infinite ammo. Pairs with `--god`.
- `--level=N` (`-l`): start run at level N. Pairs with `--god` for boss testing.
- 5 new enemy stubs in catalog: `:spectre :revenant :archvile :mancubus :pinky`.

### Changed

- Phel/Clojure idiom pass across `src/` (behaviour-preserving). Hot paths untouched.
- Enemy catalog extracted to `core/enemies.phel`. Levels now slim one-line entries.
- `:enemies` accepts int OR mixed-spec vector `[{:type :imp :count 4 :lives 1} ...]`.
- Level entry can opt in to hand-authored `:layout` (ASCII grid) — bypasses procgen.
- World drops per-level enemy visual fields; render reads catalog via per-enemy `:type`.

## [0.3.0] - 2026-05-24

### Added

- Sprint: hold `SHIFT` (kitty terminals) or `x` (anywhere) for 1.6× speed; drains a 100-unit stamina pool (30/s drain, 20/s regen, 0.5s cooldown, 20-unit re-engage threshold). HUD shows a 10-cell `STA ████████░░` bar. Closes #35.
- Weapon loadout (1/2/3): pistol (1 dmg, auto-fire, overheats), shotgun (3 dmg, single-action), chaingun (1 dmg @ 0.05s cd, auto-fire). Shotgun + chaingun must be found on map; pickup auto-switches. Per-weapon mag + reserve persist across switches and across levels.
- Finite ammo: reserve + scaled box pickups + 1.2s reload + low-ammo / press-R / dry-fire CLICK cues. Closes #5.
- Per-level enemy HP scaling 1 → 5; wounded body shades darker, yellow HP digit floats above head for 1.2s post-hit.
- Powerups: berserk sphere (20s × 2 dmg), invuln sphere (10s immunity), backpack (one-shot, doubles every weapon's reserve cap for the run).
- Keycards + locked exits on L4 (blue) / L5 (red). Compass top-centre tints toward the un-picked card, flips to door (orange) once held. `⚿ NEED <COLOUR> KEY ⚿` pulse on locked-door bump.
- `H` info menu: run stats, player status, per-weapon table, full controls. Opens paused; `ESC` closes both H and the pause panel.
- `--difficulty=easy|normal|hard|nightmare` (`-d`) scales chase speed, HP, enemy count.
- `--god` (`-g`) / `make play-dev`: contact damage suppressed; yellow `GOD` badge in HUD.

### Fixed

- One-shot keys (1/2/3, R, P, N, M, E, space) now fire under kitty CSI-u protocol too.
- Kitty CSI-u release events no longer mis-fire weapon-slot switches.
- Pause menu border alignment on rows containing multi-byte glyphs (`← →`, `· `).

### Changed

- Loot drop rates tuned down post-playtest (~25% per kill, ~12% berserk, ~8% invuln, ~20% backpack).
- 3D pickups differentiated by **shape** (not colour alone): `♥` heart, `◆` armor, `◉` ammo, `Ω` berserk, `★` invuln, `⊞` backpack, `╪` shotgun, `≣` chaingun, `⚿` keycard.
- Kill-loot ammo excludes the pistol when other weapons owned (pistol refills from level boxes).
- L4 / L5 enemy counts trimmed (toughness shifts to per-enemy HP + chase speed, leaves room to hunt keys).
- Compass cardinal letter tints orange (exit door) / blue / red (keycard quest target). Yellow facing-letter still shown.
- Pause panel minimal (title + credits + `H for info` hint); every control binding moved to the H panel.
- HUD top-left strip: `L# name · kills · weapon · mag/cap [reserve] · +pack · STA bar · ⚿ · [diff]`. Pos / angle / fps moved into F3 debug overlay.

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

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Chemaclass/phel-doom/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Chemaclass/phel-doom/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Chemaclass/phel-doom/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Chemaclass/phel-doom/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Chemaclass/phel-doom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Chemaclass/phel-doom/releases/tag/v0.1.0
