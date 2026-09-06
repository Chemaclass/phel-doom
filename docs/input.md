# Input

Raw stdin to world state.

- `src/io/input.phel`: terminal setup, non-blocking reads
- `src/glue/controls.phel`: byte parsing to game actions

## Terminal setup

`init-input!` sequence: `stty -icanon -echo min 0 time 0` (raw mode, immediate return) + `stream_set_blocking(STDIN, false)` + ANSI setup:
- `\e[?1049h`: alternate screen buffer
- `\e[?25l`: hide cursor. `render!` re-asserts it every frame so the caret can't resurface behind streaming mouse reports or after a resize (see [Fixed-centre crosshair](#fixed-centre-crosshair-and-delta-mouselook-issue-324))
- `\e[?7l`: disable autowrap
- `\e[2J\e[H`: clear + home
- `\e[>3u`: kitty keyboard protocol opt-in (press/repeat/release events)
- `\e[?1003h\e[?1006h\e[>3p`: xterm mouse reporting (any-motion + SGR) plus XTSMPOINTER always-hide of the OS pointer (#295). Appended ONLY when the Mouse setting is on (see [Mouse look](#mouse-look-issue-246))

`init-input!` takes a `mouse?` flag (default true) wired to the Mouse setting. When off, the two mouse escapes are omitted and the terminal never captures the pointer. The pure builder `init-escapes` produces the exact string, so the gating is unit-tested without a terminal.

Kitty-enabled terminals (kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5) then emit structured escape sequences. Others ignore the opt-in and fall back to the legacy byte stream.

`restore!` reverses: `\e[<u\e[?1003l\e[?1006l` (pop kitty flags + disable mouse reporting; the `restore-prelude` constant) + `\e[?25h\e[?7h\e[?1049l` + `stty sane`. The mouse-disable always goes out: idempotent, harmless even if the mouse was never enabled.

The session runs inside a `try` whose `finally` calls `restore!` (with `stop-music!` + `reset-off!`), so a throw anywhere in the loop still hands the terminal back cooked. The exception is not swallowed: it propagates once teardown has run.

`finally` does not run on signal death, so SIGINT and SIGTERM are trapped instead of killing the process. `install-signal-handlers!` sets a quit flag; `interrupted?` reads it, and every interruptible loop polls it once per frame. The game loop, start menu and end screens return `:quit` and unwind through the same teardown as pressing `q`. The settings page closes itself and leaves the flag latched, so the menu behind it quits next frame. Delivery is synchronous by design: symfony/console enables `pcntl_async_signals` in its `Application` constructor, which would let a signal land mid-render where writes are not retried. So the handler turns it back off and relies on the explicit `pcntl_signal_dispatch` in `interrupted?`. Without ext-pcntl nothing is installed and the old behaviour stands.

`drain-keys` reads up to `drain-bytes` (512) per frame, sized so a fast mouse drag's burst of ~12-byte SGR reports isn't truncated mid-sequence.

## Reading input

`drain-keys` reads STDIN once per frame and returns an empty string if nothing is queued. Held keys produce multiple bytes via OS auto-repeat, and `refresh-from-keys` ingests all of them.

## Arrow keys

Arrows arrive as 3-byte CSI: `\e[A` up, `\e[B` down, `\e[C` right, `\e[D` left. Normalised to `^` `_` `>` `<` before the byte-walk. Up/down (`^`/`_`) look up/down (pitch); left/right (`<`/`>`) turn. Forward/back movement is WASD (`w`/`s`).

## Movement slots

`key->slot` maps: `w` to `:fwd`, `s` to `:back`, `a` to `:strafe-left`, `d` to `:strafe-right`, `^`/`_` (up/down arrows) to `:pitch-up`/`:pitch-down`, `<`/`>` (left/right arrows) to turn, `x` to `:sprint`.

Each byte refreshes its slot's counter on `world[:moves]`. Physics only reads the counters. See [state.md](state.md).

## Look up/down (pitch)

Hold **↑** to look up, **↓** to look down. The arrows are a camera cluster (←/→ turn, ↑/↓ look); WASD moves. They refresh the `:pitch-up` / `:pitch-down` move slots, and physics shears the player's `:pitch` fraction (clamped to [-1, 1], no wrap) through the same counter path as turning. `pitch-hold-secs` = 0.05 (~50ms, frame-rate independent), so the camera halts on release like turning rather than gliding.

Pitch reaches the arrows on every encoding: legacy CSI/SS3 (`\e[A`/`\eOA`, normalised to `^`/`_`) and kitty-enhanced (`\e[1;..A`/`B`). The shear is a pure render offset (see [raycaster.md](raycaster.md)); a level gaze (`:pitch` 0) renders identically to no pitch at all. Pitch also drives aim: hitscan is vertical-aware (issue #243), so a shot must land on the enemy's drawn sprite and aiming at floor or sky misses (see the vertical aim gate in [combat.md](combat.md)).

## Mouse look (issue #246)

Classic FPS-style mouselook in the terminal: the `+` crosshair is pinned at screen centre, the gun fires dead-ahead, and mouse motion turns the camera (yaw) and looks up/down (pitch). Edge fallback: push the pointer toward a screen border to keep turning past the view. A pointer resting in the centre region never spins the camera on its own. One parked in the outer band keeps turning the view, by design (#324).

**Additive and backward-compatible.** Every keyboard binding is unchanged. The mouse is an extra input path, on by default and toggleable via the Mouse setting. With it off the crosshair centres and the game plays exactly like the keyboard-only build.

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

### Fixed-centre crosshair and delta mouselook (issue #324)

Most terminals **cannot lock, warp, or hide the pointer** (iTerm2 included, #313); there is no portable way to recenter the OS cursor. A delta-only mouselook would lose the pointer the moment a fast flick carried it off the window: the terminal stops reporting and the turn freezes. So `mouse-aim` (pure) tracks the pointer's **absolute position**, applies the **delta** from the previous frame as a 1:1 camera turn, and adds an `edge-pan-rate` boost near an edge so you can keep turning past the view.

`controls/mouse-aim` parses every report in the drained byte string, **caches the latest pointer position** (`:pos`, carried forward when no report arrives), and returns `{:aim-col :aim-row :yaw :pitch :fire? :fire-held? :pos}`. The crosshair is always at screen centre (`:aim-col nil`, `:aim-row nil`); the turn comes from pointer motion plus edge fallback, applied **every frame**:

```
delta-col = pointer_col - prev-pointer_col    ; columns moved since last frame
delta-row = pointer_row - prev-pointer_row    ; rows moved since last frame
yaw   = ( mouse-look-gain * delta-col / fov-proj-dist(cols)      + edge-pan-rate(pointer_col, cols, mouse-yaw-rate-max) * dt )   * sensitivity
pitch = ( -mouse-look-gain * delta-row / (pitch-cap * rows)      - edge-pan-rate(pointer_row, rows, mouse-pitch-rate-max) * dt ) * sensitivity
```

- **Delta-driven turn (interior region).** Away from the window edge the yaw turn is `mouse-look-gain * delta-col / fov-proj-dist(cols)`; pitch rows are `mouse-look-gain * delta-row / (pitch-cap * rows)`. That divisor is the raw ray-per-column scale: one rendered column of turn per pointer column. Bare 1:1 reads SLOW for an FPS, since the terminal maps the pointer to a coarse cell grid and a full-width swipe is only ~80-180 pointer columns before the border stops reporting. `mouse-look-gain` (5.0) speeds that up, so one swipe covers most of a turn. Sensitivity scales further (0.33x..3x), making the live rate `mouse-look-gain * sensitivity` times 1:1. Not scaled by `dt`: one report already IS one frame's motion, however long the frame took.
- **`edge-pan-rate(p, len, max-rate)`** takes a pointer cell `p` in the edge band (`mouse-edge-band-frac` = 30% of each half-axis). The band gives an **ease-in** ramp, the fraction into it squared: gentle at the lip, reaching `max-rate` at the far edge cell, signed by which side of centre `p` is on. The interior returns 0. The ramp fires **every frame** the pointer sits in the outer band, read from the **cached** position, so it sustains the turn when no new report arrives.
- **Rate constants** (per SECOND, frame-rate independent, at sensitivity 1.0): `mouse-yaw-rate-max` 9.6 rad/s at the far left/right edge, a full 360 in ~0.65s held there; `mouse-pitch-rate-max` 3.6 pitch-fraction/s at the top/bottom edge. `mouse-aim` multiplies the edge-pan contribution by the frame's `dt`, so held-at-edge speed is the same wall-clock rate at any frame cap (0.16 rad and 0.06 pitch-fraction per frame at 60fps). Pitch clamps to [-1, 1] via `state/clamp-pitch`, so holding at the top ramps the view fully up, then saturates.
- **Pointer right of centre -> +yaw** (pan right), **left -> -yaw**. **Pointer above centre -> +pitch** (look up): rows grow DOWNWARD, so moving the pointer up (fewer rows) increases pitch.
- **Hold at an edge to keep turning (ungated, #324).** Pushed or parked, a pointer pinned at (or gone past) a border keeps swinging the view. This is load-bearing: the pointer *will* drift to the border and can leave the window, where the terminal stops reporting (#313), and a pure-delta turn would freeze there. Rest the pointer in the **centre region** to hold still.
- **No mid-screen self-drift.** The centre region (~70% of each axis) never edge-pans, so an unhideable OS pointer (Ghostty / iTerm2 et al.) resting mid-screen leaves the camera still. Only the outer band self-pans, which is the intended "keep turning past the edge" behavior.
- `dims` is the live `[rows cols]` (the `& [dims]` arg), supplying axis lengths for the delta math and the edge-pan band. Omit it, as non-loop callers do, and you get nil deltas and zero yaw/pitch while fire intent still parses. Nothing auto-aims without knowing the viewport.
- `:pos` threads forward as the next frame's cached pointer (in `game-loop`, alongside `prev-keys`). `game-loop` seeds it to `nil` at game start and resets it to `nil` on a **resize**. A nil previous pointer yields no delta, so the first frame and the frame after a resize hold steady, no jolt.

`commands/play` calls `state/reset-reticle` (the nil sentinel) every frame to keep the crosshair centred. `apply-mouse-look` folds the yaw/pitch turn into the player before the tick, so the frame renders and aims with the new heading. Gated on not-paused, so the camera can't drift while a menu is up.

The mouse-aim math (delta + edge-pan) stays **pure** in `glue/controls` and is unit-tested: delta scaling, edge-pan band, ease-in shape, sign, sensitivity scaling, held-at-edge, pointer re-entry, nil/-prev pointer, nil/degenerate axis. The escape re-assert that re-arms reporting lives in `io/` (next section).

### Re-arming mouse reporting (issue #288)

A focus loss / regain (or some resizes) can make a terminal **silently drop** mouse tracking, leaving mouselook dead with the pointer still over the window. `init-input!` enables tracking once at startup, so `io/input.rearm-mouse!` re-asserts `\e[?1003h\e[?1006h`, plus `\e[?25l` to keep the caret hidden across the same mode flip. The play loop calls it, gated on the Mouse setting, on a resize (where tracking most often drops) or every `rearm-mouse-frames` (60th) frame, via the pure `rearm-mouse?` cadence predicate. One short idempotent burst, and the frame budget is untouched.

### Fire

A left-button **press** (`b=0`, final `M`) sets `:fire?`, ORed into the `:fire` rising edge, so a click shoots exactly like space. A held or dragged left button (`b=32`) sets `:fire-held?`, ORed into `:fire-held` so auto-fire weapons (pistol, chaingun) spray while the button is down, matching the space path. Release (`m`) clears both.

### Aim point: the fixed-centre crosshair (hidden OS pointer)

The aim is the **`+` crosshair**, pinned at exact screen centre (`paint-crosshair` draws it at row `svh/2`, col `cols/2`). The OS pointer stays hidden and is *not* the aim indicator: there is no pointer warp, and a visible arrow would only confuse. Three things keep that contract:

- **Caret stays hidden.** `init-input!` hides the caret once with `\e[?25l`, and `render!` re-asserts it every frame. A terminal can resurface the caret on a mode flip, a resize, or when SGR mouse tracking is enabled. One idempotent escape per frame keeps it hidden all session.
- **OS pointer hidden (issue #295).** The OS mouse pointer (the arrow the terminal draws) is a different cursor from the text caret, so `\e[?25l` never affected it. Worse, any-motion tracking makes xterm's default (XTSMPOINTER 1 = hide only when tracking is off) *show* it. `mouse-enable` also sends XTSMPOINTER `\e[>3p` (always hide, even leaving / entering the window); `mouse-disable` restores the default with `\e[>1p`. Terminals without XTSMPOINTER ignore it and the pointer can stay visible there. No escape can warp or confine the pointer, so this hides but cannot truly *lock* it inside the window.
- **Crosshair is always the aim indicator while mouse-aiming.** `paint-crosshair` reads a `:mouse` flag (the Mouse setting, threaded through `frame-stats`). With the mouse ON, an `:off` Crosshair style still draws a minimal dot `·`, so the player is never left without an aim point. With the mouse OFF, `:off` keeps hiding the idle crosshair as before. The hit-marker (`✗` kill / `×` wound) overrides regardless of style or mouse state, at screen centre.

### Centred firing: the gun aims dead-ahead

The **hitscan always aims at the screen-centre crosshair**, along the player's facing direction. `core/combat.aim-angle-offset` exists but is dormant: `:aim-col` is always nil now, so the offset is 0 and the shot fires dead-ahead, byte-identical to the non-mouselook path. Every fire path (`shoot` / `pierce` / `spread-shoot` / `beam-impact`), the wall probe and shot-direction knockback fire along `:angle`, with no column-based offset. Multi-target patterns (pistol pierce, shotgun cone, BFG splash) all centre on the same axis. The vertical aim gate (see [Combat.md](combat.md)) still applies: the enemy must be within the sprite's height at screen centre to register a hit.

### Hiding the OS mouse pointer: per-terminal reality (issue #312)

`mouse-enable` sends XTSMPOINTER `\e[>3p` ("always hide the pointer") whenever Mouse is on. Whether the OS pointer vanishes **while you move the mouse** is up to the terminal. An application cannot force it, and no portable escape reliably hides the pointer during continuous motion.

| Terminal | OS pointer during active mouselook | Mechanism |
|----------|------------------------------------|-----------|
| `xterm` | Hidden | Honors XTSMPOINTER `\e[>3p` (we send it), so it stays hidden even while moving |
| iTerm2 | Visible | No XTSMPOINTER and no hide-pointer setting (confirmed against iTerm2's own docs) - cannot be hidden by the app |
| macOS Terminal.app | Visible | Same: no escape, no setting |
| kitty / WezTerm / Ghostty / Alacritty | Visible while moving | They hide the pointer only on idle or while *typing* (`mouse_hide_wait` / `hide_mouse_cursor_when_typing` / `mouse.hide_when_typing`); motion shows it again, so it reappears during mouselook |

So on Ghostty, iTerm2 and most popular terminals the arrow stays visible while you move the mouse, and no escape can lock or confine it to the window (#313). That is a terminal limitation, not a game option, and it does NOT break play: the centre crosshair is still the aim point, and the **ungated edge-pan** keeps the turn alive when the pointer drifts to (or leaves at) a border.

On launch the game identifies the terminal via `$TERM_PROGRAM` (`io/input.pointer-limit-notice`). On ones known unable to hide the pointer during motion (Ghostty / iTerm2 / Apple Terminal / VS Code) it shows a one-line notice: the centred `+` is the aim, the arrow is cosmetic. A pointer that genuinely disappears during mouselook needs a terminal implementing XTSMPOINTER `Ps=3`, as xterm does. The game already emits that escape.

### Sensitivity

A `Sensitivity` percent setting (0..100, step 10, default 50) maps through `core/settings.mouse-sensitivity` to a multiplier, **geometric** around the slider midpoint (issue #275): `3 ^ ((pct - 50) / 50)`. 50% is the neutral 1.0x (kept exact for saved-settings back-compat), 0% slows to ~0.33x (1/3) for a gentle turn, and 100% speeds up to 3.0x for a fast spin. Each end sits the same ratio from neutral (1/3x vs 3x). `mouse-aim` applies the multiplier to both the delta turn and the edge-pan rate.

At the default (50% / 1.0x) the delta turn is 1:1 with pointer motion and far-edge yaw is `mouse-yaw-rate-max` 9.6 rad/s. At 100% the delta is 3.0x faster and edge yaw 28.8 rad/s, a quick spin. At 0% the delta is ~0.33x and edge yaw ~3.2 rad/s, for slow deliberate turning. Sensitivity also scales how fast the edge-pan ramps in from the interior deadzone, and the edge-pan itself is **ungated** (#324).

No acceleration curve: the position -> rate mapping (deadzone + ease-in to the edge max) is the only shaping. The ease-in already gives fine control near centre and a fast turn at the edge, so a second curve would add nothing testable.

### Backward-compat guard

The SGR reports share the `\e[` prefix with kitty CSI-u key events and arrow sequences, and a body like `<32;15;10M` contains `<` (the turn-left byte) and digits. `refresh-from-keys` strips every SGR report (`mouse-report-re`) **before** the movement byte-walk, so those bytes can never read as a keyboard turn or weapon-select. Conversely `mouse-aim` only matches the `\e[<...` SGR shape, so a kitty key, arrow or F-key never moves the cached pointer or fires a phantom shot. Both directions are regression-tested.

## Sprint

Hold **SHIFT+WASD** or **`x`** to sprint. Multiplies forward/strafe speed by 1.6x and drains `:stamina` (max 100, drain 30/s). Regen 20/s after 0.5s cooldown. At empty, stays locked until stamina recovers to 20.

Three input paths merge:
1. Kitty: `\e[<code>;<mods>:<event>u` with SHIFT bit (mods & 1) arms `:sprint` on press/repeat
2. Capital-WASD: `W`/`A`/`S`/`D` (no kitty support) refresh direction + `:sprint` simultaneously
3. `x` key: dedicated fallback, maps to `:sprint` slot

Sprint slot decays with movement counters, so releasing clears it the same frame (or next frame on legacy terminals via hold-secs bridge).

## Hold-secs trade-off

Per byte, the counter is set to its hold value in seconds. Each frame physics subtracts `dt` (elapsed seconds), not a fixed count, so the hold survives the same wall-clock duration at any frame rate or cap. At 0 the direction stops.

- `move-hold-secs` = 0.30 (~300ms, frame-rate independent): bridges the OS initial-key-repeat delay (250-500ms) so a press reads as one smooth walk instead of stuttering. Paid once, on the FIRST byte of a press.
- `move-hold-repeat-secs` = 0.15 (~150ms), issue #461: a movement byte landing while its slot is still warm is an auto-repeat, so the initial delay it was bridging is already paid and it only has to reach the next repeat. Before this every byte re-armed the full 0.30s, so on a terminal without release events the last repeat kept the player walking ~300ms after they let go: past the doorway, into melee range, through the strafe meant to dodge a bolt. 0.15s covers auto-repeat rates down to ~7/s, below every default (macOS ~15/s at its slowest, X11 ~25/s); a deliberately crippled rate (`xset r rate 400 5`) would stutter. Kitty release events (event type 3) override both with an instant clear, so best-tier terminals are unaffected.
- `turn-hold-secs` = 0.05 (~50ms): quick halt for aiming.
- `pitch-hold-secs` = 0.05 (~50ms): same quick halt for look up/down (↑/↓ arrows), so the camera stops on release instead of drifting.

## Kitty keyboard protocol

When supported, `\e[>3u` opt-in makes the terminal emit structured events:
- `\e[<code>;<mods>:<event>u` (ASCII + functional keys)
- `\e[1;<mods>:<event><A|B|C|D>` (arrows, legacy suffix)

Event codes: 1 = press, 2 = repeat, 3 = release. `refresh-from-keys` parses kitty events first, then falls back to legacy normalise + byte-walk on leftover. Mods encoded as `bits + 1`; bit 0 = SHIFT.

Best-tier terminals: kitty, WezTerm, Ghostty, Alacritty >= 0.13, iTerm2 >= 3.5 (instant release).
Legacy fallback: Terminal.app, GNOME Terminal, xterm (hold-secs bridge only).

In tmux: `set -g extended-keys on` + `setw -g xterm-keys on`, and `set -g focus-events on` so the outer terminal's focus reports reach the pane (see Focus tracking below).

## One-shot actions (rising edges)

`key-states` snaps all tracked keys each frame: `m` (map), `sp` (fire), `p` (pause), `n` (sound), `e` (about-face), `f` (action/secret), `f3` (debug), `r` (reload), `h` (help), `esc` (help alias), `q` (quit request), `[` / `]` (weapon cycle), `k1-k7` (weapon select), `f5` (save), `f9` (load). It also carries `focus-out`, a terminal report rather than a key.

`rising-edges` computes deltas: `:fire` (space pressed), `:fire-held` (space held), `:toggle-map`, `:toggle-pause`, `:toggle-sound`, `:toggle-debug`, `:toggle-help` (h or esc), `:reload`, `:about-face`, `:action`, `:quit-request`, `:next-weapon` / `:prev-weapon`, `:select-weapon1-7`, `:save`, `:load`, plus `:focus-out` (presence, not an edge: the report arrives once per focus loss).

## Focus tracking (issue #454)

`init-escapes` sends `\e[?1004h` unconditionally, so the terminal reports focus loss as `\e[O` and regain as `\e[I`; `restore!` sends `\e[?1004l`. Losing focus pauses a live run and drops the movement hold counters, so alt-tabbing away cannot leave the player gliding 300 ms of held movement in front of an enemy. An already-paused world is left alone, so reading the settings sub-page is not interrupted.

Both reports are scrubbed from the drain string (`strip-focus-events`) before the movement byte-walk, the same way mouse reports are: they embed an ESC byte, and ESC opens the info menu. Terminals without the mode ignore the request; inside tmux the pane needs `focus-events on`.

## Quitting (issue #454)

`q` in a live run no longer quits. It opens the pause menu with the cursor on Quit (`arm-quit-menu`), so the confirmation is the second `q` (or Enter on that row). `q` sits one key away from `w`, and an accidental press used to end the run outright. From the pause page, menu or settings sub-page, `q` quits and persists settings. The start menu and end screens keep quitting on a single press. Restart on the pause menu asks twice for the same reason: the first select arms it (`Restart?  enter again`), and moving the cursor disarms it.

F5 / F9 fire in `game-loop` (side-effect layer), not `tick-world`, so pure tick stays effect-free. See [savegame.md](savegame.md).

Edges consumed by: `:fire` -> `tick-shooting`; `:reload` -> ammo refill; `:action` -> secrets; `:select-weapon*` -> `switch-weapon`; toggles -> `handle-toggles`.

Note: `h` and `esc` both toggle the info panel (pause-coupled).

The pause overlay (issue #203) is a two-screen state machine on the world: `:pause-screen` is `:menu` (the default on pausing) or `:settings`. On the **menu** screen, up/down `nav-deltas` `:cursor` steps move `:pause-cursor` over `pause-menu-options` (`:resume :settings :restart :quit`), and the `:confirm` rising edge (space OR Enter, issue #225) selects via the pure `step-pause-menu`. `:resume` clears `:paused`, `:settings` switches to the sub-page, and `:restart`/`:quit` stamp `:pause-action`, which `game-loop` hands back to the run lifecycle, reusing the end screen's restart/quit path.

The **settings** sub-page navigates with `nav-deltas`, not rising-edges: it sums arrow + WASD keypresses into net `{:cursor :value}` steps, so a held key ramps a slider through OS key-repeat. The same up/down + left/right nav drives every field generically by `:kind` (`:pct` sliders, `:bool` toggles, `:enum` cyclers, each `:enum` carrying its own `:choices`). The `:confirm` edge (space/Enter) or `p` backs out to the menu; left/right stay value-adjust here, so they are not select keys. See [settings.md](settings.md) for the full field list.

## Architecture

- `io/input.phel`: side effects (stty, ANSI escapes, fread).
- `glue/controls.phel`: pure byte -> world transformation. No terminal access.

## Weapon cycling (issue #464)

The scroll wheel and `[` / `]` step through the weapons you OWN, wrapping at both ends. `wheel-weapon-step` reads the same drained byte string as the aim path, for the scroll reports that path ignores (SGR bit 6; 64 up, 65 down). The last tick in a frame wins, so a fast flick lands on one weapon rather than replaying the rack. Brackets arrive as ordinary rising edges, so holding one steps once.

Both route through `weapons/cycle-weapon` -> `switch-weapon`, which keeps the mag / reserve bookkeeping and mid-reload lockout identical to pressing a slot number. An explicit number key still wins over a step in the same frame. Owned-only: stepping onto a gun you have not found would either tease you with something you cannot fire or do nothing, which reads as a dropped input.
