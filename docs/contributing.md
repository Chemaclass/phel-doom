# Contributing

Dev workflow + Phel quirks that bit me, in one place.

## Bootstrap

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
composer install     # installs deps + wires .githooks/pre-commit
make play            # or: composer play
```

`composer install` runs a post-install hook that points
`core.hooksPath` at `.githooks/`. From then on every commit runs
`composer ci` (format-check + lint + test + build) before landing.
Bypass with `git commit --no-verify` only in genuine emergencies.

## Composer scripts

```bash
composer dev          # phel run main.phel (alias for the entry)
composer play         # phel run main.phel play
composer test         # phel test, with PHEL_DOOM_SILENT=1 so no audio
composer format       # auto-format every .phel
composer format-check # dry-run, fails CI on dirty files
composer lint         # static analysis
composer build        # compile to out/main.php
composer ci           # the full pre-push gate (also what the hook runs)
composer repl         # interactive REPL
composer doctor       # phel env diagnostic
```

CI runs `composer ci` on PHP 8.5 only. Local PHP 8.4 also works
during development but isn't matrix-tested.

## Module layout

See [docs/README.md](README.md) for the file map.

Dependency rules:

- `core/` never imports `io/` or `glue/`. Anything pure goes here.
- `io/` may import `core/`. Side-effecting code goes here.
- `glue/` may import both. Pure byte → world transformations that
  need both sides go here (e.g. controls parsing).

Tests mirror `src/`: each `*-test.phel` covers the matching module.

## Test conventions

- **Behavioural pins, never implementation pins.** Assert WHAT a fn
  returns, never how it walks a list or which exact data shape it
  uses. Keeps refactors safe.
- **No real audio.** `composer test` sets `PHEL_DOOM_SILENT=1` which
  short-circuits `play-sfx!` in `sound.phel`. Running
  `vendor/bin/phel test` directly bypasses the gate; always use the
  composer script. `tests/modules/io/sound-test.phel` asserts the
  env var is set during the suite, so this can't silently regress.
- **No real filesystem.** `merge-run` in `scores.phel` is the pure
  half of `update-scores!` and is what gets tested. The IO wrapper
  (touching `$HOME/.phel-doom-scores.json`) is not.
- **No fakes / mocks under `core/`.** Anything pure is tested
  against literal data: hand-built worlds, grids, enemy vectors.
  See `tests/modules/core/physics-test.phel` for the pattern.

When adding a feature, add tests in the matching module before the
implementation if you can, or right after. Test count is in
README; bump it when you add tests so the doc stays honest.

## Phel gotchas

A few things that aren't in Phel docs but bit me hard. Write them
down so the next person doesn't repeat the same incidents.

### PHP arrays are pass-by-value across fn boundaries

```phel
;; BROKEN — mutation lost
(defn- paint-into! [arr]
  (php/aset arr 0 99))

(let [a (php/array)]
  (paint-into! a)
  (php/aget a 0))   ; => nil, not 99
```

The `(php/aset arr ...)` inside `paint-into!` mutates a local copy
of `arr`. The caller's binding sees no change. Two ways out:

1. **Keep the loop inline** in the same lexical `let` scope:

   ```phel
   (let [a (php/array)]
     (loop [...] (php/aset a ...))
     (php/aget a 0))   ; works — same lexical scope
   ```

2. **Helper owns creation + returns the array** so the caller can
   bind it:

   ```phel
   (defn- build-arr []
     (let [a (php/array)]
       (loop [...] (php/aset a ...))
       a))

   (let [a (build-arr)] ...)   ; works
   ```

The render-overlay paint chain in `src/modules/io/render.phel` uses
pattern 2 and threads the returned `parts` through a sequential
`let` so every overlay's pushes accumulate. Read that for an
example.

### Destructure direction: `{:keyword local-name}`

Phel destructures map a keyword to a local in this order:

```phel
(let [{:foo a :bar b} {:foo 1 :bar 2}]
  [a b])
;; => [1 2]
```

Opposite of Clojure (`{local :keyword}`). `{:keys [foo bar]}` also
works for the common case where the local name matches the key.

If you write Clojure-style by mistake, the compiler greets you with
`Cannot destructure Phel\Lang\Keyword`.

### Lint warnings are mostly false positives

`vendor/bin/phel lint` flags two patterns as warnings that are
actually fine:

- **Unused let bindings whose RHS is referenced by a later binding.**
  Phel `let` is sequential (later bindings see earlier ones); the
  linter analyses each binding independently.
- **Threading macros not expanded.** `(-> w (foo arg) (bar))` looks
  like 1-arg calls to the linter, which emits arity-mismatch errors.

Errors do fail CI; warnings don't. If you genuinely need threading,
prefer a sequential `let` instead of `->` to keep lint quiet.

### `vendor/bin/phel test` skips your env-var contract

`composer test` exports `PHEL_DOOM_SILENT=1`. The bare
`vendor/bin/phel test` invocation does not. Always go through
composer scripts during local dev so the suite behaves the same as
in CI.

### Avoid Phel-runtime dispatch in hot loops

The render hot loop reads / writes ~7200 cells per frame at 180×40
(plus 5 shade arrays per col). Phel persistent vectors go through a
polymorphic protocol on every `(get v i)`; the cost is brutal.

Local microbench (180 elements, 100 trials each):

| op | php-array | Phel vector | ratio |
|---|---|---|---|
| read  | 0.0003 s | 0.1855 s | **682× slower** |
| write | 0.0231 s | 0.0400 s | 1.7× slower |

The render row loop would drop from 60+ fps to under 2 fps on Phel
vectors. So we keep php-array semantics for hot-loop buffers, but
hide the call shape behind tiny macros that expand at compile time
to the underlying `php/*` op:

```phel
;; src/modules/io/render.phel — defined once, used everywhere
(defmacro buf-mk  []          `(php/array))
(defmacro buf-set [b i v]     `(php/aset ~b ~i ~v))
(defmacro buf-get [b i]       `(php/aget ~b ~i))
(defmacro buf-push [b v]      `(php/array_push ~b ~v))
```

Call sites read at the Phel level — `(buf-set tops col top)` —
while compiling to `\Phel\Lang\…::aset($tops, $col, $top)` with zero
runtime overhead.

Two caveats:

- Macros are not first-class. You can't pass `buf-set` to `map` or
  similar; use them only at direct call sites.
- PHP arrays still pass by value at fn boundaries, so a helper that
  builds a buffer must RETURN it (see `compute-wall-shades`). The
  macros don't change that — they only fix the *call-site* DX.

Outside `render.phel` (and the math-only `php/sqrt`, `php/atan2`,
`php/intval`, etc. used everywhere for raw arithmetic), prefer
Phel-native data: maps, vectors, keywords. Game world, player,
enemy records, level configs, scores, and the `:moves` counter
table are all Phel-native.

`tests/modules/core/engine-test.phel` exercises the cast-frame loop
with literal grids if you want to benchmark.

## Adding a new overlay (worked example)

Say you want a kill-counter banner at top-right.

1. Write a `paint-kill-counter` in `src/modules/io/render.phel`:

   ```phel
   (defn- paint-kill-counter
     "Tiny 'kills: N' badge at top-right corner."
     [parts stats vw]
     (let [k (or (get stats :kills) 0)]
       (php/array_push parts
                       (str "\e[1;" (php/- vw 12) "H\e[97mkills: " k "\e[0m")))
     parts)   ; ← return parts; pass-by-value bites otherwise
   ```

2. Thread it into the overlay chain at the bottom of
   `frame->string`:

   ```phel
   (let [parts (paint-face-overlay parts ...)
         ;; ...
         parts (paint-kill-counter parts stats vw)
         parts (paint-pistol-hud parts stats vw vh)]
     ...)
   ```

3. Add a behavioural test in
   `tests/modules/io/render-overlay-test.phel` if the logic is
   non-trivial (most overlays don't need one — they're just paint).

4. `composer ci` to validate. Commit. Done.

## Adding a new core mechanic (worked example)

Say you want a stamina meter that drains while sprinting.

1. Add `:stamina 1.0` to `new-world` in
   `src/modules/core/state.phel`.

2. Add a `tick-stamina` pure fn in `core/physics.phel`:

   ```phel
   (defn tick-stamina
     "Drain stamina by 0.4/sec while :sprinting, recharge 0.2/sec
      otherwise. Clamped to [0, 1]."
     {:export true}
     [world ^float dt]
     (let [s' (php/max 0.0
                       (php/min 1.0
                                (php/+ (:stamina world)
                                       (if (:sprinting world)
                                         (php/* -0.4 dt)
                                         (php/* 0.2 dt)))))]
       (assoc world :stamina s')))
   ```

3. Wire into `tick-world`'s sequential `let` chain in `play.phel`.

4. Forward `:stamina` through `frame-stats` so render sees it.

5. Tests in `tests/modules/core/physics-test.phel`:

   ```phel
   (deftest test-tick-stamina-drains-while-sprinting
     (let [w (tick-stamina {:stamina 1.0 :sprinting true} 0.5)]
       (is (< (:stamina w) 1.0))))
   ```

6. Render concern (HUD bar) is a separate overlay, follow the
   pattern above.

That's the whole loop: state field → core fn → tick-world wiring →
frame-stats forwarding → render overlay. Keep effects out of the
core fn; tests stay easy.
