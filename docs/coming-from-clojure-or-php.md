# Coming from Clojure or PHP

Phel is a Lisp that **compiles to PHP**. If you know either language, most of phel-doom is familiar. This page maps what carries over and what bites. Read it first, then [architecture.md](architecture.md).

## 60-second model

- **It's a Lisp.** S-expressions, immutable maps/vectors/keywords, `let` / `loop` / `recur`, `->` / `->>`, `defn` / `defn-`.
- **It compiles to PHP.** Each namespace becomes a PHP file under `out/` (kebab to underscore: `phel-doom.core.state` → `out/phel_doom/core/state.php`). `composer build` regenerates it. `out/` is gitignored, and readable.
- **Layered by purity.** `core/` pure, `glue/` pure wiring, `io/` effects. See [architecture.md](architecture.md).

Conventions: kebab-case names, `defn-` private, `?` = predicate (`door?`), `!` = side effect (`render!`).

## Coming from Clojure

| Carries over | Note |
|---|---|
| Immutable colls, `conj` returns new | rebind with `let`/`def`, or use `atom` |
| `let` / `loop` / `recur`, `if` / `when` / `cond` | as expected |
| `->` first-arg, `->>` last-arg threading | also `some->`, `cond->` |
| `for` (builds a seq) vs `doseq` (side effects) | don't use `for` for `println` loops |
| Keywords, maps `{:k v}`, vectors `[...]`, sets | first-class |
| `defrecord` / `defprotocol` / `defmulti` | exist; the game uses plain maps + keywords |
| Only `false` / `nil` are falsy | same as Clojure |
| Interop: `(new C)`, `(.method obj)`, `(C/static)` | Clojure-style is the only spelling Phel accepts |

What bites:

- **Map destructuring is binding-first** (`{local :key}`), same as Clojure, since Phel 0.51. `{:keys [x y]}` works too. The old key-first order is deprecated.
- **`def-` takes no docstring slot.** A string becomes the value. `defn-` is fine.
- **`recur` re-binds loop names, not a `let`-shadow of them.** Destructure into a different name.
- **Phel vectors are slow in hot loops** (polymorphic `get`). Render uses php-arrays via `buf-*` macros.
- **PHP arrays are a separate world** from Phel colls. See below.

Details and fixes for each: [contributing.md](contributing.md#phel-gotchas).

## Coming from PHP

Phel compiles *to* PHP, so the runtime is yours. A fn becomes a class with `__invoke`. Data becomes Phel objects:

```phel
(defn new-player [x y angle]
  {:x x :y y :angle angle :pitch 0.0})   ; src/core/state.phel
```

`{:k v}` is a `\Phel\Lang\Collections\Map\PersistentMapInterface`, `:k` is a `\Phel\Lang\Keyword`. Neither is a PHP `array` or `string`. Bridge with interop:

| Want | Phel |
|---|---|
| Call a function | `(php/strlen s)` |
| Instance method / property | `(.method obj args)` / `(.-prop obj)` |
| Static method / const | `(Class/method args)` / `Class/CONST` |
| New object | `(new \RuntimeException msg)` |
| Raw array read / write | `(php/aget arr i)` / `(php/aset arr i v)` |
| PHP assoc array literal | `#php {"k" "v"}` |
| PHP array → Phel | `(vec arr)` / `(php-array-to-map arr)` |
| Phel → PHP array | `(to-array v)` |

The older `php/new`, `php/->` and `php/::` forms are rejected as source on current Phel.

Traps:

- **`0`, `""`, `[]` are truthy.** Only `false` and `nil` are falsy. The opposite of PHP.
- **PHP arrays are pass-by-value across fn boundaries.** Mutating a passed `php/array` changes a copy. Build and return, or keep the loop inline.
- **CLI args:** `*argv*`, not `php/$argv`.
- **Top-level side effects run during `phel build`.** Guard them with `(when-not *build-mode* ...)`, as `src/main.phel` does.
- **Hot loops use raw `php/*` ops** (`php/+`, `php/<`, `php/===`) to skip Phel's numeric dispatch. Everywhere else uses `+`, `<`, `=`.

## Then

Follow the reading path in [README.md](README.md). For a syntax cheatsheet, run `vendor/bin/phel agent-install claude --with-docs` and read the quick-syntax page it writes (generated, not committed). To look up any fn: `composer repl`, then `(doc <fn>)`.
