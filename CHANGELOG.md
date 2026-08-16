# Changelog

All notable changes to phel-doom.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

User-facing changes (`feat:`, `fix:`, `perf:`) belong under `## [Unreleased]` until release cut. Run `./tools/release.sh X.Y.Z` to roll the section into a new version.

## [Unreleased]

### Added

- The crosshair turns red when a shot would connect (#458). Since aiming became vertical (#243) a shot only lands when the crosshair is on the enemy's drawn sprite, so aiming a little at the floor or the sky misses - and the miss read as lag, because nothing confirmed the target before the trigger. The cue asks the real hitscan selection (the same aim angle, wall probe, range, hit radius and sprite gate the gun uses), so it can never disagree with the gun about where a shot goes. It does not track the trigger: an empty mag or a running reload keeps the target red, since the dry CLICK and the reload prompt already say that. Kill, wound and muzzle-flash colours still take priority.
- Enemies show their wind-up (#457): an enemy in the frozen moment before a swing or a fireball now carries a steady `!` above its head, in its own colour. The wind-up is 0.3-0.8s and dodging it is meant to be the skill, but in sprite mode there was nothing to read - the billboard is one baked frame and the face overlay is skipped, so a far cacodemon about to fire looked exactly like a dormant one. No pulse, and at full detail it costs one pass over enemies the frame had already projected.
- A Doom-style message line names what just happened (#456): `Picked up a heart.`, `Picked up the BLUE keycard.`, `You got the SHOTGUN!`, `A secret is revealed!`, and the weapon plus its ammo when you switch slots. Every pickup used to be the same door tink and the item vanishing, so a first-timer could not tell an armor shard from an ammo box, know the keycard was now held, or see that a pickup had auto-switched their weapon. One steady row for 2 seconds, no blink, clipped to the viewport and hidden on very short ones; the frame is byte-identical when there is nothing to say.

### Changed

- Quitting and restarting ask before they act, and the game pauses when you alt-tab away (#454). `q` sits one key from `w` and used to end a run on the spot; in game it now opens the pause menu with the cursor on Quit, so the confirmation is the second `q` (or Enter on that row). From the pause page `q` still quits and still persists settings, and the start menu and end screens are unchanged. Restart on the pause menu asks the same way: the first select arms it (`Restart?  enter again`), moving the cursor disarms it. And the terminal now reports focus (`\e[?1004h`), so losing the window pauses a live run and drops the held movement instead of leaving the player standing in front of an enemy. Inside tmux the pane needs `focus-events on`.

### Fixed

- Enemies stop respawning in plain sight (#455). A revived enemy only had to be 3 units from the player, which is a few cells of open floor and well inside the view, so a monster could pop into existence mid-room while you watched. The respawn now also requires the cell to be out of your line of sight, keeping a far-enough cell as a fallback so an open arena with nowhere to hide still brings its dead back.
- Dying no longer strips your arsenal (#453). Both death-screen retries (`r` fresh map, `R` same seed) restarted the level you died on with the pistol and backpack 0, so an L7 retry met archviles with a starting weapon and no way back up: kill loot only refills weapons you already own, and a level seeded only its own debut weapon, so L8-L10 had nothing on the floor at all. A retry now re-enters with the rack you ENTERED that level carrying - weapons, backpack stack and the gun in hand - while kills, time, lives and ammo still reset. Entry rather than death rack on purpose: weapon-pickup cells are drawn from the run PRNG before the ammo boxes, so rebuilding with a weapon the player grabbed during the fatal attempt would shift every later spawn and break the identical replay `R` promises. Levels also seed the weapons you are owed rather than only their own debut drop - most recent debut first, two at most - so `--level=N` starts with a usable rack too.

## [0.17.0] - 2026-08-16

### Added

- View + weapon bob while walking (#411, #412): opt-in **View bob** setting (0-100%, off by default) nods the scene on a distance-driven walk cycle and dips/sways the first-person gun on the same cycle. Cosmetic - never moves where a shot lands; byte-identical at rest.
- Room lighting (#418): opt-in **Room light** setting (off by default) folds a per-cell light bias into the wall shade, so levels read as dark rooms with lit pools. Bias grid derived from the map at load (lamp pools, `core/light`), looked up once per column at the ray's hit cell (+0.5-2.5% render); rebuilt like `:pgrid` on grid change / load, never saved. Off is byte-identical.
- Per-level floor theme (#417): each level's `:theme` tints its floor gradient (grey / steel / moss / clay / rust / hell) so episodes read distinct. Baked into the load-time LUT and keyed in the gradient memo, so it rebakes only on level change (zero per-frame cost). Walls + sky stay grayscale; `:base` is byte-identical to the old look.
- Screen-shake on heavy weapons (#414): the damage-only shake also kicks on firing/detonating a splash weapon, scaled by splash radius (BFG 3.0 harder than rocket 2.0; a connecting blast harder than a whiff). Hitscan weapons never shake.
- Truecolor cool fog (#419): in truecolor mode the distance fog fades toward a genuine cool haze (rgb 104/110/130) instead of the near-neutral grey the 256 palette forces. Same luminance, no blue band. 256 path unchanged; only `:truecolor` / `PHEL_DOOM_TRUECOLOR` shows it.
- Weapon-fire extralight (#413): firing briefly brightens nearby walls (muzzle-light stand-in). Rides the near-death haze scalar, never overlaps the red damage flash; not firing is byte-identical.
- `composer check-deprecations` gate (in `composer ci`): re-runs the suite from a cold compile cache with every deprecation channel on and fails on any notice. Exists because phel 0.50 infers a parameter's type from its body: a parameter compared to an int literal is emitted as `int $p` and a fractional caller is silently truncated at the signature, which PHP reports only as an "Implicit conversion from float ... loses precision" notice at an error level nothing shows by default. Same pass catches superseded interop spellings (`php/new`, `php/->`, `php/::`, `set-var`).
- Tracked benchmark harness `tests/bench/frame-bench.phel` on phel 0.50's `phel.bench`: `composer bench` reports mean + rstdev for `cast-frame` at 120/240 columns and the whole `frame->string` at 120x30 / 180x45 / 240x60 over one fixed scene; `composer bench-store` on main then `composer bench-ref` on a branch prints the delta per row and fails past +10%. Same machine, same session only (numbers do not travel; local php runs without JIT), so a workflow gate, not a CI one. Replaces the untracked `local/` one-offs earlier numbers came from.

### Changed

- Frame cap raised to ~120fps (was ~60fps): `standard-frame-us` 16667 -> 8333 (hardware renders 97-222fps uncapped). Input feel unchanged - per-frame constants are frame-rate-independent: movement/turn/pitch/sprint hold counters count down in seconds, mouselook edge-pan (`mouse-yaw-rate-max` / `mouse-pitch-rate-max`) scales by `dt`, and the resize-poll / mouse-re-arm cadences doubled (`resize-poll-frames` 6->12, `rearm-mouse-frames` 60->120). Render byte-identical. Savegames drop the `:moves` hold counters and load at rest, so old int-frame saves can't be misread as seconds of auto-walk.
- Mouse turn faster + survives the pointer leaving the window (#324, #313): `mouse-look-gain` 3.0 -> 5.0, so one swipe covers most of a turn. Edge-pan is **ungated** - it keeps turning while the pointer sits in the outer border band, so a pointer pinned at or past a window edge keeps swinging (no terminal can lock/hide the OS pointer); a resting mid-screen pointer never drifts. Ghostty joins the startup cosmetic-arrow notice. Keyboard-only play unchanged.
- Upgraded phel-lang 0.46 -> 0.50 (tests green, golden frames byte-identical). 0.48/0.49: the game already runs `withOptimizationLevel(2)` with tagged hot-loop locals (`^int` / `^float`), so it picks up the compiler lowerings (tag-typed native ops, `(** x 2)` -> `x*x`, `reduce` over a tagged vector as a native `foreach`, tail-position `foreach`/`doseq` without an IIFE closure), fixed-arity dispatch for multi-arity calls (~1.5-2x each, larger under JIT), primitive return tags and unadapted native-comparison tests; startup ~30% faster (0.47's OPcache warm child); clears PHP 8.3+ `ReflectionType` deprecations; source uses eager `mapv` / `filterv` / `vec` instead of `apply vector` over lazy chains (perf-neutral without JIT). 0.50: frame time -25% at 120x30, -18% at 180x45, -13% at 240x60 and unit suite 25.9s -> 10.7s on the same source, from its fixed-arity core, native `||` / `&&` for `or` / `and` test chains, collection literals compiling straight to their factory and a wider `php/*` return-type table. Source changes: `values` -> `vals`, `php/new` -> `(new \Foo ...)`, `:as` aliases in the render facade. Trade-off (docs/performance.md): 0.50 refuses to inline a callee whose parameters carry a type tag and its wider inference gives more of them tags, so 38 of the 54 `^:pure` helpers now dispatch instead of splicing; keeping the tags is the better half, and the numbers above are measured with it.
- Upgraded symfony/console 7.4 -> 8.1 (and symfony/var-dumper for dev): only this project's `^7.4` pin held it back, no CLI wiring changed. Verified through the built PHAR (`--version`, `play --help`, `demo --help`) and a live render run, since the suite covers game logic rather than console plumbing.

### Performance

- Production builds strip symbol metadata (phel-lang 0.49 `withStripSymbolMeta`): docstrings, source locations and arity info are compile-time only, so `phel build` drops them from the emitted PHP. Compiled game code 6.74 -> 5.18 MB (-23%), phar 3.24 -> 3.04 MB, cold start -7.2% through the phar / -10.9% through `out/main.php` (interleaved A/B, 15 rounds). Golden frame hashes identical through the built artifact. Trade-off: `phel doc` and `(meta ...)` over *built* defs return nil - the game never reads meta at runtime, and repl / `phel test` / `phel run` compile from source, so dev workflow is untouched.
- Hot string building leaves `phel.core/str`: -8.4% at 120x30, -5.6% at 180x45, -5.7% at 240x60, byte-identical. `str` is a runtime call plus one `val-to-str` per argument, and phel 0.50 lowers it to native concatenation only when every non-literal argument is already a `string` - one colour code prevents that. The weapon-sprite row builder and enemy-sprite cell index pre-baked per-code SGR tables (`palette/fg-cache` / `bg-cache` / `block-cache`) instead of formatting a code, the six seam-cell builders in `compute-wall-shades` use `php/.`, and the 2x2 quadrant glyph moved from a Phel map to a php-array. Per frame: `str` calls 874 -> 113, `weapon-row-string` -78% per call, `enemy-sprite-cell` -70%.
- Minimap overlay drops its per-cell closures: `sample-cell` -43% self time, `minimap-rows` -17% total, byte-identical. `sample-cell`, `block-has-wall?` and `block-visited?` each scan a step x step grid block per minimap cell per frame, written as a nested `loop` in a binding value or a `cond` test - a PHP closure capturing every in-scope local (the tax docs/performance.md documents for the scene emitters). Flattened to one loop over both axes.
- Cast loop hoists per-column constants + inlines the cell probe (#347): -55%/-63%/-66% on `cast-frame` at 80/120/180 columns; byte-identical.
- `cast-ray` + `los-clear?` DDA inline the cell probe + bind loop constants once (#354, #357): -49% on a 360-ray sweep, -42% on `mark-visible-cells`; byte-identical.
- Dropped the per-column closure tax in the cast loop (#345): -39% on `cast-frame`, `engine.php` 5 closures to 2; byte-identical.
- Render memo/dedup pass: `frame-gradients` also caches the sub-row sky codes + four floor-cast tables (rebuilt only on resize/pitch/px2 toggle); `emit-scene-px1` hoists `vw-1` and reads a precomputed per-column wall height; `paint-face-overlay` / `paint-enemy-hp-flashes` reuse the zone pass's `enemy-projs`. Byte-identical; wins on the resize/pitch/combat frames the fixed-viewport bench doesn't exercise.
- Pickup-paint passes skip the zero-pickup frame (#348); byte-identical.
- Quad-detail floor cells skip re-quantise on cache hits (#346): `:quad` path only, off by default; byte-identical.

### Removed

- Removed the verticality / tier system again (epic #375, second build): reverts all unreleased tier work - per-cell floor/ceiling heights `fz`/`cz` (#368/#385), step-up physics (#371), multi-span cast risers + upper spans (#369/#386), tier render + cross-height sprite occlusion (#370/#394/#395/#404/#416b), floor-height hitscan + window-gap shot blocking (#396/#388), stair-routing AI (#405), the L2 staircase showcase (#372). Back to a single flat floor (z = 0) with full-height ceilings. Pitch aim (#243) and view/weapon bob (#411/#412/#413) stay (camera effects, not verticality). Old tiered saves still load (height keys dropped on rebuild). See docs/adr/0001-remove-verticality-tier-system.md.

### Fixed

- Ctrl-C restores the terminal, on every screen. SIGINT (and SIGTERM) killed the process outright, and PHP's `finally` does not run on signal death - so the one exit a stuck game gets was the one route that bypassed teardown, handing back a raw-mode terminal with no cursor and the alternate screen still up. Both signals now set a quit flag that every interruptible loop reads at its frame checkpoint, so the run unwinds exactly like pressing `q`. Signal delivery is forced synchronous: symfony/console enables `pcntl_async_signals` in its Application constructor, which would let a signal land mid-render where writes are not retried. A PHP build without ext-pcntl behaves as before.
- The terminal is always restored: raw mode, the alternate screen, the hidden cursor and mouse capture are torn down in a `finally`, in the tech-talk demo session (`demo --phase N`) as well as normal play, so a crash mid-run no longer leaves the shell unusable (the error still propagates).
- **Truecolor** and **Quad detail** actually apply now. Both shipped on the options page, persisted to disk, and never reached the renderer: `frame-stats` projects the settings render reads and these two were missing from it, so only the `PHEL_DOOM_TRUECOLOR` / `PHEL_DOOM_QUAD` env overrides worked. Toggling either from the menu was a no-op.
- **View bob** and **Room light** now persist across launches. Both were on the options page but missing from the two hand-written key lists in the save/load code, so they silently reverted to defaults on the next start. Load and save (and their round-trip test) are driven off `page-fields`, so a newly added setting cannot be dropped again.
- A settings or high-score write that fails is reported instead of swallowed. On a read-only or full HOME every options change silently reverted on the next launch and a run's bests vanished, with nothing said. Both are recorded and surfaced once on exit, after the terminal is restored so the message is readable.
- The start menu fits short terminals: it clamps to the terminal height like every other menu box instead of painting past its bottom border below ~15 rows, and keeps its `ENTER / settings / quit` hints while doing so - the shared end-screen clamp trims from the bottom, so at 13 rows or fewer the key hints were the first thing dropped, leaving no visible way to start the game.
- Enemy counts rebalanced by room size + threat weight (HP x per-hit damage): L5 no longer stacks five boss-tier cyberdemons (now 2 + imp fodder) that out-gunned the L10 boss; sparse large halls (L4, L6, L9) populated so difficulty ramps smoothly. L1 + L10 untouched.
- L2 demon room no longer a bare box: random interior wall pillars (`:walls`) for cover + per-run variety, pocket-sealed into one connected region with a single exit on a random reachable wall (no dead-ends).
- Directional blood no longer lies about where a hit came from: `attacker-side` yields `:front` / `:back` as well as `:left` / `:right`, but the blood mask only discriminated `:left`, so a hit from dead ahead or behind drew blood on the **right** screen edge. Front/back hits show no edge drip (the hit vignette still shows the bearing).
- Quick-load rejects a corrupt save instead of loading a broken world or throwing out of the play loop: a save whose `world` payload was missing, null or the wrong shape passed the version check and grafted a grid-less world onto the live session (flashing "LOADED"); the tagged-map decoder now checks the payload at every level of recursion, so a nested `["$m", <not-an-array>]` is rejected instead of reaching `array_keys`.
- A malformed `--demo` file is rejected up front instead of being replayed as `[nil nil]` frames or crashing on the first replayed frame with the terminal already in raw mode (a non-string `keys` field). An unreadable `--demo` path fails with a message and a non-zero exit instead of silently starting a normal interactive run.
- `--record` reports a failed write and exits non-zero instead of printing "Thanks for playing." while discarding the entire recording.
- Mouselook edge-pan keeps its direction on a short axis. The signum helper took its sign from a comparison against an int literal, which phel 0.50 reads as "this parameter is an int" and emits as `int $n` - a fractional offset was truncated at the signature and a sub-cell offset came back as zero pan. It compares against float literals now. Only reachable where the pan band is under one cell wide (a very short viewport axis); the live 120x30 geometry keeps offsets far above 1.0, so ordinary play never hit it.
- Sub-pixel auto-off on macOS Terminal.app (#332): Apple Terminal draws `▀` with row seams, so startup defaults Sub-pixel off on `Apple_Terminal` until the player saves a choice; the in-game toggle and `PHEL_DOOM_SUBPIXEL=1` still force it on.

## [0.16.0] - 2026-06-27

### Added

- "Quad detail" setting (default off): packs a 2×2 quadrant Block-Elements glyph (`▌▞▖▟…`) wherever the four sub-pixels of a cell differ, adding a 2nd HORIZONTAL sample on top of the `▀` half-block's 2× vertical. Two payoffs: (1) the wall SILHOUETTE staircase — at each boundary cell the wall top/bottom is sampled at two sub-columns (bounds lerped 0.25 toward each neighbour column, kept fractional so they straddle the sub-row grid), so a receding/angled edge steps in half-cell diagonals instead of whole columns (the high-contrast wall/sky edge is the visible win — ~150 vertical-edge + ~130 diagonal glyphs/frame on a typical view); (2) the floor texture shows four texels per cell near the camera instead of two. The per-column raycast has no sub-column ray, so both lerp the basis/bounds from the neighbour columns; samples quantise to brightest-FG + darkest-BG and pick the glyph for that mask. No-horizontal-detail cells collapse to the `▀` half-block, so flat / far surfaces still RLE-coalesce and only edges/near-floor pay. Composes with Truecolor. Only with Sub-pixel on, full-detail px1. Cost when on: ~+40-47% CPU, low extra bytes (most edge cells swap `▀`→a quadrant glyph, same length). Off by default (golden hashes unchanged). Env `PHEL_DOOM_QUAD=1` / `PHEL_DOOM_NO_QUAD=1`.
- "Truecolor" setting (default off): the floor distance-fog now paints 24-bit `\e[48;2;r;g;b` cells instead of a `nearest-256` code, removing the 6×6×6-cube / 24-step-grey snap banding so the ground recedes into the haze tint smoothly. A tagged-value scheme (`>= 256` ⇒ packed RGB) lets the same cell builders mix a truecolor channel with a 256 one, and the pure-256 fast path is byte-identical (golden hashes unchanged) — so default-off render is unchanged. Costs ~+41% bytes/frame, ~+3% CPU when on (full-detail only; px2 stays 256). Needs a truecolor terminal. Env overrides `PHEL_DOOM_TRUECOLOR=1` (force on) / `PHEL_DOOM_NO_TRUECOLOR=1` (force off). Walls/sky still 256 (the seam mixer is a follow-up).
- "Sub-pixel" setting (default on, #332): macOS Terminal.app draws the `▀` half-blocks with anti-aliased row seams (iTerm2 / kitty / WezTerm / Ghostty draw them pixel-tight), so the 3D view shows horizontal seams there. Turning Sub-pixel off uses one solid colour per cell, which Terminal.app renders cleanly. Wires `PHEL_DOOM_NO_SUBPIXEL` into a persisted setting; default on so render is byte-identical (golden hashes unchanged). `docs/rendering.md` has the root cause + recommended Terminal.app settings (line spacing 1.0 also clears the seams).
- "Low detail" setting (default off): paints each wall AND floor cell as one flat colour instead of a two-sample `▀`, for ~11-26% less render time (scales with screen size) and ~31-40% fewer bytes/frame. Wall silhouettes / edges keep sub-pixel precision (the seam mixer still runs); sky and sprites untouched. Off by default (byte-identical); for large terminals / slow hardware. Dev override `PHEL_DOOM_FLAT_WALLTEX=1`.
- Living, non-repeating soundtrack: the OST no longer loops one fixed 3s clip. `music/session-riff` concatenates several ornamented `variant-riff` sections (E-minor ostinato with random 3rd/5th/octave stabs, root +3/+7/+12, over chugging root hits) into one long track, seeded off the game pid so every session sounds fresh. Baked once and looped whole (no per-relaunch gaps between sections); click-free at section joins + the loop wrap.
- Music pauses with the game: pausing (P menu, H info panel, menu Resume) SIGSTOPs the OST so it freezes and resumes exactly where it left off (`music/pause-music!` / `resume-music!`), instead of playing under the pause screen.
- Random room layouts: every level scatters random interior walls (`map/scatter-walls`), sealed-connected so no floor, pickup, keycard or exit is stranded. The exit door can land on ANY wall reachable from the spawn (interior pillar or border edge), not just the sides. The L10 boss arena keeps its hand-designed geometry (un-scattered). A test asserts every level (1-10) has interior walls + exactly one reachable exit that varies with the seed.
- Mouse look + click to shoot (issues #246, #318, #320, #288, #324, #275, #306, #295, #313): a `+` crosshair fixed at screen centre, gun firing dead-ahead; pointer motion turns yaw + pitch (`mouse-look-gain` over the raw column rate). Sensitivity slider follows `3 ^ ((pct - 50) / 50)` - 50% = 1.0x, 0% ~0.33x for fine aim, 100% 3.0x for flicks - scaling the delta turn + edge-pan. A terminal can't lock / warp / hide the OS pointer (#313), so an edge-pan fallback keeps turning past a window border (a resting pointer never spins), and `mouse-enable` sends XTSMPOINTER `\e[>3p` to hide it where supported (xterm-family); iTerm2 / Apple Terminal can't, so the arrow stays visible but cosmetic (the turn reads MOTION) and the start-menu how-to says so + lists `mouse - look/fire` (terminal via `$TERM_PROGRAM`). Left-click fires (hold for auto-fire), via xterm SGR. Mouse on/off + Sensitivity persisted; mouse off is byte-for-byte the keyboard build (golden fixture unchanged). On by default; keyboard unchanged.

### Changed

- Weapon fire volume tracks the hit distance on a miss too: a shot that hits no enemy used to play full volume; now it attenuates by the wall it hits (`cast-wall-dist`) - near wall loud, far / open level quiet - the same proximity feedback as an enemy hit. Volume only; scaled by the global SFX setting.
- Calmer 3D view: dropped the decorative blinks / strobes (every SGR `\e[5` hardware-blink is gone); informational cues held steady instead (heartbeat edge, berserk border, HUD labels, powerup banners, `JAMMED` chip, hearts strip, doors, aggro-range enemy heads). Essential single-shot feedback (hit-vignette, kill flash, dry-fire CLICK, hit-marker) + pickup glow unchanged. Event-gated, golden hashes unchanged.
- Heart pickup plays the Hero cue (#281): the most valuable pickup shared the generic loot tink (`:door`) with armor/ammo/doors; now it uses the soulsphere's `:berserk` (Hero) cue. Existing sound, render unchanged.
- Rocket launcher ships with a usable reserve (#282): the L5 flagship arrived with one rocket (`:reserve-start 0`) and auto-switched onto an empty gun in the cyberdemon arena. Now 5 in reserve (6 shots with the mag), matching the BFG, under the 30 cap.
- Shorter player-damage flash (#283): the all-white flash held ~3 frames (0.05s) and masked the gun / enemy / HUD even on armor-absorbed hits. Trimmed to ~2 frames (0.03s); the red i-frame wash + hurt-arrow still carry the hit.
- Quicker strafe for dodging (game-feel): `physics/strafe-speed` 2.4 -> 3.0 u/s. Still slower than the 4.5 forward run (a sidestep, not a teleport) but quick enough to clear a caster bolt's path during its wind-up, so dodging reads as skill.
- Kill-streak window widened 4s -> 7s (`combat/streak-window-seconds`): enemies respawn on a 3-6s band, so a 4s window reset the streak on nearly every kill (HUD stuck at 1). Sizing it above the respawn band lets a steady kill pace chain. Scoring/HUD only.

### Performance

- Compiler call inlining (issue #166): with phel-lang 0.46's let-body inliner (#2586 + the rename fix phel-lang#2622), `^:pure` now inlines hot LET-BODIED pure helpers at opt level 2 (splicing the body, dropping the per-call `getDefinition` frame dispatch). ~45 helpers tagged - per-cell `map/cell` (~600-1400 calls/frame) + `map/wall?`, per-ray `engine/cell-at` + `projection/wall-px`, `enemy/in-cone?`, and the per-enemy / per-frame AI + physics + render-math helpers - plus the existing let-free `physics/contribution` / `counter-on?`. Byte-identical (full suite + golden hashes unchanged). Requires `phel-lang/phel-lang` `^0.46` (bumped from `^0.45`). See `docs/performance.md`.
- Render hot-path globals (issue #262): pin referred frame-math globals (`tex-fade-table`, `bg-cell-cache`, `seam-darken-*`) as frame-level locals in `frame->string` and hoist `floor-flat?` / `vh-1` out of the inner loops, killing per-row / per-cell `Phel::getDefinition()` calls. Byte-identical; measured -5.9% at 180x40 (no-JIT local).
- Throttled the per-frame terminal-size poll (issue #280): `term-size` forks + execs `stty size` (~1ms) every iteration. The four size-polling loops now sample every 6th frame and reuse the last dimensions (~5/6 fewer forks); first frame eager, a resize noticed within ~6 frames. Fixed-size frames byte-identical.
- Dropped a per-column closure in `build-wall-sub-bounds`: rewrote the `mix?` flag from an `and`/`or` (which Phel compiles to a per-column IIFE closure capturing the whole `frame->string` scope) to a nested `if` ternary with zero capture - the documented closure-tax fix. Byte-identical.
- Cached the px2 weapon-sprite floor gradient (`render/floor-gradient-full-for`): it was rebuilt every frame (~0.2ms) though it has no pitch shear and `vh` only changes on resize. A single-slot `vh`-keyed memo makes it O(1). Pixel-doubled mode only; byte-identical.

### Removed

- Removed the verticality / multi-tier system (issue #325): a deliberate full flat reset for a clean-slate redesign later. Reverts all the unreleased verticality work - per-cell floor (#232) + ceiling (#235) heights, Z physics with auto-climb / fall damage / handrails (#233/#299), multi-tier stair rooms + showcase (#237/#298/#310), enemy tier AI (#301/#311), cast riser/ceiling accumulators + second riser (#322), tier render bands / palette / sprite ground-pads / cross-tier occlusion (#236/#302/#304), floor-height hitscan anchoring (#291/#297). L2-L8 are flat rooms again, each keeping its identity (name, enemy mix, chase, lock, weapon drop, size). The look up/down pitch aim (#231/#240/#243) stays (a camera shear, not verticality). Byte-for-byte identical render.
- Removed the `Reduced motion` setting: a no-op once the calm 3D view shipped as default - the toggle, the persisted `:reduced-motion` key and the `PHEL_DOOM_REDUCED_MOTION` env var are gone. Old settings files with the key load fine (unknown key ignored).

### Fixed

- Self-contained PHAR keeps working under phel-lang 0.46: 0.46 splits `phel.core` into `(load ...)` submodules (`core/meta`, `core/math`, …) that a downstream `phel build` does not emit, so the release PHAR would fatal on its first line with `Cannot locate core/meta for (load ...)` — the runtime sibling is missing and a bare PHAR has no classpath / compiler bootstrap to recover. `build/phar.sh` now runs `build/precompile-stdlib.php` to precompile the stdlib's core submodules into the `out/phel/core/*.php` siblings the PHAR ships, the same way phel's own `phel.phar` bundles them. Tracked upstream: [phel-lang#2648](https://github.com/phel-lang/phel-lang/issues/2648).
- L10 boss door is actually locked until the cyberdemon dies: the final room declared `:door-lock :boss`, but `lock-cell-for` had no `:boss` case so it fell through to a plain unlocked door — the exit was walk-through from the start and the boss could be skipped. It now seeds the `cell-door-boss` cell, which `passable?` blocks until combat stamps the synthetic `:boss` key into `:held-keys` on the killing blow. The door renders blood-red while the boss lives and flips to the ordinary orange door (3D view + minimap) once it's down, signalling it's now walk-through.
- Tests never trigger real audio: `make test` (and `make t`) now export `PHEL_DOOM_SILENT=1` like `composer test` / `docker-test` already did — the bare target was shelling out to `afplay` for every weapon/SFX event the suite fired (and the 12 sound + 1 music test that assert silence were failing for exactly that reason). `sound.phel`'s `muted?` also auto-detects the `phel test` runner in argv as a safety net, so a bare `vendor/bin/phel test` stays silent too; the game runtime (`phel run … play`) matches neither and keeps its sound.
- Exit doors placed randomly on every level: each level (1-10, incl. the L10 boss room) gets exactly one exit at a random wall reachable from the spawn, locked per `:door-lock`, so the way out is gameplay and differs every run. The hand-authored layouts (L2-L8, L10) baked a FIXED exit - and L2's `showcase-layout` shipped with NO exit, dead-ending the demon room with no door to L3. `map/place-exit` now owns the exit (layouts = geometry only); a test asserts every level has exactly one reachable seed-varying exit.
- Restart honors the Minimap setting (issue #292): the five restart paths hardcoded `show-map?` to `true` while loop entry seeded it from the persisted `:minimap`. All restarts now derive it via a shared `restart-show-map?` helper. Render byte-identical.
- Per-frame dt clamped to 100ms before the physics tick (issue #278): after a stall a delta spike let the un-swept move integrator step a full `move-speed * dt` at once, tunnelling through 1-thick walls / locked doors and draining every feel timer. Real frames (16-50ms) untouched, so live tick / FPS / golden frames byte-identical.
- F9 quick-load no longer reverts settings or writes a stale copy (issue #279): saves drop `:settings` / `:settings-cursor` and a load keeps the live settings (session-global, not run state). Previously a load adopted the snapshot and the next pause-resume persisted it.
- Pickups, projectiles, tracers + blood shear with the horizon on look up/down (issue #242): they used to stay pinned to the level-gaze horizon and float while the walls / floor / enemies pitched. Level gaze unchanged.

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

[Unreleased]: https://github.com/Chemaclass/phel-doom/compare/v0.17.0...HEAD
[0.17.0]: https://github.com/Chemaclass/phel-doom/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/Chemaclass/phel-doom/compare/v0.15.0...v0.16.0
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
