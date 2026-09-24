# Contributing

Dev loop, gates, test conventions, and Phel quirks.

## Dev loop

```bash
git clone git@github.com:Chemaclass/phel-doom.git
cd phel-doom
composer install   # deps + .githooks/pre-commit + .agents/
composer play      # or: make play
```

PHP 8.5 is the floor, locally and in CI. Phel 0.53 requires it. `composer.lock` is gitignored, so `composer install` resolves the newest `^0.53`.

Work with `composer test`. Before a commit, the pre-commit hook runs `composer ci`, the same gate CI runs. Bypass with `git commit --no-verify` only in emergencies.

| Script | Does |
|---|---|
| `composer play` / `composer dev` | launch the game / run the CLI from source |
| `composer test` | run the suite (sets `PHEL_DOOM_SILENT=1`) |
| `composer ci` | full gate: format-check, lint, layers, cycles, unused, docs, deprecations (runs the suite), build |
| `composer format` | format hand-written `.phel` files |
| `composer format-check` | dry-run format, fails on drift |
| `composer format-all` | format everything, including generated data files |
| `composer lint` | static analysis |
| `composer build` | compile to `out/main.php` |
| `composer bench` | frame/cast benchmarks (`tests/bench`) |
| `composer bench-store` / `composer bench-ref` | save a baseline to `.phel/bench-baseline.json` / fail past +10% against it (same machine) |
| `composer repl` / `composer doctor` | REPL / environment check |

For reliable perf numbers use `tools/bench-ab.sh <ref>` (interleaved A/B against another ref) and `tools/bench-flags.sh` (frame cost per render feature). See [performance.md](performance.md).

## Gates

Every guard below is a composer script inside `composer ci`. Each ships its own fixtures (`tools/*-test.sh`), because a quietly wrong guard is worse than none. [tools/README.md](../tools/README.md) has the one-line summary of each.

**Format** (`tools/format-sources.sh`). Skips the four generated data files (`enemy_sprites_data`, `weapon_sprites_data`, `wall_texture_data`, `sound_data`): `phel format` is quadratic in the size of one collection literal ([phel-lang#3218](https://github.com/phel-lang/phel-lang/issues/3218)), and `enemy_sprites_data.phel` alone cost 95s of a 124s check. The script fails if a skipped file is renamed. Check mode also caches content hashes that passed, keyed by `composer.lock`, so unchanged files are not re-checked. Write mode never uses the cache.

**Unused** (`composer check-unused`). Fails on a top-level `def` / `defn` / `defmacro` / `defstruct` under `src/` that nothing in `src/`, `tests/` or `tools/` references as code. It catches dead constants whose docstrings still describe behaviour that moved elsewhere. Privates count too, since `composer lint` passes an unused `defn-`. Names in comments, docstrings or `#_` forms do not count. It sees through `^:pure` metadata, `defstruct` predicates and the `render.phel` re-exports. References resolve by name, not namespace, so two files defining the same name share one verdict. `php tools/check-unused.php --report` lists definitions referenced only from `tests/`, which are allowed.

**Docs** (`composer check-docs`). Fails on a relative link to a missing file, a `#fragment` with no matching heading, a backticked repo path (`src/...`, `tools/...`) that is not in `git ls-files`, or a backticked `composer <script>` that does not exist. Prose is not checked. Paths in `docs/adr/` and `CHANGELOG.md` are history and exempt, but their links are checked. Generated trees (`.claude/`, `.agents/`) are not tracked, so do not cite paths inside them.

**Deprecations** (`composer check-deprecations`). The gate's only suite run. Runs the tests with `PHEL_WARN_DEPRECATIONS=1` and fails on any notice. The notice that matters most: Phel infers a parameter's type from its body, so comparing a parameter to an int literal emits `int $p` and silently truncates a float caller ("Implicit conversion from float X to int loses precision"). See `.agnostic-ai/rules/phel.md`, "Type inference traps". A warm cache hides compile-time deprecations ([phel-lang#3222](https://github.com/phel-lang/phel-lang/issues/3222)), so the script keeps its own cache under `.phel/`, keyed by `composer.lock` and `phel-config.php`, and deletes it after any failing run. On failure it prints the failing test names and copies the log to `/tmp/phel-doom-ci-failure.log`.

## Looking at a frame

Golden tests pin bytes and hashes. They prove a frame did not change, not that it looks right. To see one:

```bash
tools/frame-shot.sh tools/shots/showcase.phel /tmp/showcase.png
```

`tools/shots/showcase.phel` renders a deterministic frame with every on-screen feature lit: message line, first-run key hints, an enemy mid-windup, a red hostile reticle, the full HUD strip, and the minimap. Any script that writes raw ANSI to its first CLI argument works the same way. `tools/frame-to-html.php` emulates the terminal cell grid, then headless Chrome takes the PNG. Without Chrome you still get the HTML.

Two things that look like bugs and are not: a dotted teal outline around the gun is the `:steel` floor theme showing through the sprite's transparent gaps, and keycard glyphs may render as tofu boxes in some fonts (the **HUD glyphs** setting exists for that).

## AI agent config (generated, not committed)

- `.claude/` and root `AGENTS.md` come from [agnostic-ai](https://github.com/Chemaclass/agnostic-ai). The source of truth is `.agnostic-ai/`.
- `.agents/` comes from `vendor/bin/phel agent-install`, run by `composer install`.

To get the Claude Code or Codex config locally:

```bash
brew install Chemaclass/tap/agnostic-ai   # needs >= 0.30.0
agnostic-ai sync                          # rebuild .claude/ + AGENTS.md
```

Older agnostic-ai versions leak files and can delete other targets' output. To change agent behaviour, edit `.agnostic-ai/` and re-run `agnostic-ai sync`. `agnostic-ai sync --check` reports drift. None of this is needed to build or play.

## Test conventions

- **Assert behaviour, not implementation.** Test what a fn returns, not how it walks data.
- **No real audio.** Use `composer test`, which sets `PHEL_DOOM_SILENT=1`. `io/sound` also mutes itself under the `phel test` runner as a safety net.
- **Pure halves first.** Test `core/` against literal data (hand-built worlds and grids, see `tests/core/physics-test.phel`). No fakes or mocks in `core/`. IO wrappers that touch disk run against an isolated temp `$HOME` (see `tests/io/scores-test.phel`).

Write the test before or right after the implementation.

## Phel gotchas

### PHP arrays are pass-by-value across fn boundaries

```phel
;; BROKEN - mutation lost
(defn- paint-into! [arr]
  (php/aset arr 0 99))

(let [a (php/array)]
  (paint-into! a)
  (php/aget a 0))   ; => nil (the copy was mutated)
```

Two fixes:

1. Keep the loop inline in the same `let` scope that owns the array.
2. Let the helper create the array and return it. Callers rebind via `let`.

The render layer uses pattern 2 throughout (`compute-wall-shades`, the `paint-*` helpers). A related trap: `php/aset` inside a `let` binding VALUE can compile to a closure and write to a copy. Mutate in statement position.

### Destructure: `{local-name :keyword}` (Clojure-style)

```phel
(let [{a :foo b :bar} {:foo 1 :bar 2}]
  [a b])   ; => [1 2]
```

Binding-first since Phel 0.51. `{:keys [foo bar]}` works when the local name matches the key. The old key-first order (`{:foo a}`) is deprecated and `composer check-deprecations` flags it.

### `recur` re-binds loop names, not let-shadows of them

A `let` inside a `loop` that destructures into a local sharing a loop-binding name drops the value: at `recur`, that name resolves to the loop's original binding.

```phel
;; BROKEN - recur sends the loop's old `settings`
(loop [settings s0 cursor 0]
  (let [{:keys [cursor settings]} (navigate settings cursor steps)]
    (recur settings cursor)))

;; FIX - destructure into a non-loop name
(loop [settings s0 cursor 0]
  (let [nav (navigate settings cursor steps)]
    (recur (:settings nav) (:cursor nav))))
```

This broke the options page once: every change applied, then reverted next frame.

### `def-` takes no docstring slot

`def` accepts `(def name "doc" value)`. The private `def-` is `(def- name value)` only. A docstring there becomes the value and the real value is dropped. Lint stays quiet. Use a `;;` comment instead. `defn-` does take a docstring.

```phel
;; BROKEN - bfs-steps is now the string
(def- bfs-steps
  "4-connected BFS offsets."
  [[1 0] [-1 0] [0 1] [0 -1]])

;; FIX
;; 4-connected BFS offsets.
(def- bfs-steps [[1 0] [-1 0] [0 1] [0 -1]])
```

### Lint warnings can be false positives

`composer lint` may warn on a `let` binding used only by a later binding, and on threading macros (`(-> w (foo arg))` reads as a 1-arg call). Errors fail CI, warnings do not.

### Avoid Phel vectors in hot loops

Phel persistent vectors dispatch polymorphically on every `get`, which is far too slow per cell. Hot paths use php-arrays through compile-time macros in `src/io/render/buffer.phel`:

```phel
(defmacro buf-mk  []      `(php/array))
(defmacro buf-set [b i v] `(php/aset ~b ~i ~v))
(defmacro buf-get [b i]   `(php/aget ~b ~i))
```

Call sites read as Phel and compile to plain array ops. Macros are not first-class, and the pass-by-value rule still applies. Outside hot loops, use Phel-native data.

### Hot loops use raw `php/*` ops; everything else uses Phel wrappers

Phel's `+`, `<`, `=` dispatch through `NumericOperations` for `BigInt` / `Ratio`. That cost adds up per ray and per cell.

- **Hot loops** (`cast-frame`, `compute-wall-shades`, per-cell paint): `php/+`, `php/<`, `php/===`.
- **Everything else**: `+`, `<`, `=`.

## Recipes

### Adding a HUD overlay

Copy the shape of `paint-save-flash` in `src/io/render/paint.phel`: take `[parts stats vw vh]`, `buf-push` an ANSI string when visible, return `parts`. Thread it into the paint chain in `frame->string` (`src/io/render/main.phel`). Any state it reads must reach `stats` through `frame-stats` (`src/commands/play.phel`).

### Adding a core mechanic

Stamina is the worked example:

1. State field: `:stamina` defaults to `max-stamina` (`src/core/state.phel`).
2. Pure step: `tick-stamina` in `src/core/physics.phel`.
3. Wiring: `tick-world` calls it (`src/commands/play.phel`).
4. Render input: `frame-stats` forwards `:stamina`.
5. Overlay: `stamina-chip` in `src/io/render/paint.phel`.
6. Test: `tests/core/physics-test.phel`.

Keep effects out of `core/` and the tests stay cheap. Run `composer ci` before you push.
