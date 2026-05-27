# Input

Raw stdin to world state. Two modules:

- `src/io/input.phel`: terminal-mode setup + non-blocking byte reads
- `src/glue/controls.phel`: byte interpretation into game actions

## Terminal setup

```phel
(defn init-input! []
  (php/exec "stty -icanon -echo min 0 time 0")
  (php/stream_set_blocking php/STDIN false)
  (print "\e[?1049h\e[?25l\e[?7l\e[2J\e[H\e[>3u"))
```

- `stty -icanon -echo min 0 time 0`: raw mode, no line buffer, no echo, return immediately.
- `stream_set_blocking false`: `fread` doesn't wait for newline.
- `\e[?1049h`: alternate screen buffer (draws disappear on exit, original contents restored).
- `\e[?25l`: hide cursor.
- `\e[?7l`: disable autowrap (long lines at right edge don't scroll buffer).
- `\e[2J\e[H`: clear + cursor home.
- `\e[>3u`: push kitty keyboard protocol flags (disambiguate=1 | event-types=2). Supporting terminals (kitty, WezTerm, Ghostty, Alacritty ≥ 0.13, iTerm2 ≥ 3.5) then emit press / repeat / release events. Non-supporting terminals ignore it.

`restore!` sends `\e[<u` (pop kitty flags) then `\e[?25h\e[?7h\e[?1049l` and `stty sane`.

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
   "d" :strafe-right
   "x" :sprint})
```

Each byte refreshes its slot's counter on `:moves`. Counter is the only thing physics reads. See [state.md](state.md).

## Sprint

Hold **SHIFT** (kitty terminals) or **`x`** (anywhere) to sprint. Sprint multiplies forward + strafe speed by `sprint-multiplier` (1.6×) and drains the `:stamina` pool (`max-stamina` 100, drain 30/s). Stamina regenerates at 20/s after a 0.5s post-sprint cooldown. Hitting empty latches `:sprint-blocked?` until stamina recovers to `sprint-engage-threshold` (20) - prevents stutter-sprint at zero.

Two input paths:
- **Kitty path**: `apply-kitty-events` / `apply-kitty-arrow-events` parse the `mods` field of `\e[<code>;<mods>(:<event>)?u` / `\e[1;<mods>:<event><letter>`. Mods are encoded as `bits + 1`; bit 0 = SHIFT. Press/repeat events on a movement key (WASD or arrows) with the SHIFT bit set refresh the `:sprint` slot too - so holding SHIFT+W keeps the slot warm. Release events do NOT refresh sprint (player let go).
- **Legacy path**: `key->slot` maps the plain `"x"` byte to `:sprint` so terminals without kitty (Terminal.app, basic xterm) get a working sprint key too. Under kitty, `"x"` arrives as `\e[120u` and resolves via `ascii->slot` to the same `:sprint` refresh.

The `:sprint` slot decays alongside the other movement counters in `decay-move-counters`, so sprint intent naturally evaporates the frame the player lets go.

## Hold-frames trade-off

```phel
(def move-hold-frames 18)   ; ~300ms warm
(def turn-hold-frames  3)   ; ~50ms warm
```

Per byte, matching counter is set to its hold value. Each frame `apply-physics` decays by 1. Counter hits 0 = direction stops.

`move-hold-frames` is sized to bridge the OS initial-key-repeat delay (~250-500ms on macOS/Linux). Without it the first byte arrives, motion runs for a few frames, then stalls until the OS finally starts auto-repeating, reading as a stutter on every press. The trade-off is ~300ms post-release glide on terminals without kitty release events. Kitty-protocol release events override this with an instant clear (see below).

`turn-hold-frames` is short so arrow rotation halts within ~50ms of release; turning is for aiming, not warm-up.

## Kitty keyboard protocol (instant release)

When the terminal supports the [kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/), `init-input!`'s `\e[>3u` push opts in. From then on keys arrive as escape sequences carrying explicit press / repeat / release events:

```
\e[<code>;<mods>:<event>u        ASCII keys + functional codes (CSI u)
\e[1;<mods>:<event><A|B|C|D>     arrow keys (legacy letter suffix)
```

`refresh-from-keys` parses both forms before falling through to the legacy byte path:

```phel
(let [[w1 leftover1] (apply-kitty-events       world keys)
      [w2 leftover2] (apply-kitty-arrow-events w1    leftover1)]
  ; ... legacy normalise + single-byte refresh on leftover2
  )
```

`event` codes: 1 = press, 2 = repeat, 3 = release. Press/repeat refresh the slot to its hold value; release clears the slot to 0 the same frame.

Best-tier terminals (instant release): kitty, WezTerm, Ghostty, Alacritty ≥ 0.13, iTerm2 ≥ 3.5.
Legacy fallback (hold-frames bridge): macOS Terminal.app, GNOME Terminal, xterm.

Inside tmux: add `set -g extended-keys on` and `setw -g xterm-keys on` to pass kitty events through.

## Help / Info menu (`h` or `ESC`)

Both `h` and `ESC` are aliased to the same rising-edge toggle (`:toggle-help`) in the `key-states` / `rising-edges` logic. Pressing either opens the info panel + pauses the game. ESC is a convention shortcut; `h` is the explicit mnemonic. See `control.phel`'s `esc-pressed?` for how the escape byte is parsed.

## About-face (dedicated `e` key)

`e` snaps the player 180°. Rises through `rising-edges` like the other one-shots (`:about-face`), handled in `handle-toggles` alongside pause/map/sound:

```phel
(defn- about-face [world]
  (update-in world [:player :angle] (fn [a] (php/+ a php/M_PI))))
```

Dedicated key was chosen over double-tap S so a brake-walk mid-combat never accidentally spins the camera.

## Edge detection for one-shot keys

One-shot actions (toggles, modals, weapon switch, reload) need rising edges, not auto-repeat:

```phel
(def initial-key-snapshot
  {:m false :sp false :p false :n false :e false :f false :f3 false :r false
   :h false :esc false :k1 false :k2 false :k3 false :k4 false})

;; key-states checks each tracked key via key-pressed? which handles both
;; legacy bytes ("m", " ", ...) and kitty CSI-u press codes (\e[<code>u).
;; Tracked: m sp p n e f f3 r h esc k1 k2 k3 k4.

(defn rising-edges [now prev]
  {:fire           (and (:sp now) (not (:sp prev)))
   :fire-held      (boolean (:sp now))                  ; auto-fire while held
   :toggle-map     (and (:m now)  (not (:m prev)))
   :toggle-pause   (and (:p now)  (not (:p prev)))
   :toggle-sound   (and (:n now)  (not (:n prev)))
   :toggle-debug   (and (:f3 now) (not (:f3 prev)))
   :reload         (and (:r now)  (not (:r prev)))
   :toggle-help    (and (or (:h now)  (:esc now))       ; H + ESC aliased
                        (not (or (:h prev) (:esc prev))))
   :about-face     (and (:e now)  (not (:e prev)))
   :action         (and (:f now)  (not (:f prev)))      ; reveal-secret + switch
   :select-weapon1 (and (:k1 now) (not (:k1 prev)))     ; pistol
   :select-weapon2 (and (:k2 now) (not (:k2 prev)))     ; shotgun
   :select-weapon3 (and (:k3 now) (not (:k3 prev)))     ; chaingun
   :select-weapon4 (and (:k4 now) (not (:k4 prev)))})   ; chainsaw
```

`game-loop` carries `prev-keys` across iterations; `rising-edges` runs each frame. `tick-world` consumes the edges map. Pure data.

Consumed by:
- `:fire` / `:fire-held` - `tick-shooting` (per-shot edge + auto-fire spray)
- `:reload` - `reload` (mag refill)
- `:action` - `try-reveal-secret` + `try-toggle-switch`
- `:select-weapon*` - `switch-weapon`
- `:toggle-*` / `:about-face` - `handle-toggles`

## Why `glue/` not `io/`

`controls.phel` doesn't touch terminal (that's `io/input.phel`). It consumes the byte string from `drain-keys` and produces a new world. Pure transformation bridging IO + core state, hence `glue/`.

## Why `io/` for `input.phel`

Calls `stty`, sets stream blocking mode, writes ANSI escapes to stdout. Pure side effects.
