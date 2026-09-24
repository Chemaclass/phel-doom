# Input

Raw stdin to world state, in two layers:

- `src/io/input.phel`: side effects. `stty`, ANSI escapes, signal handlers, non-blocking `fread`.
- `src/glue/controls.phel`: pure. Parses the drained byte string into hold counters, rising edges and mouselook. Fully unit-tested.

The player-facing key list is in [gameplay.md](gameplay.md#controls). This page maps keys to what the parser produces:

| Keys | Parsed into |
|------|-------------|
| `W` `S` `A` `D` | `:fwd` `:back` `:strafe-left` `:strafe-right` hold slots |
| `←` `→` / `↑` `↓` | `:turn-left` `:turn-right` / `:pitch-up` `:pitch-down` hold slots |
| `Shift`+WASD, `X` | `:sprint` hold slot |
| Mouse motion, left click, wheel | `mouse-aim` yaw / pitch / fire, `wheel-weapon-step` |
| `Space` | `:fire` edge and `:fire-held` level |
| `1`-`7`, `[` `]` | `:select-weapon1`..`7`, `:prev-weapon` `:next-weapon` |
| `R` `F` `E` | `:reload`, `:action` (secret wall or switch ahead), `:about-face` |
| `M` `N` `P` `F3` | `:toggle-map`, `:toggle-sound`, `:toggle-pause`, `:toggle-debug` |
| `H` or `Esc` | `:toggle-help` |
| `F5` `F9` | `:save` `:load` (slot 1 only) |
| `Q` | `:quit-request` (asks first, see [game-loop.md](game-loop.md#quitting-and-restarting-issue-454)) |
| `Enter` or `Space` | `:confirm` (menus) |

Doors need no key: walk into them. `TAB` is not bound.

## Terminal setup

`init-input!` runs `stty -icanon -echo min 0 time 0` (raw mode, reads return at once), sets STDIN non-blocking, then prints the pure `init-escapes` string:

| Escape | Purpose |
|--------|---------|
| `\e[?1049h` | Alternate screen |
| `\e[?25l` | Hide the text caret |
| `\e[?7l` | Disable autowrap |
| `\e[2J\e[H` | Clear and home |
| `\e[>3u` | Kitty keyboard opt-in: flags `disambiguate (1)` + `report-event-types (2)` |
| `\e[?1004h` | Focus reports, always on |
| `\e[?1003h\e[?1006h\e[>3p` | `mouse-enable`, only when the Mouse setting is on |

`init-input!` takes a `mouse?` flag (default true). `init-escapes` is pure, so the gating is unit-tested without a terminal.

`restore!` undoes it in three steps:

1. `restore-prelude`: `\e[<u` (pop kitty flags), `mouse-disable` (`\e[?1003l\e[?1006l\e[>1p`), `\e[?1004l`. The mouse disable always goes out; it is harmless when the mouse was never on.
2. Flush, then `drain-stdin!` for 120 ms. This swallows the kitty release report of the quit key, which would otherwise echo onto the shell prompt.
3. `\e[?25h\e[?7h\e[?1049l`, then `stty sane`.

### Teardown and signals

The session runs inside a `try` whose `finally` calls `teardown!`: stop music, stop the sfx sidecar, `demo/reset-off!`, `restore!`. A throw still hands the terminal back cooked, then propagates.

`finally` does not run on signal death, so `install-signal-handlers!` traps SIGINT and SIGTERM:

- The handler only sets a flag. `interrupted?` dispatches pending signals and reads it. Every interruptible loop polls it once per frame and returns `:quit` through the normal teardown.
- The start-menu settings page closes itself and leaves the flag set, so the menu behind it quits next frame.
- A second signal restores the default handler and re-raises. A wedged process still dies without `kill -9`.
- Delivery is synchronous. symfony/console turns `pcntl_async_signals` on in its `Application` constructor, which would let a signal land mid-render, where writes are not retried. The installer turns it back off.
- Handlers are armed before `init-input!`, so raw mode never runs without a teardown guarantee.
- Without ext-pcntl nothing is installed.

SIGWINCH works the same way: see [game-loop.md](game-loop.md#resize-sigwinch-not-polling-issue-459).

## Reading input

`drain-keys` reads up to `drain-bytes` (512) once per frame and returns `""` when nothing is queued. 512 fits a fast mouse drag: any-motion tracking floods ~12-byte reports, and the parser drops a half-read trailing report. Held keys arrive as several auto-repeat bytes per frame, and every byte counts.

`refresh-from-keys` folds the string into `:moves` in four stages:

1. Strip SGR mouse reports and focus reports (`\e[I`, `\e[O`).
2. Kitty CSI-u key events.
3. Kitty-enhanced arrows.
4. Legacy: normalise each arrow to one byte (`^` `_` `<` `>`), then walk the rest through `refresh-move`.

Legacy arrows come as CSI (`\e[A`) or SS3 (`\eOA`). tmux and the alternate screen often switch to SS3, so both forms are normalised.

## Movement slots and hold time

`key->slot` maps the single bytes to slots. `shift-key->slot` maps capital `W` `A` `S` `D` to the same direction plus `:sprint`. The `:moves` shape is in [state.md](state.md#movement-counters-moves).

Each byte sets its slot to a hold time in seconds. Physics subtracts `dt` every frame and stops the direction at 0, so a hold lasts the same wall-clock time at any frame rate.

| Constant | Value | Why |
|----------|-------|-----|
| `move-hold-secs` | 0.30 | First byte of a press. Bridges the OS initial repeat delay (250-500 ms). |
| `move-hold-repeat-secs` | 0.15 | A byte on a still-warm slot is an auto-repeat and only has to reach the next one (#461). |
| `turn-hold-secs` | 0.05 | Turning halts within ~50 ms of release. |
| `pitch-hold-secs` | 0.05 | Looking up/down halts the same way. |
| `sprint-hold-secs` | 0.05 | No Shift-release signal exists; a longer hold shows a phantom stamina drain. |

Lesson from #461: when every byte re-armed 0.30 s, the last repeat kept the player walking ~300 ms after release, past doorways and into melee range. 0.15 s covers repeat rates down to ~7/s, below every default (macOS ~15/s at its slowest, X11 ~25/s). A crippled rate such as `xset r rate 400 5` stutters.

A kitty release event (type 3) clears the slot at once, so kitty terminals have no glide.

## Look up/down (pitch)

`↑` looks up, `↓` looks down. The arrows form a camera cluster (`←` `→` turn, `↑` `↓` look) and WASD moves. They refresh `:pitch-up` / `:pitch-down`, and physics shears the player's `:pitch` fraction, clamped to [-1, 1] with no wrap.

Every arrow encoding reaches pitch: CSI, SS3 and kitty `\e[1;..A`. The shear is a pure render offset (see [raycaster.md](raycaster.md)); `:pitch` 0 renders the same as no pitch. Pitch also drives aim: hitscan is vertical-aware (#243), so a shot must land on the drawn sprite. See the vertical aim gate in [combat.md](combat.md).

## Sprint

Translation speed x1.6; turning is not boosted. Sprint drains `:stamina` (max 100) at 30/s and regenerates at 20/s after a 0.5 s cooldown. At empty it stays locked until stamina recovers to 20. The rules live in `core/physics.phel` (`tick-stamina`, `sprinting?`).

Three paths arm `:sprint`:

1. Kitty: a press or repeat on a movement key with the Shift bit set.
2. Legacy Shift: without kitty, Shift uppercases the byte, and `W` `A` `S` `D` refresh direction and sprint together.
3. `x`: the dedicated fallback.

## Kitty keyboard protocol

With `\e[>3u` accepted, the terminal sends:

- `\e[<code>;<mods>:<event>u` for keys. The code is the lowercase codepoint (`w` = 119). Left/right arrows may come as 57351 / 57349.
- `\e[1;<mods>:<event><A|B|C|D>` for arrows, keeping the legacy suffix.

Events: 1 press, 2 repeat, 3 release; no field means press. Mods are `bits + 1`, bit 0 is Shift.

| Tier | Terminals | Stop on release |
|------|-----------|-----------------|
| Kitty events | kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5 | Instant |
| Legacy bytes | Terminal.app, GNOME Terminal, xterm | Hold-time bridge |

In tmux: `set -g extended-keys on`, `setw -g xterm-keys on`, and `set -g focus-events on`.

## One-shot actions (rising edges)

`key-states` snapshots every tracked key each frame, plus the `focus-out` report. `rising-edges` diffs it against the previous snapshot. Exceptions to the plain edge rule:

- `:fire-held` is true whenever space is in the input. Auto-fire weapons (pistol, chaingun) spray on it.
- `:confirm` is space or Enter as a rising edge, so a held fire key cannot auto-select a menu row.
- `:focus-out` is presence, not an edge: the report arrives once per focus loss.

Parsing gotchas, each one a past bug:

- **Strip CSI before the plain-byte check.** `\e[50;1:3u` (release of `2`) contains the bytes `1` and `3`. `key-pressed?` removes every CSI sequence first.
- **Kitty presses only.** The match accepts no event field or `:1`, so a held key fires once.
- **Esc is ambiguous.** Arrows and F-keys start with ESC. `esc-pressed?` strips CSI and SS3 sequences, then looks for a bare `\e`, or matches kitty's `\e[27u`.
- **Menu arrows skip releases.** `arrow-count` counts press and repeat, not release. Counting both moved the settings cursor twice per tap.
- **F-keys vary.** F3 is `\eOR` or `\e[13~` (Linux console). F5 is `\e[15~`, F9 `\e[20~`.

F5 / F9 run in the game loop, not `tick-world`, because they do file IO ([savegame.md](savegame.md)). Menus skip edges: `nav-deltas` sums arrow and WASD presses into signed `{:cursor :value}` steps, so a held key ramps a slider ([settings.md](settings.md#access)).

## Focus tracking (issue #454)

`\e[?1004h` makes the terminal report focus loss as `\e[O` and regain as `\e[I`. Focus loss pauses a live run and zeroes the hold counters, so alt-tabbing cannot leave the player gliding into an enemy. An already-paused world is left alone, so the settings sub-page stays open.

Both reports are scrubbed before the byte walk. They embed an ESC byte, and a bare ESC opens the help panel.

## Mouse look (issue #246)

FPS mouselook: the `+` crosshair stays at screen centre, the gun fires dead ahead, and mouse motion turns the camera and looks up/down. The mouse is an extra path, on by default. With the Mouse setting off, no mouse escape is sent and play is keyboard-only.

### SGR report format

`\e[?1003h` asks for any-motion tracking (reports with no button held). `\e[?1006h` selects SGR encoding, compact and safe past column 223.

A report is `\e[<b;Cx;Cy` then `M` (press or motion) or `m` (release). `Cx` `Cy` are 1-based absolute cells.

| Bits of `b` | Meaning |
|-------------|---------|
| 0-1 | Button: 0 left, 1 middle, 2 right |
| 2 / 3 / 4 | Shift / Meta / Ctrl |
| 5 (`& 32`) | Motion: a drag, or a hover under 1003 |
| 6 (`& 64`) | Wheel: 64 up, 65 down |

`b=0` + `M` is a left press, `b=32` a left drag, `b=35` a bare hover.

### Fixed-centre crosshair and delta mouselook (issue #324)

Terminals cannot lock, warp or confine the pointer (#313). A pure delta turn freezes once a flick carries the pointer off the window, because reporting stops there. So `mouse-aim` (pure) adds an edge term:

```
yaw   = ( mouse-look-gain * dx / fov-proj-dist(cols)  + edge-pan-rate(x, cols, mouse-yaw-rate-max)   * dt ) * sensitivity
pitch = ( -mouse-look-gain * dy / (pitch-cap * rows)  - edge-pan-rate(y, rows, mouse-pitch-rate-max) * dt ) * sensitivity
```

- **Delta turn.** `dx` `dy` are cells moved since last frame. `1 / fov-proj-dist(cols)` is one rendered column per pointer column, which reads slow: a full swipe is only ~80-180 columns. `mouse-look-gain` (5.0) makes one swipe cover most of a turn. No `dt`: one report already is one frame's motion.
- **Edge pan.** 0 in the centre region. In the outer `mouse-edge-band-frac` (30%) of each half-axis it ramps ease-in (fraction squared) to `mouse-yaw-rate-max` 9.6 rad/s (a full turn in ~0.65 s) or `mouse-pitch-rate-max` 3.6/s. Per second, so scaled by `dt`.
- **Ungated.** The edge pan runs every frame from the cached position. A pointer parked at or past a border keeps turning, which keeps mouselook alive after the pointer leaves the window.
- **No mid-screen drift.** A pointer resting in the centre adds nothing, so an unhideable OS pointer never spins the camera.
- **Signs.** Right of centre is +yaw. Rows grow downward, so pointer up is +pitch.

`mouse-aim` returns `{:aim-col nil :aim-row nil :yaw :pitch :fire? :fire-held? :pos}`.

- `:pos` is the last pointer cell. `game-loop` threads it forward, seeds it `nil` and resets it to `nil` on a resize. A nil previous position gives no delta, so those frames hold steady.
- Without `dims` (`[rows cols]`), yaw and pitch are 0 and fire still parses.

Each frame the loop calls `state/reset-reticle` and then `apply-mouse-look`, which folds yaw and pitch into the player before `tick-world`. It is skipped while paused, so a menu cannot drift the view. The hitscan fires along `:angle`: `combat/aim-angle-offset` returns 0 because `:aim-col` is always nil.

### Sensitivity

`core/settings.mouse-sensitivity` maps the 0-100 setting to `3 ^ ((pct - 50) / 50)` (#275): 1/3x, 1.0x (default 50%), 3.0x. It scales both terms, so far-edge yaw runs 3.2 / 9.6 / 28.8 rad/s. There is no acceleration curve: the ease-in band already gives fine control near centre.

### Fire and weapon cycling (issue #464)

A left press sets `:fire?`, ORed into `:fire`. A left press or drag sets `:fire-held?`, ORed into `:fire-held`, so auto-fire weapons spray while the button is down. Terminals only report a held button while it moves.

The wheel and `[` / `]` step through owned weapons, wrapping. `wheel-weapon-step` reads wheel reports from the same drain string; the last tick in a frame wins. Brackets are edges, so holding one steps once. Both go through `weapons/cycle-weapon` to `switch-weapon`, which keeps mag bookkeeping and the reload lockout. A number key in the same frame wins. Unowned weapons are skipped.

### Re-arming mouse reporting (issue #288)

A focus change or a resize can make a terminal drop mouse tracking. `rearm-mouse!` re-sends `\e[?25l` and `mouse-enable`. The play loop calls it, gated on the Mouse setting, on a resize and every `rearm-mouse-frames` (120) frames, about once a second.

### Caret, OS pointer and crosshair (issues #295, #312)

- **Text caret.** `\e[?25l` hides it. A mode flip, a resize or mouse tracking can bring it back, so `render!` re-sends it every frame.
- **OS pointer.** `\e[?25l` does not touch it, and xterm's default (XTSMPOINTER 1) shows it once tracking is on. `mouse-enable` sends `\e[>3p` (always hide); `mouse-disable` sends `\e[>1p`.

| Terminal | OS pointer during mouselook |
|----------|-----------------------------|
| xterm | Hidden: honours `\e[>3p` |
| iTerm2, Terminal.app | Visible: no XTSMPOINTER, no setting |
| kitty, WezTerm, Ghostty, Alacritty | Visible: hidden only when idle or typing |

This is a terminal limit. The centre crosshair stays the aim and the edge pan keeps turning. `pointer-limit-notice` checks `$TERM_PROGRAM`; for iTerm2, Apple Terminal, VS Code and Ghostty the start menu says the arrow is cosmetic.

`paint-crosshair` draws at row `svh/2`, col `cols/2`. With the mouse on, Crosshair style `off` still draws `·`. With it off, `off` hides the idle crosshair. The hit marker (`✗` kill, `×` wound) always shows.

### Keeping mouse bytes out of the keyboard path

An SGR report shares the `\e[` prefix with kitty keys and arrows, and `<32;15;10M` contains `<` (turn left) and digits. `refresh-from-keys` strips reports before the byte walk, so none reads as a key. `mouse-aim` only matches `\e[<...`, so a key never moves the pointer or fires. Both directions are regression-tested.
