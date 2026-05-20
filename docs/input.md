# Input

Raw terminal stdin → world state mutations. Two modules cooperate:

- `src/modules/io/input.phel` — terminal-mode setup + non-blocking
  byte reads
- `src/modules/glue/controls.phel` — interprets the bytes as game
  actions

## Terminal setup

```phel
(defn init-input! []
  (php/exec "stty -icanon -echo min 0 time 0")
  (php/stream_set_blocking php/STDIN false)
  (print "\e[?1049h\e[?25l\e[?7l\e[2J\e[H"))
```

- `stty -icanon -echo min 0 time 0` — raw mode: no line buffering,
  no echo, return immediately even if no bytes are available.
- `stream_set_blocking false` — `fread` returns immediately rather
  than waiting for a newline.
- `\e[?1049h` — switch to alternate screen buffer (everything we
  draw disappears on exit, terminal contents are restored).
- `\e[?25l` — hide the cursor.
- `\e[?7l` — disable autowrap so a long line at the right edge
  doesn't scroll the buffer.
- `\e[2J\e[H` — clear + cursor home.

`restore!` undoes everything: `\e[?25h\e[?7h\e[?1049l` then
`stty sane`.

## Reading input

```phel
(defn drain-keys []
  (let [s (php/fread php/STDIN 64)]
    (if (= s false) "" s)))
```

Returns up to 64 bytes from stdin as a raw string. Empty string if
nothing is queued. Called once per frame from `game-loop`.

Holding a key produces multiple bytes per frame as the OS auto-
repeats it. The game loop iterates over those bytes in
`refresh-from-keys`.

## Arrow keys

Arrows arrive as 3-byte CSI escapes: `\e[A` (up), `\e[B` (down),
`\e[C` (right), `\e[D` (left). The interpreter normalises them to
single-byte stand-ins before processing:

```phel
(def arrow-escape-keys         (php/array "\e[A" "\e[B" "\e[D" "\e[C"))
(def arrow-escape-replacements (php/array "^"    "_"    "<"    ">"))
```

`(php/str_replace ...)` does the swap. Then the byte-walk in
`refresh-from-keys` treats `^` `_` `<` `>` identically to WASD.

## Direction-counter mapping

```phel
(def key->slot
  {"^" :fwd    "w" :fwd
   "_" :back   "s" :back
   "<" :turn-left
   ">" :turn-right
   "a" :strafe-left
   "d" :strafe-right})
```

Each byte refreshes its slot's counter on the world `:moves` map.
The counter is the only thing physics reads — see [state.md](state.md).

## Hold-frames trade-off

```phel
(def move-hold-frames 12)   ; ~75ms warm
(def turn-hold-frames  3)   ; ~25ms warm
```

Per byte, the matching counter is set to its hold value. Each frame
`apply-physics` decays it by 1. When the counter hits 0 the
direction stops.

**Why two values**: turn precision matters more than turn fluency
(player aims with arrows, walks with WASD). Short turn-hold = arrow
stops within ~25ms of release; short move-hold makes WASD feel
crisp too. Both rely on OS auto-repeat keeping a held key alive
across the inter-byte gap.

The cost on stock terminals: walk-and-turn combos are best-effort.
The OS auto-repeat is single-track on macOS Terminal.app / iTerm2 —
pressing an arrow temporarily stops repeating W. A kitty-keyboard-
protocol opt-in is sketched in the codebase (commented out;
revertible if the trade-off becomes worth it) — see the dormant
`apply-kitty-events` parser in `glue/controls.phel`.

## Edge detection for one-shot keys

Some keys are toggles (M map, N sound, P pause) or impulses (space
fire). For those we don't want the held-key auto-repeat firing
every frame — we want **just the rising edge**:

```phel
(def initial-key-snapshot {:m false :sp false :p false :n false})

(defn key-states [keys]
  {:m  (str/contains? keys "m")
   :sp (str/contains? keys " ")
   :p  (str/contains? keys "p")
   :n  (str/contains? keys "n")})

(defn rising-edges [now prev]
  {:fire         (and (:sp now) (not (:sp prev)))
   :toggle-map   (and (:m now)  (not (:m prev)))
   :toggle-pause (and (:p now)  (not (:p prev)))
   :toggle-sound (and (:n now)  (not (:n prev)))})
```

`game-loop` carries `prev-keys` across iterations and computes
`rising-edges` each frame. `tick-world` consumes the edges map; pure
data, no observability gap.

`fire` is the one used by combat (`tick-shooting` only resolves a
hitscan when `:fire` is true). Toggles by `handle-toggles` flip the
corresponding world flag (`:show-map`, `:paused`, `:sound-on`).

## Why `glue/` not `io/`

`controls.phel` doesn't touch the terminal — that's `io/input.phel`.
It consumes the byte string `drain-keys` returns and produces a new
world. Pure transformation, but it bridges the IO side and the core
state side, hence `glue/`.

## Why `io/` for `input.phel`

It calls `stty`, sets stream blocking mode, and writes ANSI escapes
to stdout. Pure side effects.
