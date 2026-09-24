---
description: Phel language conventions for source and test files
globs: src/**,tests/**,*.phel
---

# Phel Conventions

## Naming

- kebab-case for functions and variables: `cast-ray`, `frame-stats`, `enemy-aggro?`
- `defn-` for private (not exported)
- `?` suffix for predicates: `alive?`, `door?`
- `!` suffix for side-effecting: `render!`, `play-sound!`
- Namespaces match path with **dot** separator: `phel-doom.core.engine`, `phel-doom.io.render`, `phel.test`. NEVER backslash (`phel\test` is deprecated).
- Test ns: `phel-doom-tests.<layer>.<name>-test` (plural `tests`, `-test` suffix on file + ns).

## Docstrings

Every public `defn` MUST be documented. Two equivalent forms, pick by need:

1. **String docstring** (default) — a plain string after the fn name. This is
   the house style for the vast majority of public fns. Phel stores it as the
   fn's `:doc` meta, so it is REPL/`phel doc` queryable just like the map form.
   ```phel
   (defn gain-life "Bump :lives by one, capped at the soulsphere cap." [world] ...)
   ```
2. **Metadata map** — `{:doc "..." :see-also [...] :example "..."}` after the fn
   name. Use this when a fn is a subsystem entry point and benefits from
   cross-links (`:see-also`) or a worked usage (`:example`). `format.phel` and
   the central APIs (e.g. `build-world`, `cast-frame`, `tick-shooting`) use it.
   ```phel
   (defn format-duration
     {:doc "Format a second count as a clock string..."
      :see-also ["end-rows"]
      :example "(format-duration 3725) ; => \"1:02:05\""}
     [secs] ...)
   ```

Rules: `:doc` text must match current behaviour; `:see-also` only names fns that
exist and genuinely relate; `:example` must be correct (omit it rather than
guess). Do NOT churn a clear string docstring into the map form just for
uniformity - only upgrade when you are actually adding `:see-also`/`:example`.

Skip docstrings on private `defn-` unless behaviour is subtle (a short `;;`
comment is fine there).

## Comments

- `;` line comments (not `#`)
- `;;` standalone, `;` trailing after code
- `#_` to comment out a form (`#| |#` block comments were removed in phel 0.50)
- Default: NO comments. Add only when *why* is non-obvious (perf trick, hidden invariant, work around a Phel/PHP edge).

## Semantics

- `conj` over `put` for collections
- `defstruct` for data types, not PHP classes
- Threading: `->` first, `->>` last
- `for` builds sequences, `doseq` does side effects
- CLI args: `*argv*`, not `php/$argv`
- `*build-mode*` guard for top-level side effects (breaks `composer build`)

## PHP interop (phel 0.50)

- Construct with `(new \Foo arg)`, not `php/new`. `php/->` and `php/::` are
  deprecated as source too; the Clojure-style shorthands are the spelling to
  write. `php/aget`, `php/aset`, `php/apush`, `php/oset`, `php/ref` stay.
- `(php/. a b c)` is native PHP concatenation and is the hot-path spelling when
  every fragment is already a string or an int. `str` stays a runtime call
  (plus one `val-to-str` per argument) unless every non-literal argument is
  statically known to be a `string`. Do NOT swap `str` for `php/.` over a
  float, bool or nil - PHP and Phel render those differently.

## Type inference traps

The compiler infers parameter types from the body. Comparing a parameter to an
INT literal declares that parameter `int`, so a float caller is silently
truncated at the signature (and a float literal is a compile error):

```phel
(defn- sign [n] (cond (php/> n 0) 1.0 ...))     ; => int $n; (sign 0.5) is 0.0
(defn- sign [^float n] (cond (php/> n 0.0) ...)) ; => float $n
```

Compare against float literals (and tag the parameter) whenever a fractional
value can reach it. `PHEL_WARN_DEPRECATIONS=1 vendor/bin/phel test` surfaces the
truncation as a PHP "Implicit conversion from float ... loses precision" notice.

## Per-frame maps (world, enemy, moves)

- Write only what changed: `state/assoc-changed` for a value, `combat/decay-key` for a timer. A hash-map `assoc` copies the path even when the value is identical; the compare is cheaper.
- Chain single-key `assoc`s. Variadic `(assoc m :a 1 :b 2 ...)` is 2-4x slower and scales per pair; transients are slower still on the world map (docs/performance.md, "What a write costs on Phel 0.51").
- Tag map params on dispatched per-frame fns as `^map world` so `(:k world)` lowers to `->find`. Do NOT tag one-expression `^:pure` helpers that still inline: a tagged param stops the -O2 inliner. Check with `grep -c '->find(' out/phel_doom/<module>.php` after `composer build`.
- Probe before you rebuild: an indexed `loop` that exits on the first hit beats a `filterv` whose only purpose is to learn nothing was there.

## Macros

Editing `defmacro` body or quasiquote? Load [macro-hygiene.md](macro-hygiene.md) first.

## Formatting

`.phel` files auto-formatted by `.agnostic-ai/scripts/claude/format-phel.sh` on Edit/Write. Runs `vendor/bin/phel format <file>`. No manual run.

Check without writing: `vendor/bin/phel format --dry-run <file>`. CI runs `composer format-check`.
