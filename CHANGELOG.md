# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./tools/release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

- Mouse look and click to shoot (issue #246): modern-FPS controls in the terminal. Move the mouse to turn and look up/down, left-click to fire (hold to spray auto-fire weapons). Uses xterm SGR mouse reporting; the pure `glue/controls` parser (`mouse-look`) turns reports into a per-frame angular delta plus a fire intent. The look comes from the delta between consecutive reports and clamps to zero at the screen edges (terminals have no pointer lock). A Mouse on/off toggle and a Sensitivity slider (default 50% = neutral 1.0x) are added to settings and persisted. Keyboard controls are unchanged; the mouse is additive and on by default.

### Changed

- Positional mouse steering so the camera never loses the pointer (issue #318): mouselook is reworked from a 1:1 pointer DELTA to POSITIONAL steering. A terminal has no pointer lock and no warp (and the OS pointer can't be hidden on iTerm2, #313), so the old delta model lost the pointer the instant a fast flick carried it off the window - the terminal stopped reporting, the camera froze, and the pointer raced on. Now the camera turn-RATE is a function of how far the pointer sits from the terminal CENTER, applied every frame: a central deadzone gives precise aim, an ease-in ramp reaches a max rate at the screen edge, and HOLDING the pointer off-center keeps turning (a full 360) because the rate is read from the cached pointer position every frame, not from motion. The pointer barely has to move, so it stays in the window; if it does leave at an edge the camera keeps turning that way until you bring it back (recoverable, not a freeze). Replaces the delta scales and the #288 edge-turn band. The Mouse on/off toggle, the Sensitivity slider (which now scales the turn-rate), and click / drag to shoot are unchanged.
- Mouse camera tracks pointer speed + wider Sensitivity range (issue #275): the camera turn already scales with how fast the pointer moves (a fast flick turns fast, a slow nudge turns slow - now pinned by tests), and the Sensitivity slider is widened from the narrow 0..2x linear band to a geometric `3 ^ ((pct - 50) / 50)` curve. 50% stays the neutral 1.0x (saved settings unchanged), but 0% now slows to ~0.33x for fine aiming instead of killing the look, and 100% speeds up to 3.0x for fast flicks. No acceleration curve (kept the response linear and testable).
- Faster mouse camera turn so it keeps up with the pointer (issue #306): the base per-cell scales are bumped ~2.5x (yaw 0.018 to 0.045 rad/cell, pitch 0.02 to 0.05, edge-turn 0.06 to 0.15 rad/frame) because at 100% Sensitivity the 3D camera still lagged the pointer. The geometric Sensitivity slider is unchanged (50% = 1.0x, 100% = 3.0x), so 100% yaw now lands at 0.135 rad/cell (2.5x the old 0.054) and the camera tracks or outpaces the pointer. The delta -> yaw proportionality stays linear; the slider still scales it.
- Native-FPS mouse feel (issue #246): the fixed screen-centre crosshair IS the aim point, so the terminal caret is re-hidden every frame, and with mouselook on an `:off` Crosshair still draws a minimal centre aim dot. The default turn speed is snappier (per-cell yaw 0.012 to 0.018). Sensitivity and pitch are unchanged; the mouse stays on by default.
- Calmer 3D view: dropped the decorative blinks and strobes from the gameplay view; the cues that carry information are held steady instead (heartbeat edge, berserk border, low-ammo / behind-you / reload HUD labels, powerup banners, the `JAMMED` chip, the hearts strip, doors and aggro-range enemy heads). Every terminal hardware-blink (SGR `\e[5`) is gone from the renderer. Essential single-shot feedback (directional hit-vignette, kill flash, dry-fire CLICK, crosshair hit-marker) and the gentle pickup glow are unchanged. Event-gated, so the golden render hashes are unchanged.
- Heart life-pickup plays the celebratory Hero cue (issue #281): the heart shared the generic loot tink (`:door`) with armor, ammo and doors, so the most valuable pickup had no distinct sound. It now uses the same `:berserk` (Hero) cue as the soulsphere, so both life-gains read alike. Reuses an existing allowlisted sound (no new asset); the render frame is unchanged.
- Rocket launcher ships with a usable reserve (issue #282): the L5 flagship weapon arrived with a single rocket (`:reserve-start 0`) and auto-switched onto an effectively empty gun in the cyberdemon arena. It now carries 5 in reserve (6 shots with the loaded mag), matching the other single-shot weapon, the BFG, and staying under the 30 reserve cap.
- Shorter player-damage flash (issue #283): the all-white impact flash on taking a hit held ~3 frames (the constant was 0.05s despite its "one frame" docstring), a full-screen white that briefly masked the gun, enemy and HUD even on armor-absorbed hits. Trimmed to ~2 frames (0.03s); the red i-frame wash and directional hurt-arrow still carry the hit, so the jolt stays but it no longer blanks the attacker.

### Performance

- Render hot-path (issue #262): pin referred frame-math globals (`tex-fade-table`, `bg-cell-cache`, `seam-darken-*`) as frame-level locals in `frame->string` and hoist `floor-flat?` / `vh-1` out of the inner loops, eliminating per-row and per-cell `Phel::getDefinition()` calls. Byte-identical output (golden hashes unchanged); measured -5.9% at 180x40 on no-JIT local PHP.
- Throttled the per-frame terminal-size poll (issue #280): `term-size` forks + execs `stty size` (~1ms + jitter) and ran once per loop iteration before the render-start timestamp, so its cost fell outside the measured adaptive-sleep budget on a 5ms hot path. A resize is a human-timescale event, so the four size-polling loops (game loop, end screens, settings sub-loop, start menu) now sample `term-size` only every 6th frame and reuse the last dimensions in between, dropping ~5/6 of the forks. The first frame stays eager and a resize is still noticed within ~6 frames; fixed-size frames are byte-identical (golden hashes unchanged).

### Removed

- Removed the entire verticality / multi-tier system (issue #325), a deliberate full flat reset so every level is flat ground again and the codebase is simple for a clean-slate redesign later. This reverts all the unreleased verticality work: per-cell floor heights (#232) and ceiling heights (#235), Z physics with auto-climb, fall damage and handrails (#233/#299), the multi-tier stair rooms and showcase (L2-L8 stairs/pit/dais/trench, #237/#298/#310), the enemy tier AI (BFS-to-mouth pathing + stair-seeking + riser Z-gate, #301/#311), the cast riser/ceiling accumulators and second riser (#322), the tier render bands + palette + sprite ground-platform pads + cross-tier occlusion (#236/#302/#304), and the floor-height hitscan anchoring (#291/#297). L2-L8 are flat rooms again, each keeping its identity (name, enemy mix, chase speed, keycard lock, weapon drop, rough size); enemies chase flat (straight at the player, sliding around walls). The look up/down pitch aim (#231/#240/#243) stays, since that is a camera shear, not verticality. The flat render is byte-for-byte identical to before (the golden render hashes are unchanged).
- Removed the `Reduced motion` setting: it became a no-op once the calm 3D view shipped as the default, so the toggle, the persisted `:reduced-motion` key and the `PHEL_DOOM_REDUCED_MOTION` env var are gone. Loading an old settings file that still carries the key is harmless (the unknown key is ignored).

### Fixed

- Mouse pointer is now actually hidden over the 3D view (issue #295): the earlier edge-turn fix re-asserted `\e[?25l`, which hides the text caret, not the OS mouse pointer - and enabling any-motion tracking makes xterm's default (XTSMPOINTER 1) show the pointer, so the arrow stayed visible. `mouse-enable` now also sends XTSMPOINTER `\e[>3p` (always hide the pointer, even leaving / entering the window) and `mouse-disable` restores it with `\e[>1p`. Hidden on terminals that implement XTSMPOINTER; no escape can warp or confine the pointer, so this hides but cannot truly lock it inside the window (the #288 edge-turn keeps you from needing to push it out). Gated on the Mouse setting; render frames are byte-identical.
- Restarting a run now honors the Minimap setting instead of forcing the overlay on (issue #292): the initial loop entry already seeded `show-map?` from the persisted `:minimap` setting, but the five restart paths (pause-menu Restart, victory fresh/same, game-over fresh/same) hardcoded `true`, so after any restart the minimap was on even with Minimap=off. The desync self-healed on the next settings visit or M toggle, but is gone now: all restarts derive `show-map?` from the loaded setting via a shared `restart-show-map?` helper. Loop wiring only; render frames are byte-identical.
- Mouselook no longer dies at the screen edge (issue #288): a terminal cannot lock or warp the pointer, so pushing the mouse into an edge used to clamp the reported coords (zero delta = camera stops) while the OS pointer kept going, left the window, and reporting went quiet. Now the outer ~8% edge band drives a continuous edge-turn (ramped by how deep into the band the pointer is x sensitivity), so a player can spin a full 360 without the pointer ever needing to leave; the central region is unchanged pure-delta look. If the pointer does leave and return, a re-entry guard re-baselines so there is no one-frame yaw jump, and the mouse-reporting escapes are re-asserted on resize / periodically so tracking recovers after a focus loss. Best-effort, not a true pointer lock. Respects the Mouse on/off + Sensitivity settings; render frames are byte-identical.
- Per-frame dt is now clamped to 100ms before the physics tick (issue #278): after a stall (GC, swap, a debugger break) one frame's delta could spike to hundreds or thousands of ms, and the un-swept move integrator translated the player a full move-speed * dt step in one go - tunnelling straight through 1-thick walls and locked doors and draining every feel timer at once. Real frames (16-50ms) are untouched, so the live tick, FPS and golden frames are byte-identical.
- F9 quick-load no longer reverts settings or persists a stale copy to disk (issue #279): saves now drop `:settings` / `:settings-cursor` and a load keeps the live settings, since they are session-global preference rather than run state. Previously a load adopted the baked-in snapshot and the next pause-resume wrote it back permanently.
- Pickups, projectiles, tracers and blood splats now shear with the horizon when looking up/down (issue #242): previously they stayed pinned to the level-gaze horizon and floated while the walls, floor and enemies pitched. A level gaze renders unchanged.

## [0.15.0] - 2026-06-16

### Added

- Navigable pause menu (issue #203): `p` opens a Resume / Settings / Restart / Quit menu (up/down move, enter or space selects). Settings opens the options sub-page (enter/space/`p` back); Restart restarts from level 1 with a fresh seed; Quit exits. Paints only when paused, so the 3D loop is untouched.
- Colorblind-safe minimap palette (issue #200): a `Colorblind` setting (`none` / `deuteran` / `protan` / `tritan`) remaps keycard and door markers - the only minimap glyphs told apart by colour alone - to a brightness-plus-hue CVD-safe triad (red-green: sky-blue/orange/white; blue-yellow: blue/red/white), a key and its door sharing one code. Overlay-only, no hot-path cost.
- Reload-ready cue: a one-shot bright-green ` READY! ` flash at the reload-reminder row when a reload finishes.
- Locked-door deny click: bumping a locked door without its key plays a muted click (at the ~1.5s `NEED <COLOUR> KEY` hint cadence) so a blocked door reads by ear.

### Changed

- Berserk window trimmed 20s to 18s: still chains two or three room clears, but ends with use-it-or-lose-it pressure.
- Critical-HP heartbeat eased 0.85s to 0.90s in the 3-4 heart tier for a clearer first thump; the last-heart 0.55s panic tier is unchanged.

### Fixed

- Settings persistence dropped 5 of 9 fields: crosshair, run timer, reduced motion, high contrast and colorblind were never written to the settings JSON and reset to defaults on every launch (only music, SFX, minimap and difficulty survived). All nine now round-trip; enum fields save as their bare keyword name and a malformed value heals to its default on load.

## [0.14.0] - 2026-06-14

### Added

- Distance fog fades toward a near-neutral light-grey haze instead of pure black, with a filmic (ACES-ish) brightness curve: distant walls and floor converge on the same grey haze (aerial perspective) and mid-tones gain contrast, so depth reads "hazy/far" not just "dark". Baked at load (`fade-256-fog` re-quantizes via `palette/nearest-256`), so the hot path is unchanged. `PHEL_DOOM_FLAT_FOG=1` restores fade-to-black.
- 2D minimap is now a framed HUD panel: box-drawing border with a cyan `MAP` title, inset one row from the top, flush to the right edge. Overlay only - the 3D loop skips the bounded panel rect, render-ms within noise. Fog-of-war, all markers, `--full-map`, and narrow-terminal auto-scale unaffected.
- Pickups render as real Freedoom item sprites instead of flat coloured quads: the LOD threshold dropped to `max(2, 2*lodr)` (height `min(16*lodr, 0.55*sprite_h)`), so they engage wherever the item is >= 2 rows tall - coloured-glow fallback kept for extreme range / `PHEL_DOOM_NO_SPRITES=1`. Baked via a separate `rgb->256-pickup` (gamma=0.50 lift only, no enemy gray-shift).
- End-screen run summary + letter rank: death/victory screens show **accuracy %**, **secrets** found/total, **damage taken** (HP lost; armor-absorbed hits don't count), a **per-weapon kill breakdown** (most-used first), and a colour-coded **rank** S/A/B/C/D (`0.7*accuracy + 0.3*secrets`, a secret-less run never penalised). The `:shots-fired`/`:shots-hit`/`:damage-taken`/`:kills-by-weapon` counters accumulate across levels; grade + accuracy live in `core/format`.
- Crosshair hit-marker: a connecting shot flashes over the reticle for ~0.12s - bold-red `✗` on a kill, bold-yellow `×` on a wound. New `:hit-fx {:kill? :ttl}` stamped in the combat step (single-target, pierce/spread, BFG-splash); fires only on confirmed contact, kept under reduced motion.
- 8-way directional damage feedback: a hit paints a red arc on the screen edge the attacker came from - a centred bar for the four cardinals, an L at the corner for the four diagonals - so you read the exact incoming bearing during i-frames. New `:hurt-dir` octant (`attacker-octant`); the 4-way `:hurt-side` stays for blood-drip columns. Kept under reduced motion.
- Reduced-motion toggle (Settings, default off; `PHEL_DOOM_REDUCED_MOTION=1` to force on): photosensitivity-safe mode that drops the lights-flicker strobe; holds the heartbeat edge, berserk border, pulsing HUD labels and powerup banners steady; suppresses the jump-scare flash; statics the door-eye. Single-shot feedback (hit-vignette, kill flash) kept. New `:reduced-motion` setting.
- High-contrast HUD toggle (Settings, default off): un-dims grey HUD elements (compass non-facing letters, empty heart pips, healthy ammo reserve) to bold white so the HUD reads on washed-out terminals. New `:high-contrast` setting.
- Two new pause/options settings: **Crosshair** style (`+` / `·` / `○` / `off`, hit-marker still flashes when off) and an always-on **Run timer** (`M:SS` in the HUD). Both persist to the settings JSON; the `:enum` cycler was generalised so each field carries its own `:choices`.
- Every level states an objective on its intro splash: **FIND THE EXIT** (orange, matching the compass exit arrow) on plain levels, plus the existing **FIND THE \<COLOUR\> KEY** (locked) and **KILL THE BOSS TO ESCAPE** (boss).

### Changed

- Enemy sprites render cleaner and fog with distance: each baked sprite carries box-filtered half/quarter mip levels picked by on-screen size (far less sparkle; near monsters byte-identical), and every texel routes through a 24-level fog LUT on the wall darkening curve, so a far monster sinks into the haze and a wounded one reads darker. Corpses, blood, fireballs and near-LOD pickups share the fade. Cost: one extra aget per texel (bench within noise).
- Doors render as real textured doors: a procedural 64x64 amber metal door (rust border + frame, six planks, mid rail) sampled through the stone-wall texture path, replacing the striped-curtain face. Panels scale with perspective, fog is floored so a door never fades to black, and the 4 rad/s pulse breathes brightness. Boss door keeps its flat pulsing red slab.

### Fixed

- Far enemy sprites now show readable humanoid silhouettes instead of blobs: three load-time passes added to the m2 mip build in `enemy_sprite.phel` - `min-opaque=1` box-filter preserves thin features (head, horns, limbs), a luminance contrast-stretch (min-range 40) restores light/dark separation, and silhouette edge darkening (frac 0.40) outlines the figure. Load-time only; per-frame cost unchanged. Near/mid LOD paths untouched.
- Enemy sprite bodies are no longer near-black silhouettes: the bake tool applies a per-channel gamma=0.50 lift (`tone-lift`) before quantization (preserving hue), plus a +3-step gray-shift (`gray-shift`) on ramp codes. Sprite fog runs at half wall strength so shading bands survive at range, while the wound-damage tint is not halved (health-state readability kept).
- Enemy sprite bodies read as warm olive-brown instead of gray: a warm-bias redirect in `rgb->256-lifted` (`tools/bake-enemy-sprites.phel`) maps tone-lifted pixels whose source is warm (r-b >= 12) to warm cube codes, raising warm coverage from ~31% to ~80% of opaque imp pixels. Neutral pixels (pure grays, the cacodemon's blue) unaffected. Sprites rebaked from the Freedoom WAD.
- Pickup sprites no longer render as pale gray slabs: `enemy_sprites_data.phel` rebaked from the WAD via `rgb->256-pickup` (gamma=0.50 lift only, no gray-shift, no warm-bias), so the armor vest, ammo box, and soulsphere show correct olive-green, brass, and blue.
- Sprites no longer show color-confetti on brown/tan art: the bake quantization now matches against the real xterm-256 cube levels (0/95/135/175/215/255) by nearest-squared-distance instead of evenly-spaced thresholds, so source browns stop rounding to spurious blue/green.
- Mid-distance sprites no longer show speckled noise columns: mip-switch thresholds tightened (native below 1.5x oversampling, half below 3x, quarter at 3x+) and sub-row sampling shifted to center-of-footprint, removing the corner bias. No render-time cost.
- Mid-distance sprites no longer merge into the dark wall behind them: the distance-fog cap dropped from 0.85 to 0.65, so a monster at max range stays at least 35% lit. The squared falloff curve is unchanged.

## [0.13.0] - 2026-06-11

### Added

- Half-block sub-pixel floor, walls, and sky: each cell emits a `▀` upper-half-block with independent top/bottom colours, doubling vertical resolution so stonework and the ground read with smaller, squarer pixels. Two colours is all a terminal cell carries, so this is the fidelity ceiling that does not throw colour away. `halfblock` memoizes each colour pair into a ready paint cell (~+2% CPU); bytes/frame rise ~50-70% on big screens - cap with `--max-cols`. `PHEL_DOOM_NO_SUBPIXEL=1` restores flat one-colour cells.
- Textured stone walls: plain walls sample the baked Freedoom flat (WALL70_2) via a per-column texture U, fogged by distance + side shading through a prebaked fade LUT (~2% render cost). Doors / boss door / blood-wash columns stay flat as nav cues. `PHEL_DOOM_FLAT_WALLS=1` restores the flat look.
- Textured floor: the ground plane is floor-cast from the same stone texture (distance-fogged, pulled darker so it reads as shadowed ground). Per-cell sample is two mul-adds + a texture fetch, no trig (~+12% render cost). Blood columns keep the red gradient; `PHEL_DOOM_FLAT_FLOOR=1` restores the flat gradient.
- Sharper enemy/pickup sprites via 2x2 quadrant sub-cells: fully-opaque interior cells reduce their 2x2 sample to two colours and pick a quadrant glyph (`▘▀▌▚▛▜▙█`); transparent/edge cells keep the half-block so silhouettes stay clean.
- Auto-calibrated pixel detail, always full screen: the game renders a few full-detail frames under the intro splash, measures the real render time, and only when the machine needs it locks a pixel-doubled mode - half-resolution scene, each cell painted as a 2x2 block, ~4x cheaper, still filling the whole terminal. Framing, FOV and sprite sizes match full detail exactly (no zoom), sprites keep 2x2 sub-pixel detail, and sky/floor/walls keep full vertical colour fidelity (four vertical sub-samples per scene cell); only the horizontal axis gets chunkier. Stable per session, recalibrates on terminal resize.
- `--max-cols=N` / `--max-rows=N` flags override the auto mode: a positive value fixes an inset render size (anchored top-left), `--max-cols=0` forces the full terminal at full detail. Unset = auto.

### Changed

- Wide terminals render crisp 1:1 walls: the big-screen "perf mode" that cast one ray per 2 columns and replicated it (chunky walls past 200 cols) is removed; every terminal size uses the exact 1:1 cast.
- Ammo-box budget scales with difficulty (hard x1.2, nightmare x1.5 on the enemy-HP baseline), so spray weapons (chaingun, incinerator) don't starve when faster enemies raise the miss rate.
- Heal/armor pickups scale with difficulty: nightmare seeds 2 hearts + 5 armor shards per level (hard 1 + 4) vs the 1 + 3 baseline. Rare powerup odds (berserk/invuln/soulsphere) stay flat.
- Kill-loot drop rate bumped from 25% to 35% (ammo 22%, armor 8%, heart 5%): the 8-weapon roster made 3-in-4 kills dropping nothing read as sparse.

### Fixed

- Diagonal wall edges: wall/floor and wall/sky junctions on textured walls used to step in whole-cell stairs (bright edge band per tread at full detail, mushy stone-on-stone seam in pixel-doubled mode). Both modes now trace the exact diagonal at sub-row precision with a graduated dark seam - near-black wall base line, darker first floor sub-row, lighter lip at the sky seam - so receding walls read like the floor texture's own perspective diagonals. Doors / boss door / blood columns keep whole-cell bands as nav cues. ~15% render cost at full detail, no measurable cost pixel-doubled.
- Pixel-doubling only engages on genuinely big screens (cell area beyond 200x45): a normal-sized terminal keeps full pixel detail even when the measured frame cost misses the smoothness budget - at that size detail beats framerate.
- Big-terminal rendering no longer shrinks into a small top-left inset: the first auto-smoothing pass capped the render area and left the rest of the terminal stale; replaced by the full-screen pixel-doubled mode above.
- Floor texture cracks no longer read as harsh black speckle: the floor samples a contrast-softened copy of the texture (texels lerped toward mid-grey, codes compressed from 232-249 to ~237-246) so cracks calm to a gentle mottle; walls keep full contrast. Precomputed at load, no extra floor cost.
- Wall/floor stone texture no longer shows colored confetti: the baked WALL70_2 flat carried colored seam columns, a corrupt top band, and saturated specks; the bake is sanitized to a pure grayscale ramp (luminance-remapped, corrupt rows + border columns repaired). Stone structure preserved.
- Crosshair reads clearly on any background: the idle reticle is a solid bold bright-white `+` (bold bright-yellow on fire, keeping the one-row recoil jump) instead of the faint/dim SGR smudge, and its backdrop now reuses the centre cell rendered by the row loop verbatim, so the `+` always sits on the true wall texture / floor / sky / sprite pixel instead of a mismatched flat shade.
- Horizontal FOV clamps at 100° on wide terminals: the ray spread widens naturally up to ~167 cols, then holds instead of bowing toward 110°+ edge fisheye; extra columns add horizontal resolution. Narrower terminals and wall scale unchanged.

### Performance

- 4-10x faster rendering at every screen size, byte-identical output. Phel compiles a `let` binding whose value is a `cond`/`and`/`let` into a PHP closure that copies all ~500 in-scope locals per invocation; the per-cell render loops paid that closure tax up to 7 times per cell. Both emitters now resolve each cell through statement-position conds writing into a tiny register array, with row-constant work hoisted out of the column loop. Measured (3-enemy corridor, interpreted PHP): 80x24 26.7 -> 7.1 ms, 120x30 44.7 -> 8.9 ms, 200x45 114.0 -> 13.6 ms (8.8 -> 74 fps), 240x60 pixel-doubled 56.7 -> 12.9 ms, 300x80 pixel-doubled 87.6 -> 17.3 ms. Every size sustains 55+ fps on the reference machine (md5-verified over a 24-config matrix); pixel-doubling stays the big-screen/slow-hardware reserve and simply engages far less often.
- Big screens are no longer capped at 30fps: the perf-mode cadence ceiling is gone; cadence is a uniform 60fps target at every size and framerate tracks render capability.
- Sky/floor gradients are memoized by viewport height: rebuilt only on resize instead of every frame, worth ~0.3-0.5ms/frame at 40-100 rows.

## [0.12.0] - 2026-06-09

### Added

- Freedoom enemy sprites: monsters render as real DOOM-style billboards (imp, demon/pinky/spectre, cacodemon, baron, cyberdemon, revenant, archvile, mancubus), half-block sub-pixels at native aspect, depth-occluded. `PHEL_DOOM_NO_SPRITES=1` keeps the glyph enemies. See `docs/rendering.md`.
- Freedoom death + fireball sprites: kills play a per-type collapse-to-corpse animation instead of a red block; enemy fireballs use the real DOOM projectile sprite. Both fall back under `PHEL_DOOM_NO_SPRITES=1`.
- Freedoom weapon viewmodels: first-person guns (pistol, shotgun, chaingun, chainsaw, BFG, incinerator, rocket) drawn as Freedoom sprites. `PHEL_DOOM_NO_SPRITES=1` keeps the ASCII guns.
- Freedoom weapon-fire sounds: each weapon plays its real DOOM-style report (baked Freedoom DMX, license-clean). See `docs/audio.md`.
- Freedoom pickup sprites with distance LOD: floating items render as real DOOM sprites up close and as a clean colour blob at distance, so far pickups read clearly. `PHEL_DOOM_NO_SPRITES=1` keeps the glyphs.
- Energy-weapon muzzle flash: BFG, incinerator, and rocket show a Freedoom muzzle burst while firing; hitscan guns stay flash-free so their recoil reads.
- Traveling BFG ball + rocket: a cosmetic Freedoom projectile flies from muzzle to impact and recedes as it travels (damage stays instant).
- Weapon recoil: every gun snaps up and settles when fired.

### Fixed

- Quitting no longer leaves a stray escape sequence (e.g. `3;1:3u`) on the shell prompt: the terminal's kitty key-release report is drained before cooked mode returns.

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

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.15.0...HEAD
[0.15.0]: https://github.com/Chemaclass/phel-doom/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/Chemaclass/phel-doom/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/Chemaclass/phel-doom/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/Chemaclass/phel-doom/compare/v0.11.0...v0.12.0
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
