# Contributing

Dev workflow, test conventions, and Phel quirks.

## Bootstrap

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
composer install     # installs deps + wires .githooks/pre-commit
make play            # or: composer play
```

`composer install` sets `core.hooksPath` to `.githooks/`. Every commit then runs `composer ci` (format-check, lint, layering, cycles, tests, build) before landing. Bypass with `git commit --no-verify` only in emergencies.

## Composer scripts

```bash
composer dev          # run CLI from source
composer play         # launch game
composer test         # run tests (PHEL_DOOM_SILENT=1)
composer bench        # frame/cast benchmarks (tests/bench, phel bench)
composer bench-store  # write .phel/bench-baseline.json (run on main)
composer bench-ref    # compare against it, fail past +10% (same machine)
tools/bench-ab.sh <ref> [pairs] [filter]  # interleaved A/B vs another ref (the reliable one)
tools/bench-flags.sh [passes] [filter]    # where frame time goes, by render feature
composer format       # auto-format hand-written .phel files
composer format-check # dry-run, fails CI on drift
composer format-all   # include the generated data files (rarely needed)
composer lint         # static analysis
composer check-layers # io/ -> glue/ -> core/ direction holds
composer check-cycles # no require cycles (+ the guard's own fixtures)
composer check-unused # no src/ definition that nothing references (+ fixtures)
composer check-docs   # every doc link, anchor and path claim resolves (+ fixtures)
composer check-deprecations # the suite with every deprecation channel on (+ the guard's own fixtures)
composer build        # compile to out/main.php
composer ci           # full pre-push gate
composer repl         # REPL
composer doctor       # env diagnostics
```

CI runs `composer ci` on PHP 8.5. PHP 8.4 works locally but isn't CI-tested.

`format` / `format-check` go through `tools/format-sources.sh`, which formats every hand-written `.phel` file and skips the four generated ones (`enemy_sprites_data`, `weapon_sprites_data`, `wall_texture_data`, `sound_data`). `phel format` is quadratic in the number of elements inside a single collection literal ([phel-lang#3218](https://github.com/phel-lang/phel-lang/issues/3218)), and each baked asset file is one enormous literal: `enemy_sprites_data.phel` alone took 94.7s of a 124s check, which was 70% of the whole pre-commit gate. Skipping them takes the check to 4.8s and the gate from 173s to 50s. Those files are written by `tools/bake-*.phel` and never by hand, so formatting them was pure cost. The script fails loudly if one is renamed, so the skip list cannot silently stop matching. `composer format-all` still runs the formatter over everything.

`check-unused` fails on a top-level `def` / `defn` / `defmacro` / `defstruct` under `src/` that nothing anywhere - `src/`, `tests/` or `tools/` - references as code. It exists for one specific rot: `secret-tex-offset` was a real constant with a real docstring explaining the secret-wall cue, then the texture mips landed and the call site started deriving the shift from the live mip size. The feature kept working, the constant went dead, and its docstring kept describing behaviour that now lived somewhere else - which reads as current, so it is worse than no comment. Nothing else catches that: the linter is per-form, tests only exercise what is reachable, and the build compiles dead code as happily as live code. Definitions referenced only from `tests/` (fixtures, parsers whose only caller today is their own test) are legitimate and listed by `php tools/check-unused.php --report` rather than failed. It shares its Phel source scanner with `check-cycles` (`tools/lib/phel-source.php`), so a name that survives only in a docstring, a `;` comment or a `#_` form is still dead. It sees through the things that hide a definition from a naive scan: metadata between the form and the name (`(defn ^:pure foo ...)`), the predicate `defstruct` generates (a struct reached only through `point?` is live), and the facade re-exports in `render.phel`, where the qualified half of `(def render! render/render!)` is the API being forwarded rather than a use of it. References resolve by name, not by namespace, so two files defining the same name share one verdict.


`check-docs` fails when a doc points at something that is not there: a relative markdown link to a missing file, a `#fragment` naming a heading that no longer exists, a backticked repo path (`src/...`, `tools/...`) with nothing on disk, or a backticked `composer <script>` that is neither a script nor a composer builtin. `docs/` is part of this codebase, but the parts that rot silently are the mechanical ones - nobody re-clicks every cross-reference on a rename. It found four on its first run, including a link to a `#pixel-doubling` section that had been retitled, and a path written `sound-data` for a file actually called `sound_data.phel`. Prose is deliberately not checked: an earlier cut verified every backticked kebab-case name against the definitions in `src/` and produced 97 hits, nearly all `let` bindings and map keys named in correct prose. Paths are resolved against `git ls-files`, not the filesystem: a file that exists only in your working tree - anything under the generated `.claude/` or `.agents/` trees - is missing for everyone who clones, and checking the disk would let that pass locally and fail in CI (which is exactly what happened on this guard's first run). Paths inside `docs/adr/` and `CHANGELOG.md` are exempt - those are records of what was, and legitimately name files a later commit removed - but their links and anchors are still checked.

`check-deprecations` is the gate's ONLY suite run. `composer ci` used to run `composer test` and then this - the same ~3900 tests twice, 12s warm plus 28s cold - so the warm pass was pure duplication and the gate spent 40 of its 50 seconds running one test suite two ways. `composer test` on its own is untouched and stays the fast way to run tests while working; a plain test failure inside the gate now prints the failing test names, and copies the full log to `/tmp/phel-doom-ci-failure.log`.

The compile it needs is a workaround for [phel-lang#3222](https://github.com/phel-lang/phel-lang/issues/3222): the cache key ignores the warn-deprecations flag, so a warm shared cache reports nothing and `phel test` has no `--no-cache`. It used to get its compile by deleting the shared cache, which meant a full cold recompile on every run - 25.4s of a 41s gate, paid even by a one-line doc change. It now keeps its own cache directory instead (`PHEL_CACHE_DIR`), so only what changed recompiles: **11.2s warm**, and the gate is about 27s.

Two things keep that honest. The directory name carries a hash of `composer.lock` and `phel-config.php`, so a compiler upgrade or an optimisation-level change starts a fresh cache rather than trusting yesterday's output. And a run that finds something deletes the cache before exiting - otherwise the offending file is cached with its warning already emitted and the next run is green with nothing fixed, a gate you could pass by running it twice. Failure costs the next run a cold compile, which is the right price. CI is unaffected: a fresh runner has no such directory and compiles everything. The cache handling has its own fixtures (`tools/check-deprecations-test.sh`, stubbing `phel test` so a 25-second suite does not end up inside a fixture): a clean run keeps the cache, a deprecation / a test failure / an empty run / an interrupt each drop it, a lockfile or `phel-config.php` change starts a new one, and stale ones are pruned.

`check-deprecations` re-runs the suite under `PHEL_WARN_DEPRECATIONS=1` and fails
on any notice. It exists for the quiet half: phel 0.50 infers a parameter's type
from its body, so comparing a parameter to an int literal emits `int $p` and a
fractional caller is TRUNCATED at the signature, with no error and no failing
test unless one happens to assert that exact value. PHP reports it as "Implicit
conversion from float X to int loses precision", which is invisible at the
default error level. It catches superseded interop spellings (`php/new`,
`php/->`, `php/::`, `set-var`) in the same pass. Those are raised while a
namespace COMPILES, so the script clears `.phel/cache` first: with the cache
warm from the `composer test` step just before it, nothing recompiles and a
`php/new` in the tree passes clean. See `.agnostic-ai/rules/phel.md`, "Type
inference traps".

## Looking at a frame

The suite pins bytes and hashes, which proves a frame did not CHANGE - never that it looks right. To actually see one:

```bash
tools/frame-shot.sh tools/shots/showcase.phel /tmp/showcase.png
```

`tools/shots/showcase.phel` is a deterministic frame with every on-screen feature lit at once: the message line, the first-run key hints, an enemy mid-windup (attack pose plus its `!`), a red hostile reticle, the full HUD strip with keycards and difficulty, and the minimap. Any script that writes raw ANSI to its first CLI argument works the same way.

The frame goes through `tools/frame-to-html.php`, which emulates a terminal cell grid so absolutely-positioned overlays land where they would on screen, then through headless Chrome. Without a browser installed you still get the HTML.

Worth knowing before chasing what looks like a bug: a dotted teal outline around the gun is the `:steel` floor theme showing through the sprite's transparent gaps, and the keycard glyphs may render as tofu boxes depending on the font - which is exactly what the **HUD glyphs** setting exists for.

## AI agent config (generated, not committed)

The per-tool agent config is generated, not tracked. Only the specs are.

- `.claude/` and root `AGENTS.md` come from [agnostic-ai](https://github.com/Chemaclass/agnostic-ai). Source of truth lives in `.agnostic-ai/`. Hook scripts live in `.agnostic-ai/scripts/`.
- `.agents/` comes from `vendor/bin/phel agent-install`, run automatically by `composer install`.

If you use an AI agent (Claude Code, Codex) and want its config locally, install the tool and sync:

```bash
brew install Chemaclass/tap/agnostic-ai   # one-time, needs >= 0.30.0
agnostic-ai sync                          # rebuild .claude/ + AGENTS.md from .agnostic-ai/
```

Use agnostic-ai 0.30.0 or newer: earlier versions leak an untracked README into the generated agent directory, can delete other targets' files on a scoped `sync --only`, and list the gitignore block file-by-file instead of `/.claude/`.

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
;; src/io/render/buffer.phel
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

1. Write `paint-kill-counter` in `src/io/render/paint.phel`:
   ```phel
   (defn- paint-kill-counter [parts stats vw]
     (let [k (or (get stats :kills) 0)]
       (php/array_push parts
                       (str "\e[1;" (php/- vw 12) "H kills: " k "\e[0m")))
     parts)
   ```

2. Thread into the paint chain (integrate with existing overlays in `paint.phel`).

3. Optional: test if logic is non-trivial (`tests/io/render-test.phel`).

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
