# Contributing

Dev workflow, test conventions, and Phel quirks.

## Bootstrap

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
composer install     # installs deps + wires .githooks/pre-commit
make play            # or: composer play
```

`composer install` sets `core.hooksPath` to `.githooks/`. Every commit then runs `composer ci` (format-check + lint + test + build) before landing. Bypass with `git commit --no-verify` only in emergencies.

## Composer scripts

```bash
composer dev          # run CLI from source
composer play         # launch game
composer test         # run tests (PHEL_DOOM_SILENT=1)
composer format       # auto-format .phel files
composer format-check # dry-run, fails CI on drift
composer lint         # static analysis
composer build        # compile to out/main.php
composer ci           # full pre-push gate
composer repl         # REPL
composer doctor       # env diagnostics
```

CI runs `composer ci` on PHP 8.5. PHP 8.4 works locally but isn't CI-tested.

## AI agent config (generated, not committed)

The per-tool agent config is generated, not tracked. Only the specs are.

- `.claude/` and root `AGENTS.md` come from [agnostic-ai](https://github.com/Chemaclass/agnostic-ai). Source of truth lives in `.agnostic-ai/`. Hook scripts live in `.agnostic-ai/scripts/`.
- `.agents/` comes from `vendor/bin/phel agent-install`, run automatically by `composer install`.

If you use an AI agent (Claude Code, Codex) and want its config locally, install the tool and sync:

```bash
brew install Chemaclass/tap/agnostic-ai   # one-time, needs >= 0.29.0
agnostic-ai sync                          # rebuild .claude/ + AGENTS.md from .agnostic-ai/
```

Use agnostic-ai 0.29.0 or newer: earlier versions leak `.claude/README.md` as untracked and can delete other targets' files on a scoped `sync --only`.

This is a contributor convenience only. It is not needed to run, build, or play the game.

To change agent behavior, edit specs under `.agnostic-ai/` (never the generated files) and re-run `agnostic-ai sync`. CI gate: `agnostic-ai sync --check`.

## Test conventions

- **Assert behavior, not implementation.** Test WHAT a fn returns, not how it walks data or which shape it uses.
- **No real audio.** `composer test` sets `PHEL_DOOM_SILENT=1` (short-circuits `play-sfx!`). Always use composer script, not bare `vendor/bin/phel test`.
- **No real filesystem.** Pure halves get tested; IO wrappers don't. E.g., `merge-run` in `scores.phel` is tested; `update-scores!` is not.
- **No fakes/mocks in `core/`.** Test pure code against literal data (hand-built worlds, grids). See `tests/core/physics-test.phel`.

Add tests before or right after implementation. Keep test count accurate.

## Phel gotchas

### PHP arrays are pass-by-value across fn boundaries

```phel
;; BROKEN - mutation lost
(defn- paint-into! [arr]
  (php/aset arr 0 99))

(let [a (php/array)]
  (paint-into! a)
  (php/aget a 0))   ; => nil (copy was mutated, not original)
```

Mutating a passed array only changes the local copy. Two fixes:

1. Keep the loop **inline** in the same `let` scope:
   ```phel
   (let [a (php/array)]
     (loop [...] (php/aset a ...))
     a)   ; works
   ```

2. Helper **owns creation** and **returns** the array:
   ```phel
   (defn- build-arr []
     (let [a (php/array)]
       (loop [...] (php/aset a ...))
       a))
   (let [a (build-arr)] ...)   ; works
   ```

See `src/io/render.phel` for pattern 2 in the paint-overlay chain.

### Destructure: `{:keyword local-name}` (not Clojure-style)

```phel
(let [{:foo a :bar b} {:foo 1 :bar 2}]
  [a b])   ; => [1 2]
```

Opposite of Clojure. `{:keys [foo bar]}` works when local name matches key. Clojure-style syntax throws `Cannot destructure Phel\Lang\Keyword`.

### `recur` re-binds loop names, not let-shadows of them

A `let` inside a `loop` that destructures into a local sharing a loop-binding name silently drops the value: at the `recur` site that name resolves to the loop's ORIGINAL binding, not the shadow.

```phel
;; BROKEN - recur sends the loop's old `settings`, not the navigated one
(loop [settings s0 cursor 0]
  (let [{:keys [cursor settings]} (navigate settings cursor steps)]
    (recur settings cursor)))        ; every edit lost next iteration

;; FIX - destructure into a non-loop name, read via accessors
(loop [settings s0 cursor 0]
  (let [nav (navigate settings cursor steps)]
    (recur (:settings nav) (:cursor nav))))
```

Bit the start-menu options page (`settings-screen!`): every change applied live then reverted on the next frame.

### `def-` takes no docstring slot

`def` accepts `(def name "doc" value)`, but the private `def-` is `(def- name value)` only. Pass a docstring and it silently becomes the VALUE; the real value is dropped. Lint stays quiet, so it surfaces as a runtime type error far from the def.

```phel
;; BROKEN - bfs-steps is now the STRING, not the vector
(def- bfs-steps
  "4-connected BFS offsets."
  [[1 0] [-1 0] [0 1] [0 -1]])   ; dropped -> later (+ int bfs-steps) blows up

;; FIX - move the note to a line comment
;; 4-connected BFS offsets.
(def- bfs-steps [[1 0] [-1 0] [0 1] [0 -1]])
```

`defn-` DOES take a docstring; only `def-` is the odd one out.

### Lint warnings are often false positives

`vendor/bin/phel lint` warns on:
- **Unused let bindings referenced by later bindings.** Phel `let` is sequential; linter checks each binding independently.
- **Threading macros.** `(-> w (foo arg) (bar))` looks like 1-arg calls; emits spurious arity errors.

Errors fail CI; warnings don't. If you need threading, use sequential `let` instead to keep lint quiet.

### Avoid Phel vectors in hot loops

Phel persistent vectors use polymorphic dispatch on every `get`; render at 180×40 would drop from 60+ fps to <2 fps. We use php-arrays with compile-time macros:

```phel
;; src/io/render.phel
(defmacro buf-mk  []          `(php/array))
(defmacro buf-set [b i v]     `(php/aset ~b ~i ~v))
(defmacro buf-get [b i]       `(php/aget ~b ~i))
```

Call sites: `(buf-set tops col top)` - reads Phel, compiles to `php/aset` with zero overhead. Caveats: macros aren't first-class; php-arrays still pass-by-value at fn boundaries (must return from builders).

Outside hot loops: use Phel-native data (maps, vectors, keywords).

### Hot loops use raw `php/*` ops; everything else uses Phel wrappers

Phel's `+`, `-`, `*`, `<`, `=`, ... wrap PHP operators with `NumericOperations` dispatch for `BigInt` / `Ratio`. The overhead adds up per-cell and per-ray.

- **Hot loops** (cast-ray, compute-wall-shades, per-cell paint): `php/+`, `php/<`, `php/===` (direct, no dispatch).
- **Everything else**: `+`, `<`, `=` (idiomatic, overhead invisible).

## Example: adding an overlay

New kill-counter banner at top-right?

1. Write `paint-kill-counter` in `src/io/render.phel`:
   ```phel
   (defn- paint-kill-counter [parts stats vw]
     (let [k (or (get stats :kills) 0)]
       (php/array_push parts
                       (str "\e[1;" (php/- vw 12) "H kills: " k "\e[0m")))
     parts)
   ```

2. Thread into `frame->string`'s paint chain.

3. Optional: test if logic is non-trivial (`tests/io/render-overlay-test.phel`).

4. Run `composer ci`.

## Example: adding a core mechanic

New stamina meter that drains while sprinting?

1. Add `:stamina 1.0` to `new-world` (`src/core/state.phel`).

2. Add `tick-stamina` in `src/core/physics.phel`:
   ```phel
   (defn tick-stamina [world ^float dt]
     (let [s' (php/max 0.0 (php/min 1.0
                 (php/+ (:stamina world)
                        (if (:sprinting world) (php/* -0.4 dt) (php/* 0.2 dt)))))]
       (assoc world :stamina s')))
   ```

3. Wire into `tick-world` (`src/commands/play.phel`).

4. Forward `:stamina` through `frame-stats` to render.

5. Test in `tests/core/physics-test.phel`:
   ```phel
   (deftest test-tick-stamina-drains-while-sprinting
     (let [w (tick-stamina {:stamina 1.0 :sprinting true} 0.5)]
       (is (< (:stamina w) 1.0))))
   ```

6. Render the HUD bar as a separate overlay.

Loop: state field → core fn → tick-world wiring → frame-stats → overlay. Keep effects out of core; tests stay easy.
