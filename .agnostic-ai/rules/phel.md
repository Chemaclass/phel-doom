---
description: "Phel language conventions for source and test files; use when writing or reviewing .phel"
globs: src/**,tests/**,tools/**
---

# Phel conventions

## Naming

- kebab-case for functions and variables: `cast-ray`, `enemy-aggro?`.
- `defn-` for private; `?` suffix for predicates (`alive?`); `!` suffix for side effects (`render!`).
- Namespaces match the path with dots: `phel-doom.core.engine`, `phel.test`. Never a backslash (`phel\test` is deprecated).
- Test namespace: `phel-doom-tests.<layer>.<name>-test`.

## Docstrings

Every public `defn` is documented, in one of two forms.

1. String docstring (default; stored as `:doc` meta, queryable via the REPL and `phel doc`):
   ```phel
   (defn gain-life "Bump :lives by one, capped at the soulsphere cap." [world] ...)
   ```
2. Metadata map, for subsystem entry points that gain from `:see-also` or `:example` (`format.phel`, `build-world`, `cast-frame`, `tick-shooting`):
   ```phel
   (defn format-duration
     {:doc "Format a second count as a clock string..."
      :see-also ["end-rows"]
      :example "(format-duration 3725) ; => \"1:02:05\""}
     [secs] ...)
   ```

`:doc` must match current behaviour, `:see-also` names only real related fns, `:example` must be correct (omit rather than guess). Upgrade a string docstring to the map form only when adding `:see-also` or `:example`. Private `defn-` needs none unless behaviour is subtle.

## Comments

- `;` line comments, `;;` standalone, `;` trailing. `#_` comments out a form (`#| |#` was removed in phel 0.50).
- Default to none. Comment only a non-obvious why: perf trick, hidden invariant, Phel or PHP edge.

## Semantics

- `conj` over `put`; `defstruct` over PHP classes; `->` threads first, `->>` last.
- `for` builds sequences, `doseq` runs side effects.
- CLI args: `*argv*`, not `php/$argv`.
- Guard top-level side effects with `*build-mode*`, or `composer build` breaks.

## PHP interop (phel 0.50)

- Construct with `(new \Foo arg)`, not `php/new`. `php/->` and `php/::` are compile errors; use the Clojure-style shorthands. `php/aget`, `php/aset`, `php/apush`, `php/oset`, `php/ref` remain.
- `(php/. a b c)` is native concatenation, the hot-path spelling when every fragment is a string or int. `str` costs a runtime call plus one `val-to-str` per argument unless every non-literal argument is statically a `string`. Never swap `str` for `php/.` over a float, bool or nil: PHP and Phel render them differently.

## Type inference trap

The compiler infers parameter types from the body. Comparing a parameter to an int literal declares it `int`, so a float caller is silently truncated (a float literal is a compile error):

```phel
(defn- sign [n] (cond (php/> n 0) 1.0 ...))     ; => int $n; (sign 0.5) is 0.0
(defn- sign [^float n] (cond (php/> n 0.0) ...)) ; => float $n
```

When a fractional value can reach the parameter, compare against float literals and tag it. `PHEL_WARN_DEPRECATIONS=1 PHEL_DOOM_SILENT=1 vendor/bin/phel test` surfaces truncation as a PHP "Implicit conversion from float ... loses precision" notice.

## Per-frame maps (world, enemy, moves)

- Skip work, not writes. On Phel 0.53 an `assoc` of the value already there returns the map itself, so a compare guard costs more than it saves (0.68 vs 0.56 us). Write the plain `assoc`; `combat/decay-key` leaves an idle timer alone.
- Variadic `(assoc m :a 1 :b 2)` and chained `assoc`s cost the same on 0.53; pick the clearer. Transients stay slower on the world map (`docs/performance.md`, "What a write costs on Phel 0.51").
- Tag map params of dispatched per-frame fns `^map world` so `(:k world)` lowers to `->find`. Do not tag one-expression `^:pure` helpers that still inline: a tag stops the -O2 inliner. Check with `grep -c '->find(' out/phel_doom/<module>.php` after `composer build`.
- Probe before rebuilding: an indexed `loop` that exits on the first hit beats a `filterv` used only to learn nothing was there.

## Macros and formatting

- Editing `defmacro` or a quasiquote: load [macro-hygiene.md](macro-hygiene.md) first.
- The `format-phel` after-edit hook runs `vendor/bin/phel format <file>`; do not run it by hand. Check only: `vendor/bin/phel format --dry-run <file>`. CI runs `composer format-check`.
