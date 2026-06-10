# Performance

`frame->string` at 180×40 runs in ~5ms. Inner loop is ~7200 iterations per frame (180 cols × 40 rows). Tricks that got it from "tens of ms" to "single-digit ms".

## Big-screen perf mode

Terminals >= 200 cols or > 12,000 cells (cols x rows) engage perf-mode: 2x render-scale (each ray casts once and replicates to 2 columns; minimap caps at 40 cols). Physics and input tick per frame.

Cadence is a **uniform ~60fps at every size**. Big screens used to drop to 30fps, but that was an artificial ceiling: on hardware fast enough to render a perf-mode frame inside the 16.67ms budget the player was pinned to 30fps for no reason, and on hardware too slow to make it the per-iteration sleep already floors at `min-yield-us`. Framerate now tracks render capability up to the 60fps ceiling and degrades smoothly toward render-native below it.

`perf-profile` is the single source of truth: it maps dimensions to `{:frame-us :scale}`, and `target-frame-us` / `render-scale` are thin reads off it.

```phel
(def perf-width-threshold 200)
(def perf-area-threshold  12000)
(defn perf-mode? [cols rows] (or (>= cols 200) (> (* cols rows) 12000)))
(defn perf-profile [cols rows]
  (if (perf-mode? cols rows)
    {:frame-us standard-frame-us :scale perf-scale}      ; 16667 µs, 2
    {:frame-us standard-frame-us :scale standard-scale})) ; 16667 µs, 1
(defn target-frame-us [cols rows] (:frame-us (perf-profile cols rows)))  ; uniform 60fps
(defn render-scale    [cols rows] (:scale    (perf-profile cols rows)))
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

Cast scales linearly with column count. Whole-frame timing (cast + render + emit) lands well under 5 ms target. Live perf is available in-game via **F3** (cast/render split, bytes emitted, PHP memory, RLE compression).

The overlay is off by default and costs zero per-frame when off (instrumentation gated behind `:debug?` flag).
