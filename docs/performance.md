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

## What's NOT optimised (yet)

- **DDA raycaster**. Current step-march does ~35 iterations per ray. Grid-aligned DDA would do ~5-8. ~5× faster cast phase. Larger refactor.
- **Differential rendering**. Every frame painted in full. Could diff against previous and emit only changed cells. Huge win on static scenes, meaningful complexity cost.
- **Sprite occlusion via z-buffer**. We re-test wall distance per cell when painting an enemy. A per-column min-z buffer would early-exit. Marginal at 5ms total budget.

## Measured numbers

| Viewport | frame->string time |
|---|---|
| 80×24 | ~2 ms |
| 120×30 | ~3 ms |
| 180×40 | ~5 ms |

Game-loop overhead (`stty size`, `microtime`, `usleep`) adds ~2ms. Effective frame rate caps around 165 fps at 180×40.
