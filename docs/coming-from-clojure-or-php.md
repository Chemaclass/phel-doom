# Coming from Clojure or PHP

Phel is a Lisp that **compiles to PHP**. If you know either language, most of phel-doom is already familiar — this maps what carries over and what bites. Read it first, then [architecture.md](architecture.md).

## 60-second model

- **It's a Lisp.** S-expressions, immutable maps/vectors/keywords, `let` / `loop` / `recur`, `->` / `->>`, `defn` / `defn-`.
- **It compiles to PHP.** Each `src/<ns>.phel` becomes `out/<ns>.php` (kebab ns → underscore path: `phel-doom.core.state` → `out/phel_doom/core/state.php`). `out/` is gitignored; `composer build` regenerates it. You can read it.
- **Layered by purity.** `core/` pure, `glue/` pure wiring, `io/` effects. See [architecture.md](architecture.md).

Conventions: kebab-case names, `defn-` private, `?` = predicate (`door?`), `!` = side effect (`render!`).

## Coming from Clojure

Same idea, same syntax:

| Carries over | Note |
|---|---|
| Immutable colls, `conj` returns new | rebind with `let`/`def`, or use `atom` |
| `let` / `loop` / `recur`, `if` / `when` / `cond` | as you'd expect |
| `->` first-arg, `->>` last-arg threading | also `some->`, `cond->` |
| `for` (builds a seq) vs `doseq` (side effects) | don't use `for` for `println` loops |
| Keywords, maps `{:k v}`, vectors `[...]`, sets | first-class |
| `defrecord` / `defprotocol` / `defmulti` | exist; game mostly uses plain maps + keywords ([RULES](../.agents/RULES.md)) |
| Only `false` / `nil` are falsy | same as Clojure |

What bites:

- **Destructure pair order is reversed.** Phel `{:key local}`; Clojure is `{local :key}`. `{:keys [x y]}` works the same in both. Clojure order throws `Cannot destructure Phel\Lang\Keyword`.
- **`def-` takes no docstring slot.** A string becomes the value. `defn-` is fine. ([contributing.md](contributing.md#phel-gotchas))
- **`recur` re-binds loop names, not a `let`-shadow of them.** Destructure into a *different* name. ([contributing.md](contributing.md#phel-gotchas))
- **Phel vectors are slow in hot loops** (polymorphic `get`). Render uses php-arrays via `buf-*` macros. ([contributing.md](contributing.md#phel-gotchas))
- **PHP arrays are a separate world** from Phel colls — see below.

## Coming from PHP

Phel compiles *to* PHP, so the runtime is yours. A fn becomes an `__invoke` class; data becomes Phel objects:

```phel
(defn new-player [x y angle]
  {:x x :y y :angle angle :pitch 0.0})   ; src/core/state.phel
```
```php
// out/phel_doom/core/state.php  (trimmed)
public function __invoke($x, $y, $angle) {
  return \Phel::map(Keyword::create("x"), $x, /* … */ Keyword::create("pitch"), 0.0);
}
```

So `{:k v}` is a `\Phel\Lang\PersistentMap`, `:k` is a `\Phel\Lang\Keyword` — **not** a PHP `array`/`string`. Bridge with interop:

| Want | Phel |
|---|---|
| Call a function | `(php/strlen s)` |
| Instance method / property | `(php/-> obj (method args))` / `(php/-> obj -prop)` |
| Static method / const | `(php/:: Class (static args))` / `Class/CONST` |
| New object | `(php/new \RuntimeException msg)` |
| Raw array read / write | `(php/aget arr i)` / `(php/aset arr i v)` |
| PHP assoc array literal | `#php {"k" "v"}` |
| Convert PHP array → Phel | `(vec arr)` / `(php-array-to-map arr)` |
| Convert Phel → PHP array | `(to-php-array v)` |

Traps:

- **`0`, `""`, `[]` are truthy.** Only `false` and `nil` are falsy. The opposite of PHP.
- **PHP arrays are pass-by-value across fn boundaries** — mutating a passed `php/array` changes a copy. Build-and-return, or keep the loop inline. ([contributing.md](contributing.md#phel-gotchas))
- **CLI args:** `*argv*`, not `php/$argv` (null under Phel).
- **Top-level side effects break `phel build`** (top level runs at compile time). Guard with `(when-not *build-mode* ...)`.
- **Hot loops drop to raw `php/*`** (`php/+`, `php/<`, `php/===`) to skip Phel's numeric dispatch. Everywhere else uses `+`, `<`, `=`. ([contributing.md](contributing.md#phel-gotchas))

## Then

Reading path in [docs/README.md](README.md): architecture → game-loop → raycaster + rendering → contributing. Syntax cheatsheet: [`.agents/quick-syntax.md`](../.agents/quick-syntax.md). Look up any fn: `composer repl` then `(doc <fn>)`.
