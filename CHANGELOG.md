# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./tools/release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

- Freedoom enemy sprites: monsters now render as real DOOM-style billboards (imp, demon/pinky/spectre, cacodemon, baron, cyberdemon, revenant, archvile, mancubus), baked from Freedoom (BSD) and sampled per cell with depth occlusion (transparent pixels show the wall behind, no halo). `PHEL_DOOM_NO_SPRITES=1` keeps the legacy glyph enemies. See `docs/rendering.md`.
- Freedoom weapon viewmodels: the first-person gun is now a real DOOM-style sprite (pistol, shotgun, chaingun, chainsaw, BFG, incinerator, rocket), baked from Freedoom (BSD) into a 256-colour grid and drawn as half-blocks. `PHEL_DOOM_NO_SPRITES=1` keeps the old ASCII guns. See `docs/rendering.md`.
- Freedoom weapon-fire sounds: each weapon plays its real DOOM-style report (baked Freedoom DMX, license-clean, no binary asset). See `docs/audio.md`.

### Removed

- Super shotgun (weapon slot 8) and everything unique to it: weapon spec, slot-8 key, the L8 pickup drop, its ASCII silhouette and sound. The roster is the seven classic-DOOM weapons (slots 1-7), all with Freedoom sprites and sounds.

## [0.11.0] - 2026-06-08

### Added

- Background OST: an original, license-clean procedural riff (driving E-minor ostinato) loops under the run to evoke the original DOOM, replacing the old ambient drone bed. Synthesised on the fly (no shipped asset), seamless loop, rides the Music volume slider, and toggles with N. See `docs/audio.md`.
- Landing page (`site/`): a retro-terminal static page (CRT scanlines, animated install terminal, feature grid, controls, gameplay video), auto-deployed to GitHub Pages by `.github/workflows/pages.yml` on any change under `site/`.
- Tech-talk demo (`demo --phase 1..4`): a progressive reveal - 1 bare raycaster (arena + central pillar), 2 +pistol, 3 +enemies, 4 +interior cover walls - with the full minimap on. Reuses the real engine via a pure `world->world` per-phase transform. See `docs/demo-showcase.md`.
- Level 7: a yellow-keyed locked exit + yellow keycard pickup - the third keycard colour (blue/yellow/red).

### Changed

- Weapon fire report is distance-attenuated: full volume point-blank, down to a ~0.1 floor when far, full on a clean miss. Scaled by your SFX setting.

### Fixed

- SFX volume setting is now respected: the audio probe no longer resets the SFX scalar to full on the first sound, so shots no longer stay loud at low SFX %.

## [0.10.0] - 2026-06-03

### Added

- Start-menu welcome box and credits screen show the current version, sourced from a single `src/core/version.phel` constant that `tools/release.sh` bumps (also feeds `--version`), so a release updates it everywhere at once.
- Each release publishes a SHA256 checksum of the PHAR: a `checksum` asset (verify with `shasum -a 256 -c checksum`) plus the hash in the release notes.

### Changed

- Start-menu welcome box restructured: controls now in two columns, with how-to-play kept below and the compass-hint section dropped, so the box is shorter and fits more terminals.

## [0.9.0] - 2026-06-03

### Added

- Distributable single-file `phel-doom.phar` (~2 MB): bundles the game with the Phel runtime into one executable. `./tools/release.sh` builds, smoke-tests, and attaches it to each GitHub release. Run with `php phel-doom.phar`.

## [0.8.0] - 2026-06-02

### Added

- Super shotgun (#126). Slot 8, found L8: a high-burst tank-killer, `:damage 5` over a wide but very short cone with a 2-shell barrel and slow reload. Beats the shotgun's TTK on 4-5HP tanks with no BFG ammo cost; appended so keys 1-7 keep their meaning.
- Rocket launcher (#123). Slot 7, found L5: single-action mid-tier AoE (splash r2.0 / 3) between the chaingun and the BFG. Reuses the splash path; cheaper and more available than the BFG.
- Incinerator (#122). Slot 6, found L6: a fast short-range `:fire` stream, the first weapon to deal `:fire` - activating the per-enemy resist system (caco / baron / archvile / mancubus shrug it off).
- Run times show as a clock (`M:SS`, or `H:MM:SS` past an hour) on the victory/death screens, the best time, and the info-menu RUN line (#131).
- Info menu lists `F5` / `F9` quick save / load, so the feature is discoverable in-game.

### Changed

- Each weapon now has its own gun-sprite silhouette, not just a recolour: the chainsaw shows a toothed blade over an engine (no barrel), the BFG a bulky cannon with a glowing aperture, the incinerator a thin nozzle over a fat fuel tank, the rocket a straight round tube, and the super shotgun a stubby twin-bore. Previously every weapon past the chaingun reused the pistol shape.
- Berserk is melee-biased with a full heal (#127): pickup restores full health, and the rage window boosts melee (chainsaw `x6`) far more than guns (`x2`) - the DOOM "go punch everything" identity, not a flat all-weapon multiplier.
- Shotgun fires a cone graze (#125): the nearest enemy takes full damage and up to two others in the cone are grazed - a crowd weapon, not one big hit.
- Pistol pierces (#124): its round hits every enemy in the line, its edge over the higher-DPS chaingun. Overheat dropped (jamming the forced fallback weapon is anti-fun).
- `press R to RELOAD` reminder is weapon-aware (#128): arms on the remaining-mag fraction, suppressed for single-round mags (the BFG).
- Deeper wall shading: flat stone (no speckle), gamma distance falloff, stronger corner contrast.

### Fixed

- Info-menu WEAPONS table columns align: long names no longer collide with `dmg`, 2-digit damage no longer shifts the ammo column, and unowned `--/--` rows line up.
- Wall-top/ceiling seam no longer shows scattered dark dots (the edge cell now samples the gradient instead of a flat shade).
- Start-menu settings (`s`) apply and persist (music/sfx/minimap/difficulty edits were silently dropped).
- Chainsaw (slot 4) is obtainable: drops on L4 and included in `--armory` (was unreachable).
- Powerup spawn odds and placement margins match their documented values (`rng/int!` off-by-one).
- Settings cursor moves once per arrow tap (kitty release events no longer double-count as navigation).

## [0.7.0] - 2026-06-01

### Added

- Settings page (#107). Pause (`p`, or `s` on start menu) sets music/sfx volume + default minimap/difficulty; arrows or WASD; persists to `~/.phel-doom-settings.json` (`afplay`, macOS).
- Half-heart health. 10 HP = 5 hearts; per-type hit damage (melee 1, casters 2, cyber 3); armor soaks a whole hit.
- Demo record / replay (#64). `--record` / `--demo` on a seeded Park-Miller RNG.
- Quick-save / load (#63). `F5` / `F9` to versioned JSON slots; fog re-reveals.
- BFG splash weapon (#58). Slot 5: plasma beam + 3-cell AoE that ignores fire-resist.
- Secret reward passages. Reveal a secret wall (`F`) for ammo + shard + a powerup.
- Hit-stop on meaty kills (~70ms, boss ~160ms); trash mobs stay fast.
- Ambient drone loop. Synthesised crash-safe bed, N-gated.
- Projectile casters. Cacodemons + barons fire dodgeable, telegraphed fireballs.
- Wandering idle enemies pace until LOS flips them to chase.
- Backpack stacking (#68). Up to 3; reserve cap scales with level.
- Armor shards (#68). Bank +1 past max to 2x.
- Soulsphere (#68). Over-caps lives, decays back.
- Remote switches (#62). `F` flips linked wall/floor cells.

### Changed

- Bump `phel-lang/phel-lang` to `v0.41.0` (first pinned stable; was `dev-main`).
- Caster tuning (#94). Slower, longer-telegraphed fireballs on a shorter cooldown; casters slower than melee.
- Progressive difficulty. Chase speed climbs L1-L9, eases at L10; archvile caster (L8); L6 / L7 gain casters.
- Per-level monster variety. L2-L5 mix melee into the headline type; L1 stays pure imps.
- Start menu explicit keys: ENTER starts, `s` settings, `q` quits.

### Fixed

- Settings nav was dead on non-CSI arrows (SS3 / kitty under tmux); now counts every encoding + WASD fallback, in-game turning handles SS3 too.
- Mixed-level enemies spawned at 1 HP; now use catalog HP (`default-lives-for`).
- `R` (restart same map) reproduces geometry + spawns via `core/rng`.
- Weapon report went silent on a connecting hit; every shot now plays its fire sound + kill cue.
- Enemy face drew over closer sprites (#91); now gated by the front-most check.
- Stale `:pgrid` after grid mutations (#61) let you walk through walls; `rebuild-pgrid` resyncs.
- SHIFT+WASD sprint was a no-op on non-kitty terminals; capital WASD now arms `:sprint`.

## [0.6.0] - 2026-05-27

### Added

- Automap fog-of-war (#67). Minimap cells stay hidden until the player has line-of-sight on them. New `--full-map` / `-f` CLI flag reveals everything for level editors.
- Secret walls (#61). Hand-authored hidden passages (`S` in `:layout`). Walk up, press `F` to reveal. World tracks `:secrets-total` / `:secrets-found`; F3 HUD shows progress. L10 ships with 2 secrets in the central pillar.
- Chainsaw (#59). Slot-4 melee weapon: no ammo, 1.5-cell range, half-speed while swinging. Stacks with berserk for a 2-damage-per-tick burst.
- Berserk viewport tint + dedicated pickup sfx (#57). Pulsing red border while the rage window is active (distinct from the i-frame red bar). Hero.aiff replaces the generic door tink on pickup.
- Per-enemy damage resistances (#60). Weapons carry `:damage-type`; enemies carry optional `:resists`. Caco / baron / archvile / mancubus resist `:fire` so future plasma / BFG shots bounce off them.
- Nightmare difficulty modifier (#65). `--difficulty=nightmare` stamps `:nightmare?` on every spawned enemy: 1-2s respawn instead of 3-6s, `:max-concurrent` cap bypassed.
- 4-way damage-direction HUD cue (#66). `attacker-side` returns `:front` / `:back` / `:left` / `:right`; render paints the matching screen edge so a rear hit is visually distinct from a flank.

### Changed

- Bumped `phel-lang/phel-lang` to `dev-main` (post phel-lang#2148 + #2181). `apply-translation` in `core/physics.phel` swaps `php/* php/- php/+` for native arith; same compiled PHP, cleaner source.

### Performance

- `cast-frame` mean ~60% faster across 80 / 120 / 180 widths via prebaked FOV trig tables + inlined DDA + `php/array` returns (was: persistent vector per ray).
- `cast-frame` short-circuits to a cached result on paused frames (~99% drop on paused-render path). Active gameplay unchanged.

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

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/Chemaclass/phel-doom/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/Chemaclass/phel-doom/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/Chemaclass/phel-doom/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Chemaclass/phel-doom/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Chemaclass/phel-doom/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Chemaclass/phel-doom/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Chemaclass/phel-doom/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Chemaclass/phel-doom/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Chemaclass/phel-doom/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Chemaclass/phel-doom/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Chemaclass/phel-doom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Chemaclass/phel-doom/releases/tag/v0.1.0
