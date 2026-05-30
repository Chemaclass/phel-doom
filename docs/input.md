# Input

Raw stdin to world state.

- `src/io/input.phel`: terminal setup, non-blocking reads
- `src/glue/controls.phel`: byte parsing to game actions

## Terminal setup

`init-input!` sequence: `stty -icanon -echo min 0 time 0` (raw mode, immediate return) + `stream_set_blocking(STDIN, false)` + ANSI setup:
- `\e[?1049h`: alternate screen buffer
- `\e[?25l`: hide cursor
- `\e[?7l`: disable autowrap
- `\e[2J\e[H`: clear + home
- `\e[>3u`: kitty keyboard protocol opt-in (press/repeat/release events)

Kitty-enabled terminals (kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5) then emit structured escape sequences; others ignore it and fall back to legacy byte stream.

`restore!` reverses: `\e[<u` (pop flags) + `\e[?25h\e[?7h\e[?1049l` + `stty sane`.

## Reading input

`drain-keys` reads up to 64 bytes from STDIN, returns empty string if nothing queued. Called once per frame. Held keys produce multiple bytes via OS auto-repeat; `refresh-from-keys` ingests all of them.

## Arrow keys

Arrows arrive as 3-byte CSI: `\e[A` up, `\e[B` down, `\e[C` right, `\e[D` left. Normalised to `^` `_` `>` `<` before byte-walk so they map to direction slots identically to WASD.

## Movement slots

`key->slot` maps: `w`/`^` to `:fwd`, `s`/`_` to `:back`, `a` to `:strafe-left`, `d` to `:strafe-right`, arrows to turn, `x` to `:sprint`.

Each byte refreshes its slot's counter on `world[:moves]`. Physics only reads the counters. See [state.md](state.md).

## Sprint

Hold **SHIFT+WASD** or **`x`** to sprint. Multiplies forward/strafe speed by 1.6x and drains `:stamina` (max 100, drain 30/s). Regen 20/s after 0.5s cooldown. At empty, stays locked until stamina recovers to 20.

Three input paths merge:
1. Kitty: `\e[<code>;<mods>:<event>u` with SHIFT bit (mods & 1) arms `:sprint` on press/repeat
2. Capital-WASD: `W`/`A`/`S`/`D` (no kitty support) refresh direction + `:sprint` simultaneously
3. `x` key: dedicated fallback, maps to `:sprint` slot

Sprint slot decays with movement counters, so releasing clears it the same frame (or next frame on legacy terminals via hold-frames bridge).

## Hold-frames trade-off

Per byte, counter is set to its hold value; each frame physics decrements by 1. At 0 direction stops.

- `move-hold-frames` = 18 (~300ms): bridges OS initial-key-repeat delay (250-500ms). Avoids stutter on press. Trade-off: ~300ms post-release glide on non-kitty terminals. Kitty release events (`:event` 3) override with instant clear.
- `turn-hold-frames` = 3 (~50ms): quick halt for aiming, not movement.

## Kitty keyboard protocol

When supported, `\e[>3u` opt-in makes the terminal emit structured events:
- `\e[<code>;<mods>:<event>u` (ASCII + functional keys)
- `\e[1;<mods>:<event><A|B|C|D>` (arrows, legacy suffix)

Event codes: 1 = press, 2 = repeat, 3 = release. `refresh-from-keys` parses kitty events first (extract and clear), then falls back to legacy normalise + byte-walk on leftover.

Mods encoded as `bits + 1`; bit 0 = SHIFT.

Best-tier terminals: kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5 (instant release).
Legacy fallback: Terminal.app, GNOME Terminal, xterm (hold-frames only).

In tmux: `set -g extended-keys on` + `setw -g xterm-keys on`.

## One-shot actions (rising edges)

`key-states` snaps all tracked keys each frame: `m` (map), `sp` (fire), `p` (pause), `n` (sound), `e` (about-face), `f` (action/secret), `f3` (debug), `r` (reload), `h` (help), `esc` (help alias), `k1-k5` (weapon select), `f5` (save), `f9` (load), and the four arrows (`up` / `down` / `left` / `right`) for menu navigation.

`rising-edges` computes deltas: `:fire` (space pressed), `:fire-held` (space held), `:toggle-map`, `:toggle-pause`, `:toggle-sound`, `:toggle-debug`, `:toggle-help` (h or esc), `:reload`, `:about-face`, `:action`, `:select-weapon1-5`, `:save`, `:load`, and `:nav-up` / `:nav-down` / `:nav-left` / `:nav-right`.

F5 / F9 fire in `game-loop` (side-effect layer), not `tick-world`, so pure tick stays effect-free. See [savegame.md](savegame.md).

Edges consumed by: `:fire` -> `tick-shooting`; `:reload` -> ammo refill; `:action` -> secrets; `:select-weapon*` -> `switch-weapon`; toggles -> `handle-toggles`.

Note: `h` and `esc` are aliased to `:toggle-help` (pause-coupled info panel).

The settings page (see [settings.md](settings.md)) is the pause overlay: while `:paused` (and not in the `h` info panel) the four nav edges drive cursor + value navigation. The arrow edges are read as rising-edge one-shots there (one move per press), distinct from the held-counter movement path.

## Architecture

- `io/input.phel`: side effects (stty, ANSI escapes, fread).
- `glue/controls.phel`: pure byte -> world transformation. No terminal access.
