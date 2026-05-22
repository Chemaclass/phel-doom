# Performance

`frame->string` at 180×40 runs in ~5ms. Inner loop is ~7200 iterations per frame (180 cols × 40 rows). Tricks that got it from "tens of ms" to "single-digit ms":

## Direct PHP ops in the hot loop

Unspecialised Phel `+`, `<`, and collection reads dispatch through the Phel
runtime. Fine for app code, heavy per-cell. Latest Phel `main` can native-emit
some typed primitive `phel.core` arithmetic and comparisons, but these hot loops
keep the raw PHP path explicit.

Renderer + raycaster use `php/+`, `php/<`, `php/aget`. Compile to `$a + $b`, `$a < $b`, `$arr[$k]` directly. No dispatch, no method call. ~5× speedup on the hot loop.

```phel
(php/aget shade-table idx)   ; compiles to:  $shade_table[$idx]
(php/+ a b)                  ; compiles to:  $a + $b
```

## Pre-baked shade tables

24-step grayscale palette computed once at load:

```phel
(def shade-table
  (let [t (php/array)]
    (loop [i 0]
      (when (php/< i 24)
        (php/aset t i (str "\e[48;5;" (php/+ 232 i) "m "))
        (recur (php/+ i 1))))
    t))
```

Per-cell shade is one `php/aget`. No memoize cache, no per-call allocation.

Parallel `shade-code-table` holds the colour code as a string (`"240"`) for composing half-block edge cells. Avoids re-parsing the BG code out of the prebaked ANSI string.

## PHP-native nested array for the grid (`:pgrid`)

Phel persistent vectors are great for pure updates but slow for indexed reads in a tight loop. `new-world` builds a PHP-array twin:

```phel
:pgrid (to-php-array (map to-php-array grid))
```

Raycaster + minimap iterate `:pgrid` via direct subscript. Both `:grid` and `:pgrid` must update together on cell changes (door opens, etc.).

## Flat distance arrays from cast-frame

```phel
{:dists <php-array> :hits <php-array> :hxs ... :hys ... :sides ...}
```

Renderer walks by column index. No lazy seqs, no Phel vector dispatch.

## Per-column shade pre-bake

Each column's three shade strings (normal, top-edge, bot-edge) computed once in an outer loop; the per-row inner loop does an `aget` against the column array. Expensive math (distance, side darken, cell hash, clamp) runs once per column, not per cell.

For 180×40 that's a 40× drop in shading work vs a naive per-cell approach.

## Run-length encoding

Consecutive cells with the same ANSI escape coalesce into one paint + N spaces:

```
\e[48;5;240m            (set BG once)
"          "            (12 spaces, terminal keeps the BG)
```

Cuts output 5-10× on same-colour rows. In-place state machine in the inner loop (`prev` + `run` counters). No separate buffer pass.

## Skip the minimap region

Minimap overlay rewrites the top-right ~24×~22 cells via absolute cursor positioning **after** the main row loop. Cells underneath don't need to paint properly. Inner loop emits a cheap `sky-gradient[row]` placeholder for cells in the minimap region (detected by precomputed `mini-col0` + `visible-mh`). Skips blood-paint lookup, four-arm cond, and both shade lookups.

## Alt screen buffer + cursor-home redraw

```phel
\e[?1049h    ; enter alt screen
\e[?25l      ; hide cursor
\e[?7l       ; disable autowrap
\e[H         ; cursor home each frame (no clear)
```

Terminal sees repeated home-and-overwrite. No flicker, no scroll, no full clear (which would flash). Previous frame's state is implicitly overwritten because we emit the same byte count each frame.

## Float type tags

PHP 8.4+ deprecates implicit float-to-int conversion when the cast loses precision. Phel's inferencer sees `(* x 1000)` and emits `int $x` in the signature. Perfect for ints, broken when callers pass `microtime(true)`.

Hot-path numeric args get explicit `^float`:

```phel
(defn- ms-since [^float t-then ^float t-now]
  (php/intval (php/* (php/- t-now t-then) 1000)))
```

Phel emits `float $t_then, float $t_now`. No implicit cast, no deprecation, no log spam.

## DDA raycaster

`cast-ray` and `cast-ray-hit` march from grid line to grid line via a Wolfenstein-style **DDA**: precompute step direction + per-axis `delta = |1/dir|`, advance whichever side-distance is smaller, check the cell. ~5-8 iterations per ray instead of the old fixed-step march's ~35, and the side bit + hit-cell coords fall out for free (so the brick-texture hash + corner shading get correct inputs without a second pass). Issue #2.

## Evaluated and shelved

### Sprite occlusion z-buffer (issue #4 — closed without merge)

The proposal: introduce a per-column min-z so the enemy paint loop can early-exit on cells already taken by a closer sprite, instead of the current back-to-front overwrite + per-cell wall-distance check.

`frame->string` mean over 1500 iterations on `build-world 1 5` with enemies clustered directly in front of the player so they overlap on screen:

| Enemies on screen | 80×24 | 120×30 | 180×40 |
|---|---|---|---|
| 0 | 12.9 ms | 23.1 ms | 44.5 ms |
| 1 | 13.1 ms | 23.4 ms | 45.1 ms |
| 3 | 13.1 ms | 23.0 ms | 44.4 ms |
| 8 | 13.3 ms | 23.3 ms | 44.5 ms |
| 15 | 13.7 ms | 23.9 ms | 44.8 ms |

(Absolute numbers are higher than the headline "<5 ms" because the bench measures the full `frame->string` on the larger level-1 map without the runtime's frame-budget sleep — relative deltas are what matters here.)

Going from no enemies to 15 overlapping enemies adds **~0.8 ms at 80×24, ~0.8 ms at 120×30, ~0.3 ms at 180×40** — and that *includes* the projection trig and the per-column writes the z-buffer would not eliminate. A best-case z-buffer fast path would shave a small fraction of that already-tiny slice.

Also: today's code already does most of what a z-buffer would do. `:dists` is consulted per cell to skip cells occluded by walls, `:edists` is consulted by the pickup paint to skip cells occluded by enemies, and `collect-enemy-projs` sorts enemies back-to-front so closer sprites overwrite further ones via the normal paint path. The "wasted writes" the z-buffer would avoid are bounded to dense overlap scenes, which already cost ~1 ms total.

Verdict: **win is sub-millisecond, complexity adds another implicit invariant (paint order must match z-buffer fill order) plus extra state. Not justified.** Issue closed without merging.

### Differential rendering (issue #3 — closed without merge)

Per-row diff against the previous frame, emitting only changed rows. Same `default-grid`, two-frame diff, bytes-emitted measured (lower = better):

| Scenario | Viewport | Full repaint | Row-diff | Δ |
|---|---|---|---|---|
| Paused (dt = 0) | 180×40 | 15693 B | 0 B | **-100 %** |
| Still player, world ticks (HUD + pulses only) | 180×40 | 15693 B | 6121 B | **-61 %** |
| Moving forward | 180×40 | 15583 B | 15864 B | **+2 %** |
| Turning | 180×40 | 15616 B | 15897 B | **+2 %** |

The static-scene wins are real but rare — once the player moves OR turns, every row's wall column changes and the diff cost (cursor-positioning overhead + the per-row string compare) makes it net *more* expensive than a single cursor-home full repaint. With the existing run-length encoding already keeping frames under ~16 KB at 180×40 and the cast+render budget under 5 ms, the saved bytes don't move the needle in the case that actually matters (active gameplay).

Add to that: invalidation logic for resize, scene reset, alt-screen re-entry, pause-menu overlay, minimap toggle, transient effects — every one of those would need a forced full-repaint flag, and getting any of them wrong leaves stale cells on screen.

Verdict: **complexity cost > realistic win**. Issue closed without merging.

## Measured numbers

`cast-frame` only, 2000-iteration mean from `default-grid` at the player spawn — bench harness lives in [`/perf-bench`](../.claude/skills/perf-bench/SKILL.md):

| Viewport | step-march (pre-#2) | DDA (post-#2) | Δ |
|---|---|---|---|
| 80×24 | 0.81 ms | 0.65 ms | -19 % |
| 120×30 | 1.26 ms | 0.99 ms | -22 % |
| 180×40 | 2.04 ms | 1.55 ms | -24 % |

Cast time scales roughly linearly with column count; DDA's win grows with viewport width because each ray's traversal cost drops while the per-ray trig (cos/sin/atan) stays fixed.

Whole-frame timing (cast + composition + ANSI emit) lands well under the 5 ms target at every viewport. Live perf numbers — including the cast/render split, bytes emitted, and PHP memory — are available in-game by pressing **F3** (issue #9). Game-loop overhead (`stty size`, `microtime`, `usleep`) adds ~2 ms; effective frame rate caps around 165 fps at 180×40.

### Reading these live: the F3 debug overlay

Press **F3** in-game to toggle a per-frame perf row that paints above the standard HUD footer. It surfaces (last-frame snapshot):

- `frame` — total frame time in ms (same source as the existing fps counter).
- `cast` / `render` — split of the frame budget between `cast-frame` and everything else `render!` does. Should add up to `frame` within timing jitter.
- `bytes` — `strlen` of the emitted ANSI frame string. Tracks the hypothesis behind the differential-rendering investigation (issue #3).
- `rle` — average bytes per `\e[` SGR prefix in the frame, a proxy for how effectively run-length encoding is collapsing same-colour runs (higher = better).
- `mem` — current / peak PHP memory (`memory_get_usage(true)`).

The overlay is **off by default and pays zero per-frame cost when off** — the instrumentation is fully gated behind the `:debug?` flag on the world, so production runs never call `microtime`, `strlen`, `substr_count`, or `memory_get_usage`. This is the canonical way to validate any future cast/render optimisation (issues #3, #4): toggle F3, read the numbers before and after.
