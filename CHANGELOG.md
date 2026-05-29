# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

- Mid-level save / load (#63). `F5` quick-saves the whole `:world` to `$HOME/.phel-doom/saves/slot-1.json`, `F9` loads it back, with a `SAVED` / `LOADED` HUD cue. A tagged JSON codec round-trips Phel keywords / sets / vectors / maps; `:pgrid` is rebuilt and fog re-reveals on load. Versioned: a save from an incompatible build is refused. Slots 1-9 exist in `io/savegame`.
- BFG splash weapon (#58). Slot 5, found on L7. A heavy `:plasma` shot: the beam lands on the nearest enemy or wall, then a 3-cell-radius blast damages every enemy around the impact - a multi-kill room-clearer that also bypasses the fire-resistant caco / baron / archvile / mancubus. Single-action, slow cadence, expensive cells. Distinct green plasma report (Glass).
- Secret reward passages. Every non-locked procgen level now hides up to 2 secret walls; revealing one (bump + `F`) drops a reward stash: an ammo box, an armor shard, and a rotating trophy powerup (soulsphere / berserk / invuln). Locked levels are skipped so a secret shortcut can't bypass a keycard door. Makes exploration pay off and turns the rare powerups into a reliable find.
- Hit-stop on meaty kills. Killing a tough enemy (caco / baron, ~70ms) or the boss (~160ms) briefly freezes the gameplay step so the blow lands with weight. Trash mobs (imps / demons) kill clean with no freeze, so chaingun spray stays fast.
- Ambient drone loop. A low, slow-pulsing background bed now runs under the whole gameplay session for dread. Synthesised at runtime (no shipped audio asset), looped by a crash-safe background process that self-terminates if the game dies, and gated by the N sound toggle.
- Projectile enemies. Cacodemons and barons now fire homing-less fireballs across the room instead of only meleeing: they freeze, telegraph (attack-face windup), then launch an orange bolt at your current position. Bolts travel through doorways but stop at walls, so you dodge by strafing or breaking line of fire with geometry. Impact costs one armor/life unit; i-frames gate a burst to one hit per frame.
- Wandering idle enemies. Half the freshly spawned monsters start pacing random directions; LOS flips them to chase.
- Backpack capacity expansion (#68 part 3). Stacks up to 3; reserve cap scales `base * (1 + level)`. HUD shows `+pack xN`.
- Armor shards (#68 part 2). +1 armor pickup that banks past `max-armor` up to 2x (no decay). Three per level.
- Soulsphere pickup (#68 part 1). Rare cyan sphere; pushes lives 2 over cap, decays back at 1 life / 5s.
- Switches that toggle remote cells (#62). `F` on a switch flips linked target cells (wall <-> floor). L10 uses two.

### Changed

- Enemy fireballs (cacodemon / baron) fly slower and telegraph a touch longer (#94), so they read as a dodge-able threat you can strafe out of instead of a near-hitscan hit.

### Fixed

- Weapon felt silent when a shot connected (esp. the shotgun): a hit swapped the gun report for the enemy reaction, so you only heard a quiet thud. Every trigger pull now plays the active weapon's own fire sound, hit or miss, with the kill cue layered on top. Each weapon gets a distinct report (pistol Pop, shotgun Blow, chaingun Morse, chainsaw Purr) via a data-driven `:fire-sfx` spec key.
- Enemy face / eyes glyph drew over closer sprites (#91). The face overlay was gated only by walls, not by nearer enemies, so a far enemy's eyes floated on top of one in front. Now gated by the same front-most-enemy check as the grounding shadow.
- Grid mutations (#61 secrets, doors, switches) left the raycaster's `:pgrid` stale - player walked through visually solid walls. New `state/rebuild-pgrid` resyncs after every mutation.
- SHIFT+WASD sprint silently no-op on Terminal.app / xterm / GNOME Terminal (any non-kitty terminal). Capital W/A/S/D bytes now refresh both the matching movement slot AND `:sprint`, so SHIFT+WASD sprints universally instead of being kitty-only.

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

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/Chemaclass/phel-doom/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Chemaclass/phel-doom/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Chemaclass/phel-doom/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Chemaclass/phel-doom/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Chemaclass/phel-doom/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Chemaclass/phel-doom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Chemaclass/phel-doom/releases/tag/v0.1.0
