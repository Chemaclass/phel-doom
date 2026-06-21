# Input

Raw stdin to world state.

- `src/io/input.phel`: terminal setup, non-blocking reads
- `src/glue/controls.phel`: byte parsing to game actions

## Terminal setup

`init-input!` sequence: `stty -icanon -echo min 0 time 0` (raw mode, immediate return) + `stream_set_blocking(STDIN, false)` + ANSI setup:
- `\e[?1049h`: alternate screen buffer
- `\e[?25l`: hide cursor (also re-asserted every frame by `render!` so the caret can't resurface mid-session behind streaming mouse reports or after a resize - see [Aim point](#aim-point-hidden-pointer-fixed-centre-crosshair))
- `\e[?7l`: disable autowrap
- `\e[2J\e[H`: clear + home
- `\e[>3u`: kitty keyboard protocol opt-in (press/repeat/release events)
- `\e[?1003h\e[?1006h\e[>3p`: xterm mouse reporting (any-motion + SGR) plus XTSMPOINTER always-hide of the OS pointer (#295), appended ONLY when the Mouse setting is on (see [Mouse look](#mouse-look-issue-246))

`init-input!` takes a `mouse?` flag (default true) wired to the Mouse setting; when off, the two mouse escapes are omitted and the terminal never captures the pointer. The pure builder `init-escapes` produces the exact string so the gating is unit-tested without touching the terminal.

Kitty-enabled terminals (kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5) then emit structured escape sequences; others ignore it and fall back to legacy byte stream.

`restore!` reverses: `\e[<u\e[?1003l\e[?1006l` (pop kitty flags + disable mouse reporting; the `restore-prelude` constant) + `\e[?25h\e[?7h\e[?1049l` + `stty sane`. The mouse-disable is always sent (idempotent / harmless even if the mouse was never enabled).

`drain-keys` reads up to `drain-bytes` (512) per frame, sized so a fast mouse drag's burst of ~12-byte SGR reports isn't truncated mid-sequence.

## Reading input

`drain-keys` reads up to `drain-bytes` (512) bytes from STDIN, returns empty string if nothing queued. Called once per frame. Held keys produce multiple bytes via OS auto-repeat; `refresh-from-keys` ingests all of them.

## Arrow keys

Arrows arrive as 3-byte CSI: `\e[A` up, `\e[B` down, `\e[C` right, `\e[D` left. Normalised to `^` `_` `>` `<` before byte-walk. Up/down (`^`/`_`) look up/down (pitch); left/right (`<`/`>`) turn. Forward/back movement is WASD (`w`/`s`).

## Movement slots

`key->slot` maps: `w` to `:fwd`, `s` to `:back`, `a` to `:strafe-left`, `d` to `:strafe-right`, `^`/`_` (up/down arrows) to `:pitch-up`/`:pitch-down`, `<`/`>` (left/right arrows) to turn, `x` to `:sprint`.

Each byte refreshes its slot's counter on `world[:moves]`. Physics only reads the counters. See [state.md](state.md).

## Look up/down (pitch)

Hold **↑** to look up, **↓** to look down. The arrow keys form a camera cluster (←/→ turn, ↑/↓ look) while WASD handles movement. They refresh the `:pitch-up` / `:pitch-down` move slots; physics shears the player's `:pitch` fraction (clamped to [-1, 1], no wrap) via the same counter path as turning. `pitch-hold-frames` = 3 (~50ms), so the camera halts quickly on release like turning rather than gliding. The up/down arrows reach pitch on every encoding: legacy CSI/SS3 (`\e[A`/`\eOA`, normalised to `^`/`_`) and kitty-enhanced (`\e[1;..A`/`B`). The shear is a pure render offset (see [raycaster.md](raycaster.md)); a level gaze (`:pitch` 0) renders identically to no pitch at all. Pitch also drives aim: hitscan is vertical-aware (issue #243), so a shot has to land on the enemy's drawn sprite and aiming at the floor / sky misses (see the vertical aim gate in [combat.md](combat.md)).

## Mouse look (issue #246)

Modern-FPS controls in the terminal: move the mouse to turn (yaw) and look up/down (pitch), left-click to fire. **Additive and backward-compatible** - every keyboard binding is unchanged; the mouse is an extra input path, on by default and toggleable via the Mouse setting.

### Enable / disable

`init-input!` (when the Mouse setting is on) emits two xterm escapes:
- `\e[?1003h`: ANY-MOTION tracking (the terminal reports the pointer even with no button held).
- `\e[?1006h`: SGR-extended encoding, so reports arrive as `\e[<b;Cx;Cy(M|m)` (compact, coordinate-safe past column 223).

`restore!` always sends the reverse `\e[?1003l\e[?1006l` (idempotent). With the setting off, `init-input!` is passed `mouse? false` and emits neither escape, so a terminal or player that dislikes mouse capture opts out cleanly.

### SGR report format

`\e[<b;Cx;Cy` then `M` (press / motion) or `m` (release). `(Cx, Cy)` are 1-based **absolute** cell coordinates. `b` is a bit-packed button + modifier code:

| bits | meaning |
|------|---------|
| 0-1  | button: 0 left, 1 middle, 2 right |
| 2 / 3 / 4 | SHIFT / META / CTRL modifier |
| 5 (`& 32`) | motion (a drag with a button held, or a bare hover under 1003) |
| 6 (`& 64`) | scroll wheel (skipped: no useful look delta) |

So `b=0` final `M` is a left press, `b=32` is a left drag (button 0 + motion), `b=35` is a bare hover (motion + low-bits 3 = no button).

### The look delta (no pointer lock)

`controls/mouse-look` (pure) parses every report in the drained byte string and returns `{:yaw :pitch :fire? :fire-held? :pos}`:
- Terminals report **absolute** cell coords with **no pointer lock and no warp**, so yaw/pitch come from the **delta between consecutive position reports**, summed across the frame. This is NOT the discrete hold-counter model the keyboard uses (turn-hold-frames etc.); it is a per-frame angular delta applied directly to `:angle` / `:pitch`.
- **Camera speed tracks pointer speed** (issue #275): the mapping is linear and clamp-free, so a fast flick (a big per-frame delta) turns fast and a slow nudge turns slow - a 2x-larger delta yields 2x the yaw at a fixed sensitivity. Nothing inside `mouse-look` or `apply-mouse-look` clamps the yaw magnitude (only `:pitch` saturates, by design, at the clamped [-1, 1] range). The proportionality is pinned by tests.
- Per-cell scales (`mouse-yaw-scale` 0.045 rad, `mouse-pitch-scale` 0.05 fraction) tune the native-FPS feel. They were bumped ~2.5x in issue #306 so the 3D camera keeps up with (and at 100% outpaces) the pointer - the earlier 0.018 / 0.02 left the camera lagging the cursor even at max sensitivity. Yaw is now sized so a brisk full-width flick (~120 cols) sweeps ~5.4 rad (~309 deg) at the neutral 1.0x sensitivity - more than a full turn per stroke before the pointer saturates at the edge. Pitch covers a useful slice of the clamped [-1, 1] range in a couple of cells of vertical travel.
- Motion RIGHT (+dx) -> +yaw; motion UP -> +pitch (rows grow DOWNWARD, so up is a decreasing y, hence the dy is negated).
- **Edge-clamp caveat**: because the coords are absolute and clamp to `1..cols` / `1..rows`, a continuous drag into a screen edge produces a **zero delta** there - the terminal equivalent of running the mouse off the pad. There is no recentering. **Edge-turn continuation** (below) is the workaround.
- `:pos` threads forward as the next frame's baseline (in `game-loop`, alongside `prev-keys`). The very first report of a session only establishes the baseline (zero delta), so the pointer's opening absolute position can't read as one giant jump.

`commands/play.apply-mouse-look` folds the delta into the player before the tick (so the frame renders + aims with the new heading), gated on not-paused so the camera can't drift while a menu is up.

### Edge-turn continuation (issue #288)

A terminal **cannot truly lock or warp the pointer** - there is no portable way to recenter the OS cursor. So instead of locking it, `mouse-look` makes the pointer rarely *need* to reach the edge: pushing it into the outer edge band keeps the camera turning on its own, like RTS edge-scroll. The player can spin a full 360 without the pointer ever leaving the terminal. This is **best-effort**, not a real pointer lock; if the player flings the pointer fully out of the window it still leaves (the re-entry guard below recovers it).

The live `[rows cols]` is threaded into `mouse-look` (the `& [dims]` arg) so it knows where the edges are. Omitting `dims` keeps the old pure-delta behaviour (used by tests / any non-loop caller).

- **The band.** Per axis, the outer band is `max(mouse-edge-margin-cells = 2, round(mouse-edge-margin-frac = 8% * len))`, capped at half the axis. On a 120-col terminal that is 10 cells each side, leaving the central ~84% as **pure delta look** - normal feel is unchanged in the centre.
- **The continuous yaw.** When the latest pointer x lands in the left/right band, an extra yaw is added **on top of** the (saturated) delta. It ramps **linearly** from 0 at the band's inner edge to `mouse-edge-turn-rate` (0.15 rad/frame, bumped ~2.5x in #306 to match the faster yaw scale) at the very edge cell, signed toward that edge (left band -> turn left, right band -> turn right). Deeper into the edge = faster turn. It is multiplied by the same Sensitivity multiplier as the delta, so the Mouse on/off + Sensitivity settings both still govern it. Yaw is the priority; pitch already clamps to [-1, 1] so top/bottom edge-continue is intentionally not added.
- **Graceful re-entry.** If a report arrives more than the re-entry threshold (Chebyshev) from the previous pointer cell - the signature of the pointer leaving the terminal and re-appearing somewhere far off - that frame **re-baselines** (zero delta, `:pos` advances to the new cell) instead of reading the gap as one giant yaw jump. Under any-motion tracking the terminal emits a report per cell crossed, so a genuine fast flick never steps that far between consecutive reports; only a true leave-and-return does. The threshold is `max(mouse-reentry-gap-cells = 256, 2 * cols)` (`reentry-gap`), so even a full-width flick on a very wide (4K / tiny-font) terminal stays under it and is read as real travel; only a true teleport crosses it.

The edge math (`edge-turn-yaw`, `edge-band-cells`, `reentry-jump?`) stays **pure** in `glue/controls` and is unit-tested (sign, depth ramp, additivity, sensitivity scaling, central-region pure-delta, re-entry reset). The escape re-assert that re-arms reporting lives in `io/` (next section).

### Re-arming mouse reporting (issue #288)

A focus loss / regain (or some resizes) can make a terminal **silently drop** mouse tracking, leaving mouselook dead even though the pointer is still over the window. `init-input!` only enables tracking once at startup, so `io/input.rearm-mouse!` re-asserts the `\e[?1003h\e[?1006h` escapes (plus `\e[?25l` to keep the caret hidden across the same mode flip). The play loop calls it - gated on the Mouse setting - on a resize (where tracking most often drops) or every `rearm-mouse-frames` (60th) frame, via the pure `rearm-mouse?` cadence predicate. One short idempotent escape burst; the frame budget is untouched.

### Fire

A left-button **press** (`b=0`, final `M`) sets `:fire?`, which the game loop ORs into the existing `:fire` rising edge - so a click shoots exactly like space. A held / dragged left button (`b=32`) sets `:fire-held?`, ORed into `:fire-held` so auto-fire weapons (pistol, chaingun) spray while the button is down, matching the space `:fire-held` path. Release (`m`) clears both.

### Aim point: hidden pointer, fixed centre crosshair

The aim is the **fixed screen-centre crosshair**, never a moving pointer (the terminal reports motion but offers no pointer warp, so a roaming pointer would not even track the aim). Two things keep that contract:

- **Caret stays hidden.** `init-input!` hides the terminal caret once with `\e[?25l`, and `render!` re-asserts `\e[?25l` every frame. A terminal can resurface the caret on a mode flip, a resize, or when SGR mouse tracking is enabled, which would leave a blinking caret racing the crosshair; the per-frame re-assert (one idempotent escape) keeps it hidden for the whole session.
- **OS pointer hidden (issue #295).** The OS mouse pointer (the arrow the terminal draws) is a different cursor from the text caret, so `\e[?25l` never affected it - and enabling any-motion tracking makes xterm's default (XTSMPOINTER 1 = hide only when tracking is off) actually *show* it. `mouse-enable` now also sends XTSMPOINTER `\e[>3p` (always hide the pointer, even leaving / entering the window); `mouse-disable` restores the default with `\e[>1p`. Terminals that do not implement XTSMPOINTER ignore it (the pointer can stay visible there), and since no escape can warp or confine the pointer, this hides but cannot truly *lock* it inside the window - the edge-turn above is what keeps you from ever needing to push it out.
- **Crosshair is always the aim indicator while mouse-aiming.** `paint-crosshair` reads a `:mouse` flag (the Mouse setting, threaded through `frame-stats`). When mouselook is ON, an `:off` Crosshair style still draws a minimal centre dot `·` so the player is never left with no aim point. With the mouse OFF, `:off` keeps hiding the idle reticle exactly as before. The hit-marker (`✗` kill / `×` wound) overrides regardless of style or mouse state.

### Hiding the OS mouse pointer: per-terminal reality (issue #312)

`mouse-enable` sends XTSMPOINTER `\e[>3p` ("always hide the pointer") whenever Mouse is on, but whether the OS pointer actually vanishes **while you move the mouse** is up to the terminal - an application cannot force it, and there is no portable escape that reliably hides the pointer during continuous motion.

| Terminal | OS pointer during active mouselook | Mechanism |
|----------|------------------------------------|-----------|
| `xterm` | Hidden | Honors XTSMPOINTER `\e[>3p` (we send it), so it stays hidden even while moving |
| iTerm2 | Visible | No XTSMPOINTER and no hide-pointer setting (confirmed against iTerm2's own docs) - cannot be hidden by the app |
| macOS Terminal.app | Visible | Same: no escape, no setting |
| kitty / WezTerm / Ghostty / Alacritty | Visible while moving | They hide the pointer only on idle or while *typing* (`mouse_hide_wait` / `hide_mouse_cursor_when_typing` / `mouse.hide_when_typing`); motion shows it again, so it reappears during mouselook |

So on iTerm2 - and on most popular terminals - the arrow stays visible while you actively move the mouse. This is a terminal limitation, not a game option, and it does NOT affect play: the fixed centre crosshair is the aim point and the camera turns with the mouse regardless of where the (best-effort hidden) pointer sits. For a pointer that genuinely disappears during mouselook you need a terminal that implements XTSMPOINTER `Ps=3` (xterm does) - the game already emits the escape, so nothing else is needed there. The edge-turn above also means you rarely need to sweep the pointer far in the first place.

### Sensitivity

A `Sensitivity` percent setting (0..100, step 10, default 50) maps through `core/settings.mouse-sensitivity` to a multiplier, **geometric** around the slider midpoint (issue #275): `3 ^ ((pct - 50) / 50)`. So 50% is the neutral 1.0x (kept exact for saved-settings back-compat), 0% slows to ~0.33x (1/3) for fine aiming, and 100% speeds up to 3.0x for fast flicks. Each end sits the same ratio away from neutral (1/3x vs 3x), giving a clearly useful slow <-> fast span instead of the old narrow 0..2x linear band (where 0% killed the look entirely and 100% only doubled it). `mouse-look` multiplies the raw delta by this multiplier, so the camera turn already tracks pointer speed (see the look-delta note above); the setting just scales that proportional response up or down. Combined with the snappy 0.045 yaw scale (bumped ~2.5x in #306), the default (50% / 1.0x) gives a responsive turn out of the box and 100% lands at 0.045 * 3.0 = 0.135 rad/cell so the camera clearly keeps up with the pointer; raise it for a faster flick, lower it for fine tracking.

No acceleration curve: the per-frame delta -> yaw mapping stays linear. A faster-than-linear accel was considered (issue #275, optional) and skipped - the geometric sensitivity span already covers the fast end (3x), terminal pointers saturate at the screen edge so very large single-frame deltas are already rare, and a second curve would break the clean, testable proportionality for marginal feel gain.

### Backward-compat guard

The SGR reports share the `\e[` prefix with kitty CSI-u key events and arrow sequences, and a report body like `<32;15;10M` contains `<` (the turn-left byte) and digits. `refresh-from-keys` strips every SGR report (`mouse-report-re`) **before** the movement byte-walk, so those bytes can never be misread as a keyboard turn / weapon-select; conversely `mouse-look` only matches the `\e[<...` SGR shape, so a kitty key / arrow / F-key never produces a look delta or a phantom fire. Both directions are regression-tested.

## Sprint

Hold **SHIFT+WASD** or **`x`** to sprint. Multiplies forward/strafe speed by 1.6x and drains `:stamina` (max 100, drain 30/s). Regen 20/s after 0.5s cooldown. At empty, stays locked until stamina recovers to 20.

Three input paths merge:
1. Kitty: `\e[<code>;<mods>:<event>u` with SHIFT bit (mods & 1) arms `:sprint` on press/repeat
2. Capital-WASD: `W`/`A`/`S`/`D` (no kitty support) refresh direction + `:sprint` simultaneously
3. `x` key: dedicated fallback, maps to `:sprint` slot

Sprint slot decays with movement counters, so releasing clears it the same frame (or next frame on legacy terminals via hold-frames bridge).

## Hold-frames trade-off

Per byte, counter is set to its hold value; each frame physics decrements by 1. At 0 direction stops.

- `move-hold-frames` = 18 (~300ms at 60 fps): bridges OS initial-key-repeat delay (250-500ms). Avoids stutter on press. Trade-off: ~300ms post-release glide on non-kitty terminals. Kitty release events (event type 3) override with instant clear.
- `turn-hold-frames` = 3 (~50ms at 60 fps): quick halt for aiming.
- `pitch-hold-frames` = 3 (~50ms at 60 fps): same quick halt for look up/down (↑/↓ arrows), so the camera stops on release instead of drifting.

## Kitty keyboard protocol

When supported, `\e[>3u` opt-in makes the terminal emit structured events:
- `\e[<code>;<mods>:<event>u` (ASCII + functional keys)
- `\e[1;<mods>:<event><A|B|C|D>` (arrows, legacy suffix)

Event codes: 1 = press, 2 = repeat, 3 = release. `refresh-from-keys` parses kitty events first, then falls back to legacy normalise + byte-walk on leftover. Mods encoded as `bits + 1`; bit 0 = SHIFT.

Best-tier terminals: kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5 (instant release).
Legacy fallback: Terminal.app, GNOME Terminal, xterm (hold-frames bridge only).

In tmux: `set -g extended-keys on` + `setw -g xterm-keys on`.

## One-shot actions (rising edges)

`key-states` snaps all tracked keys each frame: `m` (map), `sp` (fire), `p` (pause), `n` (sound), `e` (about-face), `f` (action/secret), `f3` (debug), `r` (reload), `h` (help), `esc` (help alias), `k1-k7` (weapon select), `f5` (save), `f9` (load).

`rising-edges` computes deltas: `:fire` (space pressed), `:fire-held` (space held), `:toggle-map`, `:toggle-pause`, `:toggle-sound`, `:toggle-debug`, `:toggle-help` (h or esc), `:reload`, `:about-face`, `:action`, `:select-weapon1-7`, `:save`, `:load`.

F5 / F9 fire in `game-loop` (side-effect layer), not `tick-world`, so pure tick stays effect-free. See [savegame.md](savegame.md).

Edges consumed by: `:fire` -> `tick-shooting`; `:reload` -> ammo refill; `:action` -> secrets; `:select-weapon*` -> `switch-weapon`; toggles -> `handle-toggles`.

Note: `h` and `esc` both toggle the info panel (pause-coupled).

The pause overlay (issue #203) is a two-screen state machine on the world: `:pause-screen` is `:menu` (the default on pausing) or `:settings`. On the **menu** screen the up/down `nav-deltas` `:cursor` steps move `:pause-cursor` over `pause-menu-options` (`:resume :settings :restart :quit`) and the `:confirm` rising edge (space OR Enter, issue #225) selects via the pure `step-pause-menu`: `:resume` clears `:paused`, `:settings` switches to the sub-page, `:restart`/`:quit` stamp `:pause-action` which `game-loop` hands back to the run lifecycle (reusing the same restart/quit path as the end screen). On the **settings** sub-page, navigation uses `nav-deltas` (not rising-edges): it sums arrow + WASD keypresses into net `{:cursor :value}` steps so a held key ramps a slider through OS key-repeat; the same up/down + left/right nav drives every field generically by `:kind` (`:pct` sliders, `:bool` toggles, `:enum` cyclers - each `:enum` carries its own `:choices`), and the `:confirm` edge (space/Enter) or `p` backs out to the menu (left/right stay value-adjust here, so they are not select keys). See [settings.md](settings.md) for the full field list.

## Architecture

- `io/input.phel`: side effects (stty, ANSI escapes, fread).
- `glue/controls.phel`: pure byte -> world transformation. No terminal access.
