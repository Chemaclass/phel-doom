# Input

Raw stdin to world state. Two modules:

- `src/modules/io/input.phel`: terminal-mode setup + non-blocking byte reads
- `src/modules/glue/controls.phel`: byte interpretation into game actions

## Terminal setup

```phel
(defn init-input! []
  (php/exec "stty -icanon -echo min 0 time 0")
  (php/stream_set_blocking php/STDIN false)
  (print "\e[?1049h\e[?25l\e[?7l\e[2J\e[H"))
```

- `stty -icanon -echo min 0 time 0`: raw mode, no line buffer, no echo, return immediately.
- `stream_set_blocking false`: `fread` doesn't wait for newline.
- `\e[?1049h`: alternate screen buffer (draws disappear on exit, original contents restored).
- `\e[?25l`: hide cursor.
- `\e[?7l`: disable autowrap (long lines at right edge don't scroll buffer).
- `\e[2J\e[H`: clear + cursor home.

`restore!` undoes: `\e[?25h\e[?7h\e[?1049l` then `stty sane`.

## Reading input

```phel
(defn drain-keys []
  (let [s (php/fread php/STDIN 64)]
    (if (= s false) "" s)))
```

Up to 64 bytes from stdin as raw string. Empty string if nothing queued. Called once per frame from `game-loop`. Held keys produce multiple bytes per frame via OS auto-repeat; `refresh-from-keys` walks them.

## Arrow keys

Arrows arrive as 3-byte CSI escapes: `\e[A` up, `\e[B` down, `\e[C` right, `\e[D` left. Normalised to single-byte stand-ins:

```phel
(def arrow-escape-keys         (php/array "\e[A" "\e[B" "\e[D" "\e[C"))
(def arrow-escape-replacements (php/array "^"    "_"    "<"    ">"))
```

`(php/str_replace ...)` swaps. Byte-walk in `refresh-from-keys` treats `^` `_` `<` `>` identically to WASD.

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

Each byte refreshes its slot's counter on `:moves`. Counter is the only thing physics reads. See [state.md](state.md).

## Hold-frames trade-off

```phel
(def move-hold-frames 12)   ; ~75ms warm
(def turn-hold-frames  3)   ; ~25ms warm
```

Per byte, matching counter is set to its hold value. Each frame `apply-physics` decays by 1. Counter hits 0 = direction stops.

Two values because turn precision matters more than turn fluency (arrows aim, WASD walks). Short turn-hold stops arrow within ~25ms of release. Short move-hold keeps WASD crisp. Both rely on OS auto-repeat to keep a held key alive across the inter-byte gap.

Cost on stock terminals: walk-and-turn combos are best-effort. OS auto-repeat is single-track on macOS Terminal.app / iTerm2; pressing an arrow stops W repeating. Kitty-keyboard-protocol opt-in sketched in `glue/controls.phel` (dormant `apply-kitty-events` parser, commented out, revertible).

## Edge detection for one-shot keys

Toggles (M map, N sound, P pause) and impulses (space fire) need rising edges, not auto-repeat:

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

`game-loop` carries `prev-keys` across iterations; `rising-edges` runs each frame. `tick-world` consumes the edges map. Pure data.

`fire` is consumed by combat (`tick-shooting` only resolves hitscan when `:fire`). `handle-toggles` flips the corresponding world flag (`:show-map`, `:paused`, `:sound-on`).

## Why `glue/` not `io/`

`controls.phel` doesn't touch terminal (that's `io/input.phel`). It consumes the byte string from `drain-keys` and produces a new world. Pure transformation bridging IO + core state, hence `glue/`.

## Why `io/` for `input.phel`

Calls `stty`, sets stream blocking mode, writes ANSI escapes to stdout. Pure side effects.
