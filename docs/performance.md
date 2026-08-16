# Performance

`frame->string` runs ~7ms at 80x24 up to ~17ms at 300x80 (interpreted PHP, no JIT, M-series laptop). The inner loop visits every cell per frame (cols x rows). Tricks that got it from "hundreds of ms" to here, roughly in order of impact.

## How to measure

**Compare two refs with `tools/bench-ab.sh`, not two separate `composer bench` runs.** A single reading on a laptop drifts far more than most changes are worth: measured in one sitting, the same commit read 4.65 ms, 5.09 ms and 6.91 ms as the machine warmed up. Run the old ref, then the new one, and you can "measure" a 20% regression or a 10% win on code that did not change - both of those conclusions were drawn from exactly that method before this script existed.

```sh
tools/bench-ab.sh v0.17.0          # 3 pairs, the frame-120 row
tools/bench-ab.sh main 5 frame-    # 5 pairs, every frame row
tools/bench-ab.sh HEAD~1 5 cast    # the cast rows
```

It alternates the two refs back to back, so each pair shares a thermal state, and averages the per-pair deltas. **A consistent sign across every pair is the signal**; the script flags mixed signs as noise. The tree must be clean (it checks refs out in place and restores your branch, including on Ctrl-C).

Worked example: the twenty PRs between v0.17.0 and the release after it added eight per-frame overlays (message line, attack telegraph, hint strip, HUD glyph indirection, secret-wall texture offset, attack poses). Five interleaved pairs put the whole batch at **+0.5 to +0.7% frame time, two of three rows with mixed signs** - i.e. free, within the harness's resolution.

## The bench harness itself

`tests/bench/frame-bench.phel` is the tracked harness: `defbench` rows (phel
0.50's `phel.bench`) over one fixed scene, level 3 seed 1337, three enemies in
view, minimap on. `cast-120` / `cast-240` time `cast-frame` alone;
`frame-120x30` / `frame-180x45` / `frame-240x60` time the whole
`frame->string`. Each row reports its mean and `rstdev`; under 1% is normal on
an idle machine, and a row above a few percent is noise to re-run, not a result.

```sh
composer bench                # every row, this machine
composer bench-store          # on main: write .phel/bench-baseline.json
composer bench-ref            # on the branch: delta per row, fail past +10%
composer bench -- --filter=cast --revs=1000   # one family, more revs
```

`bench-ref` is a same-machine, same-session gate, not a CI one: absolute
durations do not travel between machines, the local php CLI runs without JIT,
and a shared runner's noise floor is wider than most real wins. Store the
baseline and compare in one sitting; a change that claims a win here should
show it in this table (and add a row when it moves something the table does
not cover). The suite loads this file too, so nothing in it runs at load: the
scene is a `delay` forced on the first warmup rev.

The numbers quoted below predate the harness and came from `local/`
one-offs of the same scene; the fixed-viewport 200-iteration means are
comparable to the `frame-*` rows.

## No statement-forms in hot-loop binding values (the closure tax)

The single biggest win (4-10x whole-frame). Phel compiles a `let` binding whose VALUE is a statement-form (`cond`, `and`, a `let`, a `when`) into an immediately-invoked PHP closure. The closure's `use(...)` list captures EVERY local in the enclosing scope - inside `frame->string`'s setup that is ~500 variables, and inside the per-cell loop of `emit-scene-px1` / `emit-scene-px2` (the scene emitters #350 lifted out of `frame->string`) it is that fn's ~70-param scene scope - and PHP copies each one into the closure on every invocation. Measured in isolation: 7 such closures per cell at 200x45 cost ~168ms/frame; the same work through a plain array register costs ~0.4ms.

The per-cell loops therefore follow a strict shape:

- Every per-cell binding value is a PURE expression (arithmetic, `aget`, fn call, `if` with expression branches - these all compile inline).
- Anything that needs branching writes its result into a tiny pre-allocated php-array register (`cell-reg` / `pack-reg`) from conds in STATEMENT position, then reads it back with one `aget`.
- `and` / `or` in a binding value also closure-compile; rewrite as nested `if` ternaries.
- Row-constant work (gradient rows, floor-cast row terms, `row * vw`) hoists into a per-row `let` outside the column loop.

Result on the 3-enemy corridor bench (ms/frame, same machine):

| Viewport | before | after | speedup |
|---|---|---|---|
| 80x24 full detail | 26.7 | 7.1 | 3.8x |
| 120x30 full detail | 44.7 | 8.9 | 5.0x |
| 200x45 full detail | 114.0 | 13.6 | 8.4x |
| 240x60 full detail | 180.4 | 17.4 | 10.4x |
| 240x60 pixel-doubled | 56.7 | 12.9 | 4.4x |
| 300x80 pixel-doubled | 87.6 | 17.3 | 5.1x |

Frame output is byte-identical before/after (verified by md5 over a 24-config matrix: angles, sizes, blood, minimap, px2, flat/no-subpixel/no-sprite toggles).

To check for regressions: build and grep the artifact - `grep -c 'function() use(' out/phel_doom/io/render/main.php` should stay unchanged vs a same-environment main build (the absolute count varies by build environment and compiler version; ~26-35 observed, 28 on phel 0.50), all of them once-per-frame or once-per-column sites (pickup-painter chain arguments, centre-cell capture, debug snapshot), none inside the per-cell `while` loops. The raycaster artifact `out/phel_doom/core/engine.php` should stay at 1 (the once-per-width FOV-table build; phel 0.50 lowers the once-per-frame pause-cache probe that used to be the second); the per-column cast loop has been closure-free since issue #345 (the DDA march + `wallx` were lifted out of binding position into the reused `hit-reg` register).

The same rule binds the MINIMAP overlay, which runs its own per-cell loop: `hud/sample-cell`, `hud/block-has-wall?` and the `block-visited?` closure inside `minimap-rows` each scan a step x step grid block per minimap cell per frame, and each used to write that scan as a nested `loop` sitting in a binding value or a `cond` test. Flattened to ONE loop over both axes they carry 0 closures; `minimap-rows` keeps 4, all once-per-frame setup. Measured: `sample-cell` self time -43%, `minimap-rows` total -17%.

## Big screens: uniform cadence + crisp walls

Cadence and render-scale are **uniform at every terminal size**:

- **Cadence**: a uniform ~120fps target, a ceiling rather than a floor. Framerate tracks render capability up to it and degrades smoothly below, where the per-iteration sleep floors at `min-yield-us`. Every per-frame input feel constant (movement/turn/pitch/sprint hold timers, mouse edge-pan rate) is stored in seconds / per-second units, not a fixed frame count, so this cap can move without changing input feel.
- **Scale**: a uniform 1 (exact 1:1 cast). Wide terminals render crisp walls instead of 2x replicated pairs. `cast-frame` still accepts a `scale` argument, so the replication path stays available, it is just always called with 1.

Wide terminals are render-bound, not cadence-bound: the cost is the per-column cast + wall-shade work, which scales with column count. The minimap still caps at 40 cols (see `layout`). Physics and input tick once per frame.

### Resize poll is throttled (issue #280)

`term-size` reads the terminal dimensions by forking + execing `stty size`. A fork + exec costs roughly 1ms plus scheduler jitter, and it ran once per loop iteration BEFORE the render-start timestamp, so its cost landed OUTSIDE the measured adaptive-sleep budget on a 5ms-target hot path. A resize is a human-timescale event, so most of those forks were pure waste. The loops now thread a `poll-frame` counter and sample `term-size` only on poll frames (`poll-size?`: frame 0, then every `resize-poll-frames` = 12 frames), reusing the last `[rows cols]` in between. That drops most of the per-frame forks while still noticing a resize within ~12 frames (~100ms at the 120fps cap), which `redraw-if-resized` and the auto-calibration tolerate. The first frame stays eager so initial sizing is never delayed. Same throttle at the four size-polling loops (game loop, end screens, settings sub-loop, start menu). Fixed-size frames are byte-identical, so the golden `test-frame-bytes-pinned` hashes are unchanged.

```phel
(def standard-frame-us 8333)    ; ~120fps, every size
(def standard-scale     1)      ; crisp 1:1, every size
(defn target-frame-us [cols rows] standard-frame-us)
(defn render-scale    [cols rows] standard-scale)
```

## View bob and the gradient memo (issue #411)

The sky/floor gradient bundle (`frame-gradients`) is a single-slot memo keyed on `(vh, pr)`, so it rebuilds only when the viewport height or the horizon offset changes. Camera pitch already moves `pr` (a look-around rebuilds it), but a static gaze holds the cache. Head bob (#411) adds a walk-cycle term to `pr`, so with **View bob on and the player moving** the key changes and the bundle rebuilds more often - the very scenario the setting targets.

Measured worst case (a synthetic bench flipping `pr` every single frame, i.e. rebuild every frame): **+0.04ms at 120x30, +0.28ms at 180x40**, against a 5-7ms frame and the 16ms ceiling. The real cost is a fraction of that: `bob-rows` is quantized to whole rows, so `pr` only changes a few times per bob cycle, not every frame. View bob defaults OFF, so the shipped look pays nothing. Given the sub-0.3ms worst case, the bob term is baked straight into `pr` (one add at the two `pitch-rows` sites) rather than decoupled from the memo key; a decouple would add hot-path complexity for no measurable win.

## Frame-gradients memo extension + wall-height/enemy-projection dedup

Three follow-ups to the memo/dedup patterns above, audited together:

**1. Extend `frame-gradients` to the sub-row sky codes + floor-cast tables.** `build-sky-codes-sub` and the four floor-cast tables (`build-floor-dperp` / `build-floor-level` / `build-floor-dperp-sub` / `build-floor-level-sub`) were rebuilt from scratch every frame even though every one of them is a pure function of the same inputs the `(vh, pr)`-keyed gradient bundle already caches, plus two more frame-constant-per-resize values: `sub-vh` (2x`svh` in pixel-doubled mode, else `svh`) and `pr-sub` (2x`pr` in pixel-doubled mode, else `pr`). `frame-gradients` now takes both as optional args (defaulting to `vh`/`pr`, so the key collapses back to the pre-existing `(vh, pr)` pair at full detail) and folds all ten arrays into the one memo slot. Rebuilds only on resize, pitch change, or a pixel-doubling toggle - the same triggers the existing bundle already rebuilt on.

**2. Per-column hoists in `emit-scene-px1`.** `(vw - 1)` (the quad-floor/quad-edge right-neighbour bound) is frame-constant, not per-cell; hoisted to the same outer `let` as the existing `vh-1` hoist. The non-mix wall-texture branch's `(max 1 (- bot top))` is column-constant but was recomputed on every ROW of a wall's height (the loop is row-outer/col-inner, so a tall wall repeats the same subtraction up to `vh` times per column); `compute-wall-shades` already computes the exact pre-clamp value as a local (`wall-h`, used to derive `bots`), so it now also stashes `(max 1 wall-h)` into a new per-column buffer (`:wall-h`) that the row loop reads with one `aget` instead of recomputing.

Evaluated and skipped: hoisting the `floordxs`/`floordys`/`shades-tex-u`/`shades-tex-px` per-column `buf-get` fetches themselves. They already compile to a single `php/aget` on an existing flat array - there is no computation to save, only a fetch, and the loop being row-outer/col-inner means there is no per-column scope to cache them in without transposing the loop (which would break row-major RLE coalescing). A per-frame array rebuild to "cache" a value that is already a raw array read would cost more than it saves.

**3. Enemy projection dedup.** `collect-enemy-projs` runs once in `frame->string`'s zone pass (`enemy-projs`) but `paint-face-overlay` and `paint-enemy-hp-flashes` each re-projected independently: `paint-face-overlay` called `collect-enemy-projs` a second time, and `paint-enemy-hp-flashes` called `project-enemy` a third time per hit-flashing enemy. Both now take the shared `enemy-projs` as a parameter instead:

- `paint-enemy-hp-flashes` is byte-identical unconditionally: it was already projecting at the FULL `vw` (matching the zone pass), so `project-enemy-pd` now rides `:lives` / `:max-lives` / `:hit-flash-secs` along on every projection (reusing locals already computed there for `:damage-ratio`, plus one more cheap default) and the fn filters the shared bundle instead of re-projecting.
- `paint-face-overlay` was called with `svw` as its width, so at full detail (`svw == vw`) it is the same call with the same pure function, and reuses `enemy-projs` directly. Pixel-doubled mode projects directly at `svw` rather than at the full `vw` and halving the column (the zone pass's approach) - a different integer-rounding path - so px2 keeps its own `svw`-scoped `collect-enemy-projs` call rather than risk a rounding drift.

Verified byte-identical beyond the pinned golden hash (whose fixture has no on-screen enemy): an md5-per-frame sweep across pitch / view-bob / pixel-doubling / resize combinations, and a glyph-mode (`PHEL_DOOM_NO_SPRITES=1`) sweep with every enemy mid-hit-flash across both render scales, hash identically before/after.

Measured (`/perf-bench`-style harness, level-1 world, 4 enemies, seed 42, 200-iter mean after 20-frame warmup, no-JIT `phel run`; this bench holds cols/rows/pitch/px2 fixed across all 200 iterations per config, so it does not exercise the memo extension's actual trigger - resize/pitch/px2 changing between frames - only the fixed-viewport cost; see the smoke checks above for that case):

| Viewport | before | after | delta |
|---|---|---|---|
| 80x24  | 3.72 ms | 3.73 ms | +0.4% (noise) |
| 120x30 | 4.57 ms | 4.55 ms | -0.5% (noise) |
| 180x40 | 6.27 ms | 6.21 ms | -1.1% (noise) |
| 240x60 | 9.10 ms | 9.18 ms | +0.9% (noise) |

All four are within the &lt;3% noise band. Kept anyway per the same reasoning as the view-bob memo above: the wins are real on the frames that actually change `(vh, pr, sub-vh, pr-sub)` or repaint a tall wall column or a hit-flashing enemy - resize, pitch/view-bob, pixel-doubling toggles, tall corridors, combat - none of which this fixed-viewport bench varies. `grep -c 'function() use(' out/phel_doom/io/render/main.php` and `out/phel_doom/core/engine.php` are unchanged vs main (the absolute count varies by build environment; compare against a same-environment main build, not a fixed number).

## PHP runtime: OPcache + JIT

Two settings matter most:

- **OPcache.** Caches parsed bytecode so startup doesn't re-parse `vendor/phel-lang/`. Free win for long-lived game loops.
- **JIT (tracing mode).** Specialises hot paths (DDA loop, RLE walk, shade lookups) to native code. Tracing outperforms function mode on tight loops.

Recommended `php.ini`:

```ini
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0

opcache.jit_buffer_size=128M
opcache.jit=tracing
```

Verify:

```bash
php -r 'var_dump(opcache_get_status()["jit"] ?? "no jit");'
```

Caveats:
- First few frames are slower while JIT compiles traces; bench at frame >= 60.
- `opcache.validate_timestamps=0` disables source-file stat checks. Set to `1` during dev.
- The repo-root Dockerfile does NOT configure OPcache or JIT; enable both per host if you are benchmarking in it.

## Direct PHP ops in the hot loop

Unspecialised Phel dispatch through the runtime. Hot loops use `php/+`, `php/<`, `php/aget` for direct PHP operations: `$a + $b`, `$a < $b`, `$arr[$k]`. No dispatch, no method call.

```phel
(php/aget shade-table idx)   ; $shade_table[$idx]
(php/+ a b)                  ; $a + $b
```

## `php/.` for hot string building, not `str` (phel 0.50)

`str` is a runtime `phel.core` call plus one `val-to-str` per argument. phel 0.50
lowers it to a native PHP `.` chain, but ONLY when every non-literal argument is
statically known to be a `string`; one int argument keeps the whole call at
runtime. Almost every hot cell builder concatenates a colour CODE, so almost
none of them qualified.

Two fixes, both byte-identical (20-config md5 matrix unchanged):

- **Pre-bake the SGR fragment, then concatenate strings.** `palette/fg-cache`,
  `bg-cache` and `block-cache` hold `\e[38;5;<n>m` / `\e[48;5;<n>m` /
  `\e[38;5;<n>m█` for all 256 codes. `paint/weapon-row-string` (the densest
  per-frame string path: one cell per weapon-sprite pixel, up to four `str`
  calls each) and `enemy-sprite/enemy-sprite-cell` now index those instead of
  formatting a code.
- **Write `php/.` where the fragments are already strings.** The six seam-cell
  builders in `compute-wall-shades` run twice per COLUMN per frame.

Also in that pass: `enemy-sprite/quadrant-glyph` became a php-array indexed by
the 2x2 mask, so the per-cell glyph lookup is one `aget` instead of a
`phel.core/get` dispatch on a Phel map.

Measured over 200 frames: `str` calls per frame 874 -> 113 (-87%), `val-to-str`
3500 -> ~570, `weapon-row-string` 84.5 -> 18.5 us/call (-78%),
`enemy-sprite-cell` 2.12 -> 0.63 us/call (-70%), `compute-wall-shades` total
874.7 -> 336.9 us/call (-61%). Whole frame: -8.4% at 120x30, -5.6% at 180x45,
-5.7% at 240x60.

The trap: do NOT swap `str` for `php/.` over a float, a bool or nil. PHP renders
those differently from Phel (`1.0` -> `"1"` not `"1.0"`, `true` -> `"1"` not
`"true"`, nil -> `""`). Ints and strings are safe, and colour codes are always
one of those.

## Pre-baked shade tables

24-step grayscale computed once at load. Per-cell shade is one `php/aget`. No memoize, no allocation.

Parallel `shade-code-table` holds colour codes as strings for half-block edge composition (avoids re-parsing codes from ANSI strings).

The distance-fog LUTs (`tex-fade-table`, `build-themed-gradient(-codes)`) bake a tinted + filmic fade toward a cool haze tint (see `docs/rendering.md`, "Atmospheric fog tint"). The RGB lerp, filmic curve, and nearest-256 re-quantization all run inside the load-time bake; the hot path is unchanged (one nested `aget`). The floor gradient bundle is additionally keyed on the per-level theme base code (#417), so a themed level rebakes its floor LUT once on level load, never per frame. Measured render-ms delta vs the legacy `PHEL_DOOM_FLAT_FOG=1` fade-to-black is within noise at 80x24 / 120x30 / 180x40 (load-time-only change), and the built artifact adds zero `function() use(` closures to the per-cell loops in `main.php`.

## PHP-native nested array for the grid (`:pgrid`)

Phel vectors are slow for indexed reads in tight loops. `new-world` builds a PHP-array twin:

```phel
:pgrid (to-php-array (map to-php-array grid))
```

Raycaster and minimap use `:pgrid` via direct subscript. Both `:grid` and `:pgrid` update together on cell changes.

`:light-grid` (#418) is a sibling PHP-array twin, derived the same way and updated by the same `rebuild-pgrid` hook. Room lighting adds ONE `php/aget` per COLUMN in `compute-wall-shades` (at the ray's hit cell), never per texel, and folds into `idx-raw` so the wall TEXTURE fog rides it for free. Measured cost: +0.5% render at 120x30, +2.5% at 180x40, ~0 in px2 - all noise-level and only paid when the opt-in `:light` setting is on. Off (default) the lookup is skipped (nil grid -> +0), byte-identical. The `if light-grid` guard is a plain ternary, so it stays inlined (no per-column closure; run the `function() use(` artifact guard after build).

## Flat distance arrays from cast-frame

`cast-frame` returns PHP arrays (`:dists`, `:hits`, `:hxs`, `:hys`, `:sides`). Renderer walks by column index; no lazy seqs, no Phel dispatch.

## Per-column shade pre-bake

Compute each column's three shade strings (normal, top-edge, bot-edge) once in an outer loop; per-row inner loop does one `aget`. Expensive math (distance, side darken, clamp) runs once per column, not per cell. 40x reduction at 180x40.

## Frame-level global capture (issue #262)

Referred globals (`tex-fade-table`, `bg-cell-cache`, `seam-darken-*`) compiled through `Phel::getDefinition()` - a static singleton probe + two array lookups - on every reference. Inside per-row and per-cell code paths this accumulates: `tex-fade-table` has 4 reads per px2 row (floor fade for sub-rows 0-3) and 2-3 reads per textured wall cell in the px1 path.

Fix: bind each hot global once in the frame-level `let` in `frame->string` under its own name. The compiler promotes inner references to a PHP local variable (`$tex_fade_table_...`) instead of re-calling `getDefinition`. Byte-identical (same value, just cached).

Also hoisted in the same pass (all frame-constant, sub-microsecond each):

- `floor-flat?` - was recomputed per row in both px1 and px2 loops; hoisted to frame-level after `floor-code-at`.
- `vh-1 = (php/- vh 1)` - used twice per column in `compute-wall-shades`; hoisted to the outer `let`.

Bench (1000-iter mean after 20-frame warmup, no-JIT local `phel run`; trust deltas, not ms):

| Viewport | before | after | delta |
|---|---|---|---|
| 80x24  | 4.02 ms | 3.85 ms | -4.2% |
| 120x30 | 6.68 ms | 6.50 ms | -2.6% |
| 180x40 | 10.24 ms | 9.63 ms | **-5.9%** |

The 180x40 result crosses the >5% real-improvement threshold. Smaller viewports land within noise - fewer total cell lookups make the `getDefinition` overhead smaller relative to the frame.

## Run-length encoding

Consecutive same-color cells coalesce: one escape, N spaces. Cuts output 5-10x on monochrome rows. In-place state machine with `prev` + `run` counters.

## Skip the minimap region

Minimap overlay rewrites top-right ~24x~22 cells via cursor positioning after the row loop. Inner loop emits a cheap placeholder for cells in that region (detected by precomputed `mini-col0` + `visible-mh`). Skips blood-paint lookup and shade computations.

## Alt screen buffer + cursor-home redraw

Alt screen + cursor home each frame (no clear). Terminal sees home-and-overwrite: no flicker, no scroll. Previous frame overwritten implicitly.

## Float type tags

PHP 8.4+ deprecates implicit float-to-int conversion. Hot-path numeric args use explicit `^float` tags to avoid deprecation warnings.

```phel
(defn- ms-since [^float t-then ^float t-now]
  (php/intval (php/* (php/- t-now t-then) 1000)))
```

## Compiler call inlining (`^:pure` + opt level 2)

`phel-config.php` builds at `withOptimizationLevel(2)`, which enables the
compiler's `CallInliner`: a call to a single-expression `defn` can be spliced
in at the call site, skipping one PHP frame and exposing the body to constant
folding. `^:pure` on a `defn-` opts it into inlining trust (the author asserts
the body is side-effect-free; see issue #166).

Annotated: the let-free `physics/contribution` (`if` body) + `physics/counter-on?`
(single `php/>`), and - since phel-lang's let-body inliner landed (see below) -
~45 hot let-bodied pure helpers carrying `^:pure`: the per-cell `map/cell` +
`map/wall?`, the per-ray `projection/wall-px`, `enemy/in-cone?`,
and the per-enemy / per-frame AI (`enemy-ai/*`), physics, render-math
(`fade-256`, `project-enemy-pd`, ...), map and combat helpers. The inliner splices
each body at its call sites, dropping the `getDefinition(...)->__invoke(...)` frame
dispatch. Byte-identical output (full unit suite + render golden hashes unchanged) -
`^:pure` only relocates the same body. (`engine/cell-at`, once the poster child
here, showed sites the inliner skipped; issue #354 removed the fn entirely and
hand-inlined its body as native `?? 1` subscripts at every former call site -
the do-cast column loop in #347, then `cast-ray` + `los-clear?`.)

These run on the cast / AI / movement paths; the win is removing the per-call PHP
frame dispatch, not changing the math (the hot loops were already native `php/`
interop). It is small in absolute ms and easily lost in `/perf-bench` noise - verify
it structurally by diffing `out/` (the dispatch form is gone), not by chasing a ms
delta.

### let-body inlining (phel-lang 0.46)

Earlier the `CallInliner` rebaser whitelisted only Literal / GlobalVar / PhpVar /
LocalVar / Call / If / Vector / Set / Map return nodes - a `LetNode` was NOT on the
list, so any `defn` whose body is a `let` (or an `if`/`cond` with a `let` branch)
fell back to dispatch even with `^:pure`, ruling out the highest-frequency helpers
(`map/cell` ~600-1400 calls/frame, `map/wall?`, `enemy/in-cone?`). **phel-lang 0.46
(#2586) lifted that limit**: let-bodied pure `defn`s inlined at opt >= 2.

Caveat (history): the first dev-main build of #2586 mis-renamed inlined variables
(undefined-variable codegen -> runtime crash, fixed in phel-lang#2622); 0.46 ships
the fix. The crash surfaced only in the FULL unit suite (it hit physics / AI /
projectile paths), NOT the render golden hashes - so always full-suite a `^:pure`
change.

### Typed callees stopped inlining (phel-lang 0.50)

phel-doom requires `phel-lang/phel-lang` `^0.50`.

0.50 (#3126) stops the inliner splicing away a callee whose parameters carry a
`:tag`, because splicing dropped the emitted parameter type and the native
arithmetic lowering that type enables. The same release widened type INFERENCE,
so a parameter now picks up a tag just from being compared to a typed literal.
The two together mean most of the annotated helpers no longer inline. Measured
by counting `"<name>")->__invoke` dispatch sites in `out/`, same source, 0.49
build vs 0.50 build:

| helper | 0.49 | 0.50 |
|---|---|---|
| `map/cell` | 0 | 6 |
| `map/wall?` | 0 | 2 |
| `projection/wall-px` | 0 | 8 |
| `frame-math/fade-256` | 0 | 4 |
| `enemy/in-cone?` | 0 | 1 |
| `frame-math/project-enemy-pd` | 2 | 9 |

38 of the 54 `^:pure` helpers now have at least one dispatch site. This is a
trade, not a regression: 0.50 is faster end to end on the same source and the
same golden frames (120x30 8.8 -> 6.6 ms/frame, 240x60 22.7 -> 19.7, unit suite
25.9s -> 10.7s), and the dispatch it costs was always "small in absolute ms",
per the section above. Keep the tags. There is no way to ask for both, and
dropping a tag to buy back one inline trades native arithmetic for a saved PHP
frame, which is the worse half.

So do NOT treat a dispatch site on a `^:pure` helper as a bug now. The structural
check that still means something is the CLOSURE count, not the dispatch count.

## DDA raycaster

Grid-line-to-grid-line march via Wolfenstein DDA: precompute step direction and per-axis delta, advance the smaller side-distance, check the cell. ~5-8 iterations per ray instead of ~35 fixed steps. Side bit and hit-cell coords are free (no second pass). Issue #2.

Rule for future march changes: any per-step cost added unconditionally shows up on EVERY frame of EVERY level; gate it or inline it for free.

## Evaluated and shelved

### Sprite occlusion z-buffer (issue #4)

Proposal: per-column min-z to early-exit enemy paint on occluded cells.

Benchmark with enemies clustered in front on `build-world 1 5`:

| Enemies | 80x24 | 120x30 | 180x40 |
|---|---|---|---|
| 0 | 12.9 ms | 23.1 ms | 44.5 ms |
| 15 | 13.7 ms | 23.9 ms | 44.8 ms |

Overlapping enemies add ~0.8 ms at 80x24, ~0.3 ms at 180x40. Existing code already does most of what z-buffer would do: `:dists` skips wall occlusions, `:edists` skips enemy occlusions, back-to-front sorting overwrites distant sprites.

Verdict: sub-millisecond win, complexity cost not justified.

### Differential rendering (issue #3)

Per-row diff against previous frame:

| Scenario | Paused | Still | Moving | Turning |
|---|---|---|---|---|
| Full repaint | 15693 B | 15693 B | 15583 B | 15616 B |
| Row-diff | 0 B | 6121 B | 15864 B | 15897 B |
| Delta | -100% | -61% | +2% | +2% |

Paused and still-player wins are real but rare. Active movement negates the win. Invalidation logic for resize, reset, alt-screen re-entry, pause overlay, minimap toggle, effects adds complexity.

Verdict: complexity cost > realistic win.

## Inlined DDA + prebaked FOV tables

After DDA, `cast-frame` was still running `atan` + `cos` per column and dispatching `cast-ray-hit` per ray. Two follow-ups:

1. **Width-keyed memo.** `offset-tables-for` caches per-width `[col -> offset]` + `[col -> cos(offset)]` arrays. Cast-frame reads two `aget`s instead of trig per column.
2. **Inlined DDA.** `cast-ray-hit` inlined into `cast-frame`. The DDA marches in statement position and writes its `[dist hit side hx hy]` result into a reused 5-slot `hit-reg` register (issue #345), so the hot loop neither dispatches a per-ray call nor allocates a persistent vector (nor the per-column closure that binding the march in value position would have cost).

Effect on `cast-frame` (2000-iter bench, `default-grid`):

| Viewport | post-DDA | post-prebake+inline | Δ |
|---|---|---|---|
| 80x24 | 0.53 ms | 0.21 ms | -61% |
| 120x30 | 0.82 ms | 0.32 ms | -61% |
| 180x40 | 1.28 ms | 0.51 ms | -60% |

## Measured numbers

`cast-frame` only, 2000-iter mean from `default-grid`:

| Viewport | step-march | DDA | prebake+inline | Δ |
|---|---|---|---|---|
| 80x24 | 0.81 ms | 0.53 ms | 0.21 ms | -74% |
| 120x30 | 1.26 ms | 0.82 ms | 0.32 ms | -75% |
| 180x40 | 2.04 ms | 1.28 ms | 0.51 ms | -75% |

Cast scales linearly with column count. Live perf is available in-game via **F3** (cast/render split, bytes emitted, PHP memory, RLE compression).


Half-block sub-pixel rendering (`frame->string`, 200-iter mean, measured BEFORE the closure-tax fix - the ratios still hold, the absolutes are ~5-10x today's):

| Viewport | half-block | flat (`NO_SUBPIXEL`) | Δ CPU | bytes Δ |
|---|---|---|---|---|
| 120x30 | 62.2 ms | 60.9 ms | +2.2% | +47% |
| 180x45 | 140.3 ms | 137.6 ms | +1.9% | +61% |
| 240x60 | 245.7 ms | 241.1 ms | +1.9% | +71% |

The 2-colour `halfblock` cell cache is what makes the +2% possible: building the `\e[..m▀` string per cell instead costs ~+50%. The remaining cost is bytes/frame (denser SGR, less RLE coalescing), an I/O cost not a CPU one - cap it with `--max-cols` on ultra-wide terminals.

## Render is per-cell bound; the auto pixel-scale

The 3D render (`frame->string`) is the loop's bottleneck: cast is ~1 ms, render is the rest and scales ~linearly with the cell count (cols x rows). Before the closure-tax fix the corridor scene ran ~51 ms at 100x28 up to ~210 ms at 200x50 on the reference machine; the same scenes now run ~7-14 ms (see the statement-position section above). Crucially, **opcache + tracing JIT measured ~0% improvement, and the compiled/built artifact was not faster than `phel run`** - PHP's JIT does not accelerate this call/array/string-heavy loop. (This corrects the older "build is ~10x faster / phel run absolutes are inflated" assumption: the per-frame generated PHP is the same either way.)

The strongest remaining lever on render cost is fewer cells. The game therefore **auto-calibrates a render pixel scale** (see `docs/game-loop.md` + `auto-pixel-scale`): measure a few full-detail frames; when the min render-ms exceeds `auto-target-frame-ms` (24 ms) AND the terminal is a big screen (cell area beyond 200x45, `big-screen?`), lock pixel scale 2 - the scene renders at half resolution and each scene cell paints a 2x2 terminal block, so the game **always fills the whole terminal**. A terminal at or below 200x45 never pixel-doubles: at that size pixel detail wins over framerate, and the cell count is small enough that the natural framerate stays acceptable. A fast machine that fits the budget never downscales. Override with `--max-cols=0` (full terminal at full detail) or `--max-cols=N` (manual inset cap).

Since the closure-tax fix (see the statement-position section above) full detail holds the 24 ms budget up to roughly 240x60 on the reference machine, so pixel-doubling now engages only on genuinely huge terminals or genuinely slow hardware - exactly its intended role. The calibration measures the real machine either way; none of the thresholds assume these numbers.

Pixel-doubling preserves the full-detail look everywhere it matters:

- **No zoom**: the cast runs at the FULL width with `scale 2` (one ray per two columns over full-width FOV tables, compacted by `compact-cast-2`), and every `proj-dist`-derived quantity (wall height, sprite projection, floor-cast numerator, billboard heights in the overlay painters) is halved via an explicit `pd` parameter - so framing, FOV and on-screen sprite sizes match full detail exactly. Only the texel size doubles.
- **Full vertical colour fidelity**: the sky / floor / wall-texture branches sample FOUR vertical sub-texels per scene cell (packed into one 32-bit int by a single branch dispatch) and compose the output row pair as two ▀ half-block cells - the same 2-sub-pixels-per-terminal-row density as full detail. Only the horizontal axis is doubled. Runs of identical ▀ cells RLE-coalesce by repeating the bare `▀` glyph (the SGR state persists), so bytes stay in check.
- **Sprites**: each scene cell spreads its 2x2 texel quad (`enemy-sprite-quad`) over the real 2x2 terminal block - full sprite sub-pixel detail at pixel scale 2.

The overlay is off by default and costs zero per-frame when off (instrumentation gated behind `:debug?` flag).

### Phel/PHP closure gotcha in the emitter

Every `buf-push` in the emitters lives in STATEMENT position. A push (or any `php/aset`) inside a let-binding VALUE compiles into an IIFE closure; PHP `use` copies arrays into closures, so the write lands on a copy and is silently lost. Binding values must stay pure reads; mutation goes in the loop body before `recur`. The same compilation rule is also why those closures are a performance cliff - see the statement-position section at the top of this doc.
