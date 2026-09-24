# Performance

The loop is `input -> step -> cast -> render`. Render dominates: it visits every terminal cell per frame (cols x rows). Cast is a rounding error. The step is a real but smaller share.

Every large win here came from one move: opting out of the persistent, generic Phel operation in code that runs thousands of times per frame. Read [Rules for the hot path](#rules-for-the-hot-path) and [Tried and rejected](#tried-and-rejected-do-not-retry) before optimising anything.

## How to measure

Absolute numbers do not travel between machines. The local php CLI runs without OPcache or JIT. A single reading drifts more than most changes are worth: in one sitting the same commit read 4.65 ms, 5.09 ms and 6.91 ms as the laptop warmed up. Compare in one sitting, interleaved, and trust deltas over milliseconds.

### The tracked harness

`tests/bench/frame-bench.phel` holds `defbench` rows (`phel.bench`) over one fixed scene: level 3, seed 1337, three enemies in view, shotgun held, minimap on.

| row | what it times |
|---|---|
| `cast-120`, `cast-240` | `cast-frame` alone |
| `step-120` | `tick-world`, a quiet frame |
| `step-fire-120` | `tick-world` with `:fire true` |
| `frame-120x30`, `frame-180x45`, `frame-240x60` | the whole `frame->string` |

`tests/bench/phel-costs-bench.phel` tracks the Phel primitives the hot paths are built on (map writes, `def` reads, equality, grid access). When a compiler upgrade makes one of those rows free, the workaround it justified can go.

```sh
composer bench                # every row, this machine
composer bench-store          # on main: write .phel/bench-baseline.json
composer bench-ref            # on the branch: delta per row, fail past +10%
composer bench -- --filter=cast --revs=1000   # one family, more revs
```

Each row reports mean and `rstdev`. Under 1% is normal on an idle machine. Above a few percent is noise to re-run, not a result. `bench-ref` is a same-machine, same-session gate, not a CI one. The suite loads the bench files too, so nothing in them runs at load: the scene is a `delay` forced on the first warmup rev.

### A/B against another ref

Use `tools/bench-ab.sh`, never two separate `composer bench` runs. Running the old ref then the new one has "measured" a 20% regression and a 10% win on unchanged code.

```sh
tools/bench-ab.sh v0.17.0          # 3 pairs, the frame-120 row
tools/bench-ab.sh main 5 frame-    # 5 pairs, every frame row
tools/bench-ab.sh HEAD~1 5 cast    # the cast rows
```

It alternates the refs back to back, so each pair shares a thermal state, and averages the per-pair deltas. **A consistent sign across every pair is the signal.** Mixed signs get flagged as noise. The tree must be clean: the script checks refs out in place and restores your branch, including on Ctrl-C.

Phel 0.53 also ships `phel bench --ab=<ref> --pairs=N`, which benches the ref in a temporary worktree and never touches your tree. It works: on an idle machine a 10-pair A/A (`--ab=HEAD`) read `step-120` -2.0% and `step-fire-120` -1.9%, both flagged as noise. An early 3-pair run under load read -7.7% with all three pairs agreeing, which looked like a bias and was not ([phel-lang#3347](https://github.com/phel-lang/phel-lang/issues/3347), closed). Whichever tool you use, run at least 5 pairs and check the load average first.

Under heavy load (load average 5-24) the means swung by up to 78%. The #526 and #527 passes used the minimum over 800-1000 calls instead, which held.

### Attribute render cost

`tools/bench-flags.sh` benchmarks the frame with each render feature switched off, interleaved:

```sh
tools/bench-flags.sh            # 2 passes, the frame-120 row
tools/bench-flags.sh 3 frame-240
```

Never set the flags by hand with `env $vars cmd`. zsh does not word-split an unquoted variable, so `env "A=1 B=1" cmd` sets ONE variable `A` to `"1 B=1"`. Every flag is checked with `=== "1"`, both read as off, and the run measures the default frame with a plausible number. That produced a phantom "disabling two features is 68% slower than disabling one". The script applies each config as a real assignment and refuses to run if its self-check shows the shell mangling it.

### Structural checks

Some wins are invisible in milliseconds and visible in the build. Run `composer build`, then:

- **Closure count.** `grep -c 'function() use(' out/phel_doom/io/render/main.php` must not grow against a same-environment main build. On phel 0.53 and PHP 8.5 (2026-09-24) it reads 21 for `main.php`, 11 for `hud.php`, 0 for `core/engine.php`. The count varies by compiler version, so compare builds, not fixed numbers. None may sit inside a per-cell `while` loop.
- **Map lowering.** `grep -c '->find(' out/phel_doom/core/<module>.php` confirms `^map` tags took effect.
- **Byte identity.** A render change must keep the golden `test-frame-bytes-pinned` hashes. Their fixture has no on-screen enemy, so a change near sprites or overlays also needs an md5-per-frame sweep across modes, positions and angles.
- **Full suite for `^:pure`.** An inliner bug once crashed only on physics, AI and projectile paths. The render hashes stayed green.

### Bench caveats

- **Two step rows, on purpose.** Every rev starts from the same world, so `step-fire-120` re-resolves a shot every rev (the cooldown never advances). A row that never fires misses the most expensive thing the step does. Quoting either alone is how a 2x difference gets written down as fact.
- **Per-frame caches are invisible to the bench.** Each rev starts from a pristine world, so a cache across frames never warms. Measure those by threading a world through a few hundred frames, as the game does.
- **Fixed-viewport rows never exercise resize, pitch or pixel-doubling changes.** A memo keyed on those needs its own sweep.
- **Live numbers:** press **F3** in game for the cast/render split, bytes emitted, PHP memory and RLE compression. The overlay costs nothing when off.

## Measured numbers

`composer bench` on 2026-09-24: phel 0.53, PHP 8.5, no JIT, M-series laptop.

| row | mean |
|---|---|
| `cast-120` | 0.055 ms |
| `cast-240` | 0.095 ms |
| `step-120` | 0.31 ms |
| `step-fire-120` | 0.47 ms |
| `frame-120x30` | 4.3-4.5 ms |
| `frame-180x45` | 7.9 ms |
| `frame-240x60` | 12.6 ms |

The frame rows include the cast. At 120x30 render is ~98% of the frame, and the step adds 7-11% on top of it.

### Where the frame time goes

`tools/bench-flags.sh` at 120x30 (2026-08-17, phel 0.50, frame 5.75 ms):

| Feature removed | frame | share |
|---|---|---|
| baseline | 5.75 ms | - |
| wall texture (`PHEL_DOOM_FLAT_WALLS=1`) | 3.39 ms | 41% |
| floor cast (`PHEL_DOOM_FLAT_FLOOR=1`) | 4.79 ms | 17% |
| sub-pixel sampling (`PHEL_DOOM_NO_SUBPIXEL=1`) | 4.87 ms | 15% |
| texture filter ON (`PHEL_DOOM_TEXMIP=1`) | 5.80 ms | -1% |

The shares overlap and do not sum: flat walls subsume the floor cast, and sub-pixel sampling is what makes texture sampling expensive. The table predates the #526 wall-band pass (-6% at 120x30). Use it for ranking. **The wall texture is the biggest line in the frame.** A 10% win there beats deleting the floor cast outright.

Inside the 41% (same method, 5.50 ms baseline): fast walls, one texel per interior cell (`PHEL_DOOM_FLAT_WALLTEX=1`), buy only 9 points. The other 32 are machinery the textured path needs and the flat path skips: the per-column `tex-u` / `tex-level` / `tex-sz` / `tex-px` buffers, the seam and silhouette branches, and the per-cell dispatch between them. Attack the structure, not the sample math. Three sample-math attempts are recorded under [Tried and rejected](#tried-and-rejected-do-not-retry).

### Inside the step

Stage by stage on the bench scene, quiet frame of 448 us (phel 0.51, 2026-09-22, before the write-skipping pass):

| stage | us | cost driver |
|---|---|---|
| tick-enemies | 100 | 3 enemies, ~33 us each: a LOS ray plus 6-8 map writes |
| damage-step | 69 | one 20-key variadic `assoc` rewriting 17 timers at 0.0 |
| pickups (10 rules) | 50 | ten `filterv` rebuilds to find the player standing on nothing |
| apply-physics | 50 | two `weapon-spec` lookups, two sprint checks, idle bob-phase write |
| mark-visible-cells | 31 | 5 us on the memo hit |
| tick-scare | 21 | 3-key variadic write every frame |
| refresh-from-keys | 18 | five regexes over an empty drain string |
| everything else | ~110 | toggles, six `get-in`, two closure `update`s, timers |

The cost was **writes to the world map that changed nothing**, not reads. The fixes are listed in [History](#history). `mark-visible-cells` (the fog-of-war line-of-sight scan within `visit-radius`) now skips when the player has not changed cell. Its cache has two inputs: `:visited-at` for the player's cell, and `state/rebuild-pgrid` clearing the stamp for the grid, so a secret opened next to a standing player still lights up. `tests/core/engine-test.phel` pins that hook.

A firing frame after #527 (minimum over 800 calls, 2026-09-23): `fire-shot` costs 191 us, of which `spread-shoot` is 54 and `enqueue-shot-sfx` 36. The wall hitscan is one DDA ray, 5.5 us. With no enemies in the world a firing step costs ~90 us more than a quiet one.

## Rules for the hot path

### No statement-forms in hot-loop binding values (the closure tax)

The biggest win in the project: 4-10x whole-frame. Phel compiles a `let` binding whose VALUE is a statement-form (`cond`, `and`, `or`, a `let`, a `when`, a `loop`) into an immediately-invoked PHP closure. Its `use(...)` list captures EVERY local in scope, and PHP copies each one in on every call. In `frame->string`'s setup that is ~500 variables. In the per-cell loop of `emit-scene-px1` / `emit-scene-px2` it is the ~70-param scene scope. Measured in isolation: 7 such closures per cell at 200x45 cost ~168 ms/frame; the same work through a plain array register costs ~0.4 ms.

The per-cell loops follow a strict shape:

- Every per-cell binding value is a PURE expression: arithmetic, `aget`, a fn call, an `if` with expression branches. These compile inline.
- Branching work writes its result into a small pre-allocated php-array register (`cell-reg`, `pack-reg`, `hit-reg`) from conds in STATEMENT position, then reads it back with one `aget`.
- `and` / `or` in a binding value closure-compile too. Rewrite them as nested `if`s, or move them into a plain fn call.
- Row-constant work (gradient rows, floor-cast row terms, `row * vw`) hoists into a per-row `let` outside the column loop.

The rule covers every per-cell or per-column loop, not only the scene emitters. The cast loop has been closure-free since #345 moved the DDA march and `wallx` into `hit-reg`. The minimap's `hud/sample-cell`, `hud/block-has-wall?` and `block-visited?` each ran a nested `loop` in a binding value per minimap cell; flattened to ONE loop over both axes they carry no closures (`sample-cell` self time -43%, `minimap-rows` -17%).

Result of the original fix (#192, 2026-06, 3-enemy corridor, ms/frame, byte-identical over a 24-config md5 matrix):

| Viewport | before | after | speedup |
|---|---|---|---|
| 80x24 full detail | 26.7 | 7.1 | 3.8x |
| 120x30 full detail | 44.7 | 8.9 | 5.0x |
| 200x45 full detail | 114.0 | 13.6 | 8.4x |
| 240x60 full detail | 180.4 | 17.4 | 10.4x |
| 240x60 pixel-doubled | 56.7 | 12.9 | 4.4x |
| 300x80 pixel-doubled | 87.6 | 17.3 | 5.1x |

Check for regressions with the closure count in [Structural checks](#structural-checks).

### Phel/PHP closure gotcha in the emitter

The same compilation rule is a correctness trap. A `buf-push` or any `php/aset` inside a let-binding VALUE runs inside the IIFE closure. PHP `use` copies arrays in, so the write lands on a copy and is silently lost. Binding values stay pure reads; mutation goes in statement position before `recur`. PHP arrays also pass by value across fn boundaries: the lifted scene emitters return `[parts center-cap]` and the caller must rebind both from the result.

### Direct PHP ops and native arrays

Unspecialised Phel ops dispatch through the runtime. Hot loops use `php/+`, `php/<`, `php/aget`, `php/===`: `$a + $b`, `$arr[$k]`, no dispatch.

- **`:pgrid`.** `new-world` builds a PHP-array twin of the grid, `(to-array (map to-array grid))`. The raycaster and minimap subscript it directly. `state/rebuild-pgrid` keeps `:grid` and `:pgrid` in sync. `:light-grid` is a sibling twin updated by the same hook. Room lighting adds one `php/aget` per COLUMN, never per texel (+0.5% render at 120x30, +2.5% at 180x40, only with the opt-in `:light` setting).
- **Inline `?? 1` subscripts** replace `engine/cell-at` at every former call site (#354): the cast column loop, `cast-ray` and `los-clear?`.

#### Flat distance arrays from cast-frame

`cast-frame` returns PHP arrays (`:dists`, `:hits`, `:hxs`, `:hys`, `:sides`). The renderer walks them by column index: no lazy seqs, no Phel dispatch.

### Pre-bake, hoist and memoize

Anything that does not change per cell is computed once, at the coarsest level it can live at.

- **Shade tables.** A 24-step grayscale is baked at load; per-cell shade is one `php/aget`. `shade-code-table` holds the codes as strings for half-block edge composition. The fog LUTs (`tex-fade-table`, `build-themed-gradient`) bake the tinted filmic fade at load, so the hot path stays one nested `aget`.
- **Per column.** `compute-wall-shades` computes each column's shade strings, `tex-*` buffers and `:wall-h` once. The row loop reads them with one `aget` (40x fewer shade computations at 180x40).
- **Per frame.** `frame-gradients` is a single-slot memo of the sky/floor gradients, sub-row sky codes and floor-cast tables, keyed on `(vh, pr, sub-vh, pr-sub)` and the level theme. It rebuilds only on resize, pitch change, view bob or a pixel-doubling toggle.
- **Per width.** `offset-tables-for` caches per-width `[col -> offset]` and `[col -> cos(offset)]` arrays, so `cast-frame` reads two `aget`s instead of trig per column.
- **Globals captured once.** A reference to a module-level `def` compiles to `\Phel::getDefinition(ns, name)` on every read. `frame->string` binds each hot global (`tex-fade-table`, `bg-cell-cache`, `seam-darken-*`) once in its frame-level `let`, so inner references become PHP locals (-5.9% at 180x40).
- **Cell strings.** The 2-colour `halfblock` cache (`half-cell-cache` in `frame_math.phel`) returns a pre-baked `\e[..m▀` string per colour pair. Building that string per cell instead costs ~+50%.
- **Shared projections.** `collect-enemy-projs` runs once per frame; `paint-enemy-hp-flashes` and the full-detail `paint-face-overlay` reuse its `enemy-projs`. Pixel-doubled mode keeps its own `svw`-scoped call, because projecting at `svw` rounds differently from halving a full-width column.

### `php/.` for hot string building, not `str` (phel 0.50)

`str` is a runtime `phel.core` call plus one `val-to-str` per argument. Since phel 0.50 it lowers to a native `.` chain, but ONLY when every non-literal argument is statically a `string`. One int argument keeps the whole call at runtime, and almost every cell builder concatenates a colour code.

- **Pre-bake the SGR fragment.** `palette/fg-cache`, `bg-cache` and `block-cache` hold `\e[38;5;<n>m`, `\e[48;5;<n>m` and `\e[38;5;<n>m█` for all 256 codes. `weapon-row-string` and `enemy-sprite-cell` index those.
- **Write `php/.` where the fragments are already strings**, as in the seam-cell builders of `compute-wall-shades`.
- `enemy-sprite/quadrant-glyph` is a php-array indexed by the 2x2 mask: one `aget` instead of a `get` on a Phel map.

Measured over 200 frames (2026-08-16): `str` calls per frame 874 -> 113, `weapon-row-string` 84.5 -> 18.5 us/call, `compute-wall-shades` 874.7 -> 336.9 us/call. Whole frame -8.4% at 120x30, -5.7% at 240x60.

The trap: never swap `str` for `php/.` over a float, a bool or nil. PHP renders them differently (`1.0` -> `"1"`, `true` -> `"1"`, nil -> `""`). Ints and strings are safe.

### What a Phel operation costs

Loop overhead subtracted for the 0.50 column (200k iterations, 2026-08-17). The 0.53 column is the matching `composer bench` row (2026-09-24, PHP 8.5, loop overhead included). Read rows against each other, not as absolutes.

| | phel 0.50 | 0.53 row |
|---|---|---|
| `php/aget` on a nested php array | ~4 ns | - |
| `(get row x)` on a persistent vector | ~600 ns | - |
| reading a module-level `def` | ~320 ns | 199 ns (`read-module-def`) |
| `php/===` against a literal | free (folded) | - |
| `=` on ints | ~850 ns | 345 ns vs 203 ns for `php/===` |
| `(cell grid x y)` | 1.6 us | 810 ns |
| `(wall? grid x y)` | 2.1 us (was 5.9) | 904 ns |

- **A module-level `def` is not a constant.** Every read is a registry lookup by two strings. Hoist constants into a `let` outside the loop. Inside a per-call predicate there is nowhere to hoist to, which is why `wall?` compares against literals, pinned by `test-wall-literals-match-the-constants`.
- **`=` and `<` dispatch on type.** On values known to be ints, use `php/===` and `php/<`.
- The persistent, generic version of an operation cost 100x to 1000x the native one on 0.50. The gap has narrowed on 0.53 but still favours native ops. None of this moves a frame on its own (the `wall?` swap is ~1.5% of a threaded frame). It matters where calls are counted in thousands.

### What a write costs on Phel 0.51

The step phase lives on map writes. The 0.51 column is a microbench on the real 90-key world map (2026-09-22, PHP 8.4, no JIT, 20k iterations). The 0.53 column re-measures the same shapes on a synthetic 90-key map (2026-09-24, PHP 8.5, no JIT, 20k iterations, scratch loop).

| | phel 0.51 | 0.53 |
|---|---|---|
| `(assoc m :k v)` | 1.25 us | 1.1 us |
| same, target tagged `^map` | 0.95 us | - |
| `(assoc m :k v)` when `v` is already stored | 1.38 us | 0.56 us |
| `(if (php/=== v (get m :k)) m (assoc m :k v))` | 1.12 us | 0.68 us |
| `(assoc m :a 1 :b 2 :c 3)` | 6.9 us | 3.2 us |
| three chained single-key `assoc` | 3.2 us | 3.2 us |
| three `assoc!` through a transient | 4.2 us | 3.7 us |
| `(assoc m :k1 1 ... :k20 20)` | 58.0 us | 10.1 us |
| twenty chained single-key `assoc` | 16.0 us | 10.0 us |
| `(update m :k (fn [v] ...))` | 3.5 us | 1.7 us |
| five `(:k m)` reads, untagged | 2.2 us | - |
| five `(:k m)` reads, `m` tagged `^map` | 0.95 us | - |
| `(get-in m [:a :b])` | 2.2 us | - |
| `(:b (:a m))` | 0.77 us | - |
| `(filterv p (map f coll))`, 4 items | 14.7 us | - |
| `(into [] (comp (map f) (filter p)) coll)` | 27.8 us | - |

The rules, as they stand on 0.53:

1. **Skip whole decays and rebuilds, not single writes.** `combat/decay-key` writes a timer only while it runs; a quiet frame writes a handful of keys instead of forty. A guard around one same-value write does not pay: a compare-first helper (`state/assoc-changed`, removed) measured 1-2 us slower than rewriting in `apply-heat` on 0.51, and on 0.53 a same-value `assoc` (0.56 us) is cheaper than the guarded form (0.68 us) because it returns the map itself.
2. **Variadic `assoc` no longer needs chaining.** On 0.51 a multi-key `assoc` was 2-4x the chained form and worsened per pair. On 0.53 the two cost the same at 3 and 20 keys, and the `assoc-2-keys-*` bench rows agree. The existing chains are harmless. Do not write new chains for speed. Transients still do not beat plain writes on a hash map.
3. **Tag map params on the per-frame path.** `^map world` makes every `(:k world)` in the body a `->find` call and `assoc` a `->put` (phel-lang #3319). Do not tag the one-expression `^:pure` helpers that still inline: a tagged param stops the inliner, and the inline is worth more. Verify with the `->find(` count, not a millisecond.
4. **Probe before you rebuild.** An indexed scan that exits on the first hit beats a `filterv` that allocates the answer to "was anything there".
5. **Prefer `assoc` of a computed value over a closure `update`.** On 0.51 a counter bump was 3.1 us as `update` and 2.2 us as `(assoc m :k (php/+ (or (:k m) 0) 1))`. On 0.53 they are within 5%.

### Compiler call inlining (`^:pure`)

`phel-config.php` builds at `withOptimizationLevel(2)`, which enables the compiler's `CallInliner`. `^:pure` on a `defn-` asserts the body is side-effect-free and lets the inliner splice a single-expression body into its call sites, dropping the `getDefinition(...)->__invoke(...)` dispatch. `src/` carries 59 `^:pure` helpers: `map/cell`, `map/wall?`, `projection/wall-px`, `enemy/in-cone?`, the AI, physics and render-math helpers.

The win is removing a PHP frame per call, not changing the math. It is small in ms and lost in bench noise. Verify it by diffing `out/`, where the dispatch form disappears.

Two compiler facts shape this:

- **Typed callees do not inline** (since phel 0.50, #3126). Splicing dropped the parameter type and the native arithmetic it enables, and 0.50 also widened type inference. On 0.50, 38 of 54 `^:pure` helpers gained at least one dispatch site. It was a trade, not a regression: the same source ran faster end to end (120x30 8.8 -> 6.6 ms/frame, unit suite 25.9 s -> 10.7 s). Keep the tags. A dispatch site on a `^:pure` helper is not a bug. The closure count is the structural check that still means something.
- **Always full-suite a `^:pure` change.** The first let-body inliner build (phel-lang #2586) mis-renamed variables and crashed at runtime on physics, AI and projectile paths only (fixed in #2622, shipped in 0.46).

### Output

#### Run-length encoding

Consecutive same-colour cells coalesce: one escape, N spaces. That cuts output 5-10x on monochrome rows. Runs of identical ▀ cells repeat the bare glyph, since the SGR state persists.

#### Skip the minimap region

The minimap rewrites the top-right region via cursor positioning after the row loop. The scene loop emits a cheap placeholder for cells there (bounds from `mini-col0` and `visible-mh`) and skips their blood and shade work.

#### Alt screen buffer + cursor-home redraw

Alt screen plus cursor home each frame, no clear. The terminal overwrites in place: no flicker, no scroll. `render!` writes through `print`, never a raw `fwrite`, which can write a partial frame.

### Float type tags

PHP deprecates implicit lossy float-to-int conversion. Hot-path numeric args carry explicit `^float` tags so Phel does not infer int, as in `ms-since`:

```phel
(defn- ms-since [^float t-then ^float t-now]
  (php/intval (php/* (php/- t-now t-then) 1000)))
```

### Rule for march changes

The DDA march (~5-8 cell crossings per ray instead of ~35 fixed steps, see [raycaster.md](raycaster.md)) runs on every column of every frame of every level. Any per-step cost added unconditionally shows up everywhere. Gate it or make it free.

## Runtime and scaling

### PHP runtime: OPcache + JIT

OPcache caches parsed bytecode, so startup does not re-parse `vendor/phel-lang/`. Enable it. The JIT does not speed up this loop: opcache plus tracing JIT measured ~0% on the render (2026-06), and the built artifact was no faster than `phel run`. The loop is call-, array- and string-heavy, and the generated PHP is the same either way.

```ini
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0   ; set to 1 during development

opcache.jit_buffer_size=128M
opcache.jit=tracing
```

Verify with `php -r 'var_dump(opcache_get_status()["jit"] ?? "no jit");'`. If you bench with JIT on, measure at frame >= 60, after traces compile. The repo-root Dockerfile does NOT configure OPcache or JIT.

### Big screens: uniform cadence + crisp walls

`src/core/perf.phel` holds the frame-loop constants:

- **Cadence.** `standard-frame-us` is 8333 (~120 fps) at every terminal size. It is a ceiling: framerate tracks render capability below it, and the per-iteration sleep floors at `min-yield-us`. Every input feel constant is stored in seconds or per-second units, so the cap can move without changing input feel.
- **Render scale.** `standard-scale` is 1 (one ray per output column) at every size, so wide terminals get crisp walls. The pixel-doubled path passes `2` to `cast-frame` directly, not through `render-scale`.

Render cost scales ~linearly with cell count, so the strongest lever left is fewer cells. The game **auto-calibrates a pixel scale** (see [game-loop.md](game-loop.md), `auto-pixel-scale`). It measures `auto-cal-frames` full-detail frames under the intro splash. When the minimum render-ms exceeds `auto-target-frame-ms` (24 ms) AND the terminal is a big screen (area beyond 200x45, `big-screen?`), it locks pixel scale 2: the scene renders at half resolution and each scene cell paints a 2x2 block, ~4x cheaper. The game always fills the terminal. At or below 200x45 it never pixel-doubles: detail wins over framerate there. Since the closure-tax fix, full detail holds 24 ms up to roughly 240x60 on the reference machine, so pixel-doubling engages only on huge terminals or slow hardware. `--max-cols=0` forces full detail; `--max-cols=N` sets a manual cap.

Pixel-doubling keeps framing, FOV and sprite sizes: the cast runs at the full width with scale 2 (`compact-cast-2`), every `proj-dist`-derived quantity is halved via an explicit `pd` parameter, and each scene cell still samples four vertical sub-texels. Only the horizontal texel doubles. See [rendering.md](rendering.md#pixel-doubled-mode-auto-big-screens-on-slow-machines).

Half-block sub-pixel rendering costs +2% CPU against flat cells (2026-06, pre-closure-fix absolutes; the ratio held) and +47% to +71% bytes per frame from denser SGR and less RLE coalescing. That is an I/O cost. Cap it with `--max-cols` on ultra-wide terminals.

### Resize sampling (issues #280, #459)

`term-size` forks and execs `stty size`, outside the measured frame budget. The game loop samples it only when SIGWINCH fires (`sample-size?`, #459) plus frame 0. The menu and end-screen loops, and any build without ext-pcntl, fall back to `poll-size?`: frame 0, then every `resize-poll-frames` (12) frames, reusing the last `[rows cols]` in between. See [game-loop.md](game-loop.md#resize-sigwinch-not-polling-issue-459).

### View bob and the gradient memo (issue #411)

Head bob adds a walk-cycle term to `pr`, the `frame-gradients` memo key, so View bob plus movement rebuilds the gradients more often. Worst case, `pr` flipping every frame: **+0.04 ms at 120x30, +0.28 ms at 180x40**. `bob-rows` quantises to whole rows, so the real rate is a few rebuilds per bob cycle. View bob defaults off. The bob term is baked into `pr` at the two `pitch-rows` sites; decoupling it from the memo key would add hot-path complexity for no measurable win.

### Memory

The renderer is built out of lazy memos (half-block and truecolor cell caches, BG cell cache, per-width offset tables, gradient bundles). Each is a per-frame leak if its key can keep taking new values: nothing fails, and a long session dies on the memory limit.

Measured with the player walking and turning (2026-08-17): **flat at 1130 frames in 256-colour and truecolor modes**. Baseline ~63 MB of baked tables; peak 63.5 MB at 120x30, 67.6 MB at 400x100. A default 128M `memory_limit` has room. `tests/io/render-memory-test.phel` runs 400 moving frames after a 30-frame warmup with a 256 KB budget, which catches a leak of ~640 bytes per frame.

## Tried and rejected (do not retry)

Each entry has the number that decided it. Re-open one only if the stated condition changes.

- **`^vector` tags on the enemy loops (Phel 0.53).** On a `^vector` local, `(count v)` compiles to `->count()` and `(nth v i)` to `->get()`, skipping the generic dispatch. Tagging `target-index`, `closest-attacker`, `rear-attacker?`, `beam-impact`, `splash`, `pierce` and the spread pair: `step-120` +1.4%, `step-fire-120` +0.2%, mixed signs over 5 pairs. A level holds a dozen or so enemies, so the loop overhead is not a cost, and the tag adds a `TypeError` if a non-vector ever arrives. Revisit if enemy counts grow by an order of magnitude.

- **Inlining the `halfblock` memo call.** Saves 18.6 ns per cell (40.3 vs 21.7 ns over 2M iterations): 0.067 ms per frame at 120x30, 1.2%, under the bench's ±4% rstdev. Not worth reaching into another namespace's private cache.
- **Hoisting the per-column fade table out of the cell loop.** Under 1% or net-negative, measured twice. Wall texture and seam micro-optimisations in general sit under the noise floor; the cost is the per-sub-row texture sample itself.
- **Emitting only the changed half of each SGR pair.** 5,595 bytes (12.2%) of a 45,680-byte frame at 120x30 re-state colour the terminal already has. Fixing it breaks verbatim reuse of the pre-baked cell strings and spends CPU in a CPU-bound frame to save bytes on a path that is not the bottleneck. Revisit only if the terminal link becomes the constraint (slow SSH).
- **Sprite occlusion z-buffer (#4).** 15 clustered enemies add ~0.8 ms at 80x24 and ~0.3 ms at 180x40 (2026-05). `:dists`, `:edists` and back-to-front sorting already do most of a z-buffer's work.
- **Differential rendering (#3).** A per-row diff saves 100% paused and 61% standing still, but costs +2% bytes while moving or turning, and needs invalidation for resize, reset, alt-screen re-entry, pause, minimap toggle and effects.
- **`:inline` metadata on a one-line helper.** 5.6 vs 6.1 us per 5 calls, 8%. Not worth the macro-hygiene surface.
- **`into` with a transducer.** 2x slower than `filterv` over a lazy `map` (phel-lang #3323).
- **Transients for batched world writes.** Slower than plain writes on a hash map on 0.51 and on 0.53 (see the write table).
- **A compare-first guard (`assoc-changed`) around a single same-value write.** Slower than the write it skips on 0.53; removed (see rule 1 above).
- **Decoupling view bob from the gradient memo key.** Worst case +0.28 ms; see [View bob](#view-bob-and-the-gradient-memo-issue-411).
- **Relying on the JIT.** ~0% on the render loop (see [PHP runtime](#php-runtime-opcache--jit)).

## History

The wins that built today's frame, oldest first.

| when | change | result |
|---|---|---|
| 2026-05 | DDA raycaster (#2) replaces the fixed step-march | `cast-frame` -35% |
| 2026-05 | per-width FOV tables and the DDA inlined into `cast-frame` | `cast-frame` -61%, -75% total vs step-march (120x30: 1.26 -> 0.32 ms) |
| 2026-06 | closure tax removed from both emitters (#192) | 3.8x to 10.4x whole frame |
| 2026-06 | half-block sub-pixels with the 2-colour cell cache | +2% CPU instead of ~+50% |
| 2026-06 | frame-level global capture (#262) | -4.2% at 80x24, -5.9% at 180x40 |
| 2026-06 | resize poll throttled (#280) | removes a ~1 ms fork from most frames |
| 2026-06 | let-body `^:pure` inlining (phel 0.46, #2586) | ~45 hot helpers stop dispatching |
| 2026-07 | `frame-gradients` covers sub-row sky and floor-cast tables; `:wall-h` column buffer; one shared enemy projection | within noise on fixed viewports, kept for resize, pitch and combat frames |
| 2026-08 | phel 0.50 plus `php/.` and pre-baked SGR fragments (#452) | 0.50: 120x30 8.8 -> 6.6 ms; `php/.`: a further -8.4% |
| 2026-08 | minimap scans flattened to one loop | `sample-cell` -43% |
| 2026-08 | `wall?` compares literals; per-frame writes chained (#519) | ~1.5% of a frame each |
| 2026-08 | `mark-visible-cells` skips when the player keeps its cell | step 1.11 -> 0.97 ms walking |
| 2026-09 | step write-skipping on phel 0.51 (#524) | `step-120` -29%, `step-fire-120` -32% |
| 2026-09 | column-major wall band in `emit-scene-px1` (#526) | 120x30 -6%, 180x45 -12.5% |
| 2026-09 | firing frame writes and grid reads (#527) | firing step -7.2% |

Notes on the entries that still shape the code:

- **#524, step writes.** Per commit, `tools/bench-ab.sh HEAD~1 3 step` on `step-120`: pickups probe before rebuilding -10.2%, timers decay only when running -5.6%, physics and play hoists -13.0%, `^map` tags on combat, physics and play params -14.0%. Whole branch, five pairs, one sign: `step-120` 435.5 -> 308.4 us, `step-fire-120` 713.5 -> 480.7 us.
- **#526, the wall band.** `emit-scene-px1` stays row-major for RLE, but runs a column pass first: it resolves each column's kind and constants once and writes the wall band into a flat `wall-cells` array keyed `row*vw+col`. The row loop reads a wall cell with one `aget`. The floor stays row-major because its constants are per row. Byte-identical across 1344 frames (12 render modes x 3 positions x 8 angles x 2 sizes). `emit-scene-px2` keeps the row-major shape.
- **#527, the firing frame.** `damage-enemy` 26 -> 13.5 us (two variadic `assoc`s and a `get-in` resist lookup), `noise-wake` 32 -> 16 us (its BFS moved from `map/cell` to `:pgrid`), `fire-shot` 251 -> 191 us. Before #531 the death-cry lookup walked ~90 world keys for an enemy that was never there, so no kill played its cry.
