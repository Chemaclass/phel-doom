# Performance

`frame->string` on a 180×40 viewport runs in ~5ms. Inner loop has
~7200 iterations per frame (180 cols × 40 rows). Tricks that got it
from "tens of ms" to "single-digit ms":

## Direct PHP ops in the hot loop

Phel's `+`, `<`, `aget`, etc. are polymorphic — they dispatch
through the Phel runtime to find the right implementation. That's
fine for application code but heavy in a per-cell loop.

The renderer + raycaster use `php/+`, `php/<`, `php/aget` instead.
These compile to PHP `$a + $b`, `$a < $b`, `$arr[$k]` directly — no
dispatch, no method call. ~5× speedup on the hot loop.

```phel
(php/aget shade-table idx)   ; compiles to:  $shade_table[$idx]
(php/+ a b)                  ; compiles to:  $a + $b
```

## Pre-baked shade tables

The 24-step grayscale palette is computed once at load time:

```phel
(def shade-table
  (let [t (php/array)]
    (loop [i 0]
      (when (php/< i 24)
        (php/aset t i (str "\e[48;5;" (php/+ 232 i) "m "))
        (recur (php/+ i 1))))
    t))
```

Per-cell shade lookup becomes one `php/aget`. No memoize cache, no
string allocation per call.

A parallel `shade-code-table` holds just the colour code as a
string (`"240"` etc.) used to compose half-block edge cells. Avoids
having to re-parse the BG code out of the prebaked ANSI string.

## PHP-native nested array for the grid (`:pgrid`)

Phel's persistent vectors are great for pure updates but slow for
indexed reads in a tight loop. `new-world` builds a PHP-array twin
of the grid that the raycaster + minimap iterate without touching
Phel's collection machinery:

```phel
:pgrid (to-php-array (map to-php-array grid))
```

Reads go through `php/aget` — direct PHP subscript. Both `:grid`
and `:pgrid` must be updated together when a cell changes (door
opens, etc.).

## Flat distance arrays from cast-frame

`cast-frame` returns parallel PHP arrays:

```phel
{:dists <php-array> :hits <php-array> :hxs ... :hys ... :sides ...}
```

The renderer walks them by column index. No lazy sequences, no
Phel vector dispatch.

## Per-column shade pre-bake

The renderer computes each column's three shade strings — normal,
top-edge, bot-edge — **once** in an outer loop, then the per-row
inner loop just does an `aget` against the column array. The
expensive math (distance → side darken → cell hash → clamp) runs
once per column, not once per cell.

For a 180×40 viewport that's a 40× drop in shading work compared to
a naive per-cell shade computation.

## Run-length encoding

Inside the per-row loop, consecutive cells with the same ANSI escape
get coalesced into one paint + N spaces:

```
\e[48;5;240m            (set BG once)
"          "            (12 spaces — terminal keeps the BG)
```

Cuts output size 5-10× on rows that share a colour. Done in-place
with a small state machine in the inner loop (`prev` + `run`
counters) — no separate buffer pass.

## Skip the minimap region

The minimap overlay rewrites the top-right ~24 cols × ~22 rows via
absolute cursor positioning **after** the main row loop. The cells
underneath those overlays don't need to be painted properly — the
inner loop emits a cheap `sky-gradient[row]` placeholder for cells
in the minimap region (detected by a precomputed `mini-col0`
threshold + `visible-mh` row threshold). Skips the blood-paint
lookup, the four-arm cond, and both shade lookups for those cells.

## Alt screen buffer + cursor-home redraw

```phel
\e[?1049h    ; enter alt screen
\e[?25l      ; hide cursor
\e[?7l       ; disable autowrap
\e[H         ; cursor home each frame (no clear)
```

The terminal sees us repeatedly home-and-overwrite. No flicker, no
scroll, no full clear (which would flash). The previous frame's
state is implicitly overwritten cell-by-cell because we emit the
same number of bytes per frame.

## Float type tags

PHP 8.4+ deprecates implicit float-to-int conversion when the cast
loses precision. Phel's type inferencer sees `(* x 1000)` and emits
`int $x` in the compiled PHP signature — perfect for ints, but
broken when callers pass `microtime(true)` values.

Hot-path numeric args get explicit `^float` tags:

```phel
(defn- ms-since [^float t-then ^float t-now]
  (php/intval (php/* (php/- t-now t-then) 1000)))
```

Phel emits `float $t_then, float $t_now` in the compiled signature.
No implicit cast, no deprecation, no log spam.

## What's NOT optimised (yet)

- **DDA raycaster** — current step-march does ~35 iterations per
  ray. Grid-aligned DDA would do ~5-8. ~5× faster cast phase.
  Larger refactor.
- **Differential rendering** — we paint every frame in full. Could
  diff against the previous frame and only emit changed cells.
  Massive win on static scenes; meaningful complexity cost.
- **Sprite occlusion via z-buffer** — currently we re-test the wall
  distance per cell when painting an enemy. A per-column min-z
  buffer would let us early-exit. Marginal at 5ms total budget.

## Measured numbers

| Viewport | frame->string time |
|---|---|
| 80×24 | ~2 ms |
| 120×30 | ~3 ms |
| 180×40 | ~5 ms |

Game-loop overhead (`stty size`, `microtime`, `usleep`) adds ~2ms.
Effective frame rate caps around 165 fps at 180×40.
