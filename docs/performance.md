# Performance

`frame->string` runs ~7ms at 80x24 up to ~17ms at 300x80 (interpreted PHP, no JIT, M-series laptop). The inner loop visits every cell per frame (cols x rows). Tricks that got it from "hundreds of ms" to here, roughly in order of impact.

## No statement-forms in hot-loop binding values (the closure tax)

The single biggest win (4-10x whole-frame). Phel compiles a `let` binding whose VALUE is a statement-form (`cond`, `and`, a `let`, a `when`) into an immediately-invoked PHP closure. The closure's `use(...)` list captures EVERY local in the enclosing scope - inside `frame->string` that is ~500 variables - and PHP copies each one into the closure on every invocation. Measured in isolation: 7 such closures per cell at 200x45 cost ~168ms/frame; the same work through a plain array register costs ~0.4ms.

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

To check for regressions: build and grep the artifact - `grep -c 'function() use(' out/phel_doom/io/render/main.php` should stay at ~21, all of them once-per-frame sites (pickup-painter chain arguments, centre-cell capture, debug snapshot), none inside the per-cell `while` loops.

## Big screens: uniform cadence + crisp walls

Cadence and render-scale are **uniform at every terminal size**. The old "big-screen perf mode" (a width/area threshold that dropped wide terminals to 30fps and a chunky 2x render-scale) has been removed:

- **Cadence**: a uniform ~60fps target. The 30fps cap was artificial - on hardware fast enough to render a wide-terminal frame inside the 16.67ms budget the player was pinned to 30fps for no reason, and on hardware too slow to make it the per-iteration sleep already floors at `min-yield-us`. Framerate now tracks render capability up to the 60fps ceiling and degrades smoothly toward render-native below it.
- **Scale**: a uniform 1 (exact 1:1 cast). Wide terminals render crisp walls instead of 2x replicated pairs. `cast-frame` still accepts a `scale` argument, so the replication path stays available, it is just always called with 1.

Wide terminals are render-bound, not cadence-bound: the cost is the per-column cast + wall-shade work, which scales with column count. The minimap still caps at 40 cols (see `layout`). Physics and input tick once per frame.

### Resize poll is throttled (issue #280)

`term-size` reads the terminal dimensions by forking + execing `stty size`. A fork + exec costs roughly 1ms plus scheduler jitter, and it ran once per loop iteration BEFORE the render-start timestamp, so its cost landed OUTSIDE the measured adaptive-sleep budget on a 5ms-target hot path. A resize is a human-timescale event, so ~5 of every 6 of those forks were pure waste. The loops now thread a `poll-frame` counter and sample `term-size` only on poll frames (`poll-size?`: frame 0, then every `resize-poll-frames` = 6 frames), reusing the last `[rows cols]` in between. That drops ~5/6 of the per-frame forks while still noticing a resize within ~6 frames, which `redraw-if-resized` and the auto-calibration already tolerate. The first frame stays eager so initial sizing is never delayed. Same throttle at the four size-polling loops (game loop, end screens, settings sub-loop, start menu). Fixed-size frames are byte-identical, so the golden `test-frame-bytes-pinned` hashes are unchanged.

```phel
(def standard-frame-us 16667)   ; ~60fps, every size
(def standard-scale     1)      ; crisp 1:1, every size
(defn target-frame-us [cols rows] standard-frame-us)
(defn render-scale    [cols rows] standard-scale)
```

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
- Dockerfile in repo root already enables OPcache; tune JIT per host.

## Direct PHP ops in the hot loop

Unspecialised Phel dispatch through the runtime. Hot loops use `php/+`, `php/<`, `php/aget` for direct PHP operations: `$a + $b`, `$a < $b`, `$arr[$k]`. No dispatch, no method call.

```phel
(php/aget shade-table idx)   ; $shade_table[$idx]
(php/+ a b)                  ; $a + $b
```

## Pre-baked shade tables

24-step grayscale computed once at load. Per-cell shade is one `php/aget`. No memoize, no allocation.

Parallel `shade-code-table` holds colour codes as strings for half-block edge composition (avoids re-parsing codes from ANSI strings).

The distance-fog LUTs (`tex-fade-table`, `build-themed-gradient(-codes)`) bake a tinted + filmic fade toward a cool haze tint (see `docs/rendering.md`, "Atmospheric fog tint"). The RGB lerp, filmic curve, and nearest-256 re-quantization all run inside the load-time bake; the hot path is unchanged (one nested `aget`). Measured render-ms delta vs the legacy `PHEL_DOOM_FLAT_FOG=1` fade-to-black is within noise at 80x24 / 120x30 / 180x40 (load-time-only change), and the built artifact adds zero `function() use(` closures to the per-cell loops in `main.php`.

## PHP-native nested array for the grid (`:pgrid`)

Phel vectors are slow for indexed reads in tight loops. `new-world` builds a PHP-array twin:

```phel
:pgrid (to-php-array (map to-php-array grid))
```

Raycaster and minimap use `:pgrid` via direct subscript. Both `:grid` and `:pgrid` update together on cell changes.

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
`map/wall?`, the per-ray `engine/cell-at` + `projection/wall-px`, `enemy/in-cone?`,
and the per-enemy / per-frame AI (`enemy-ai/*`), physics, render-math
(`fade-256`, `project-enemy-pd`, ...), map and combat helpers. The inliner splices
each body at its call sites, dropping the `getDefinition(...)->__invoke(...)` frame
dispatch. Byte-identical output (full unit suite + render golden hashes unchanged) -
`^:pure` only relocates the same body. (`engine/cell-at` still shows a few sites the
inliner skips; the rest inline.)

These run on the cast / AI / movement paths; the win is removing the per-call PHP
frame dispatch, not changing the math (the hot loops were already native `php/`
interop). It is small in absolute ms and easily lost in `/perf-bench` noise - verify
it structurally by diffing `out/` (the dispatch form is gone), not by chasing a ms
delta.

### let-body inlining (phel-lang dev-main)

Earlier the `CallInliner` rebaser whitelisted only Literal / GlobalVar / PhpVar /
LocalVar / Call / If / Vector / Set / Map return nodes - a `LetNode` was NOT on the
list, so any `defn` whose body is a `let` (or an `if`/`cond` with a `let` branch)
fell back to dispatch even with `^:pure`, ruling out the highest-frequency helpers
(`map/cell` ~600-1400 calls/frame, `map/wall?`, `enemy/in-cone?`). **phel-lang
dev-main (#2586) lifted that limit**: let-bodied pure `defn`s now inline at opt >= 2,
so phel-doom requires `phel-lang/phel-lang:dev-main`.

Caveat: an early dev-main build mis-renamed inlined variables (undefined-variable
codegen -> runtime crash, fixed in phel-lang#2622). `^:pure` on a let-bodied fn
therefore needs dev-main AT OR AFTER that fix. The crash surfaces only in the FULL
unit suite (it hit physics / AI / projectile paths), NOT the render golden hashes -
so always full-suite a `^:pure` change.

## DDA raycaster

Grid-line-to-grid-line march via Wolfenstein DDA: precompute step direction and per-axis delta, advance the smaller side-distance, check the cell. ~5-8 iterations per ray instead of ~35 fixed steps. Side bit and hit-cell coords are free (no second pass). Issue #2.

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
2. **Inlined DDA.** `cast-ray-hit` inlined into `cast-frame`. DDA returns PHP arrays, not persistent vectors.

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

The 2-colour `halfblock` cell cache is what makes the +2% possible: the earlier full-frame half-block attempt was rejected at +50% because it built the `\e[..m▀` string per cell. The remaining cost is bytes/frame (denser SGR, less RLE coalescing), an I/O cost not a CPU one - cap it with `--max-cols` on ultra-wide terminals.

## Render is per-cell bound; the auto pixel-scale

The 3D render (`frame->string`) is the loop's bottleneck: cast is ~1 ms, render is the rest and scales ~linearly with the cell count (cols x rows). Before the closure-tax fix the corridor scene ran ~51 ms at 100x28 up to ~210 ms at 200x50 on the reference machine; the same scenes now run ~7-14 ms (see the statement-position section above). Crucially, **opcache + tracing JIT measured ~0% improvement, and the compiled/built artifact was not faster than `phel run`** - PHP's JIT does not accelerate this call/array/string-heavy loop. (This corrects the older "build is ~10x faster / phel run absolutes are inflated" assumption: the per-frame generated PHP is the same either way.)

The strongest remaining lever on render cost is fewer cells. The game therefore **auto-calibrates a render pixel scale** (see `docs/game-loop.md` + `auto-pixel-scale`): measure a few full-detail frames; when the min render-ms exceeds `auto-target-frame-ms` (24 ms) AND the terminal is a big screen (cell area beyond 200x45, `big-screen?`), lock pixel scale 2 - the scene renders at half resolution and each scene cell paints a 2x2 terminal block, so the game **always fills the whole terminal** (an earlier inset-cap approach that shrank the render into a corner was replaced by this). A terminal at or below 200x45 never pixel-doubles: at that size pixel detail wins over framerate, and the cell count is small enough that the natural framerate stays acceptable. A fast machine that fits the budget never downscales. Override with `--max-cols=0` (full terminal at full detail) or `--max-cols=N` (manual inset cap).

Since the closure-tax fix (see the statement-position section above) full detail holds the 24 ms budget up to roughly 240x60 on the reference machine, so pixel-doubling now engages only on genuinely huge terminals or genuinely slow hardware - exactly its intended role. The calibration measures the real machine either way; none of the thresholds assume these numbers.

Pixel-doubling preserves the full-detail look everywhere it matters:

- **No zoom**: the cast runs at the FULL width with `scale 2` (one ray per two columns over full-width FOV tables, compacted by `compact-cast-2`), and every `proj-dist`-derived quantity (wall height, sprite projection, floor-cast numerator, billboard heights in the overlay painters) is halved via an explicit `pd` parameter - so framing, FOV and on-screen sprite sizes match full detail exactly. Only the texel size doubles.
- **Full vertical colour fidelity**: the sky / floor / wall-texture branches sample FOUR vertical sub-texels per scene cell (packed into one 32-bit int by a single branch dispatch) and compose the output row pair as two ▀ half-block cells - the same 2-sub-pixels-per-terminal-row density as full detail. Only the horizontal axis is doubled. Runs of identical ▀ cells RLE-coalesce by repeating the bare `▀` glyph (the SGR state persists), so bytes stay in check.
- **Sprites**: each scene cell spreads its 2x2 texel quad (`enemy-sprite-quad`) over the real 2x2 terminal block - full sprite sub-pixel detail at pixel scale 2.

The overlay is off by default and costs zero per-frame when off (instrumentation gated behind `:debug?` flag).

### Phel/PHP closure gotcha in the emitter

Every `buf-push` in the emitters lives in STATEMENT position. A push (or any `php/aset`) inside a let-binding VALUE compiles into an IIFE closure; PHP `use` copies arrays into closures, so the write lands on a copy and is silently lost. Binding values must stay pure reads; mutation goes in the loop body before `recur`. The same compilation rule is also why those closures are a performance cliff - see the statement-position section at the top of this doc.
