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

Classic FPS-style mouselook in the terminal: the `+` crosshair is pinned at screen centre, the gun fires dead-ahead, and moving the mouse turns the camera (yaw) and looks up/down (pitch). Edge fallback: push the pointer toward a screen border to keep turning past the view; a pointer left resting (even one parked near a border) never spins the camera on its own. **Additive and backward-compatible** - every keyboard binding is unchanged; the mouse is an extra input path, on by default and toggleable via the Mouse setting. With the mouse off the crosshair centres and the game plays exactly like the keyboard-only build.

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

A terminal **cannot lock, warp, or hide the pointer** on most terminals (iTerm2 included, #313): there is no portable way to recenter the OS cursor. A raw delta-only mouselook would lose the pointer the instant a fast flick carries it off the window - the terminal stops reporting and the turn freezes. So `mouse-aim` (pure) tracks the pointer's **absolute position**, computes the **delta** from the previous frame, applies that delta as a 1:1 camera turn, and adds an `edge-pan-rate` boost while you push the pointer toward an edge so you can keep turning past the view. A resting pointer adds nothing, so the unhideable OS arrow can't drift the camera on its own.

`controls/mouse-aim` parses every report in the drained byte string, **caches the latest pointer position** (`:pos`, carried forward when no report arrives), and returns `{:aim-col :aim-row :yaw :pitch :fire? :fire-held? :pos}`. The crosshair is always at screen centre (`:aim-col nil`, `:aim-row nil`); the camera turn is derived from pointer motion and edge fallback, applied **every frame**:

```
delta-col = pointer_col - prev-pointer_col    ; columns moved since last frame
delta-row = pointer_row - prev-pointer_row    ; rows moved since last frame
yaw   = ( mouse-look-gain * delta-col / fov-proj-dist(cols)      + edge-pan-rate(pointer_col, cols, mouse-yaw-rate-max) )   * sensitivity
pitch = ( -mouse-look-gain * delta-row / (pitch-cap * rows)      - edge-pan-rate(pointer_row, rows, mouse-pitch-rate-max) ) * sensitivity
```

- **Delta-driven turn (interior region).** When the pointer moves N columns in the interior (not at the window edge), the yaw turn is `mouse-look-gain * delta-col / fov-proj-dist(cols)`. The `delta-col / fov-proj-dist(cols)` part is the raw ray-per-column scale (one rendered column of turn per pointer column); a bare 1:1 reads SLOW for an FPS (you drag the pointer most of the way across the screen for a 90-degree turn), so `mouse-look-gain` (3.0) speeds the whole interior turn up to a brisk default. Same for pitch rows: `mouse-look-gain * delta-row / (pitch-cap * rows)`. Sensitivity scales both further (0.33x..3x), so the live rate is `mouse-look-gain * sensitivity` times 1:1.
- **`edge-pan-rate(p, len, max-rate)`** for a pointer cell `p` in the edge band (`mouse-edge-band-frac` = 30% of each half-axis): the outer band produces an **ease-in** ramp (the fraction into the band, squared - gentle at the band lip) reaching `max-rate` at the far edge cell, signed by which side of centre `p` is on. Returns 0 in the interior region. This ramp fires every frame while the pointer sits at or past the window border, sustaining the turn when delta reports stop.
- **Rate constants** (per frame at sensitivity 1.0): `mouse-yaw-rate-max` 0.16 rad/frame at the far left/right edge (a full 360 in ~0.65s held there), `mouse-pitch-rate-max` 0.06 pitch-fraction/frame at the top/bottom edge. Pitch is the clamped [-1, 1] fraction via `state/clamp-pitch`, so holding the pointer at the top ramps the view fully up (then saturates).
- **Pointer right of centre -> +yaw** (pan right), **left -> -yaw**. **Pointer above centre -> +pitch** (look up): rows grow DOWNWARD, so moving the pointer up (fewer rows) increases pitch.
- **Push toward an edge to keep turning.** Edge-pan fires only while the pointer is actively pushed DEEPER into the band (the per-frame delta points toward that edge, `dx * rate > 0`). A pointer held still - including the unhideable OS arrow parked near a border - or pulled back toward centre adds NO turn. So you push the mouse toward a border to swing the view past the screen edge, and let it rest to hold still; you turn far by repeated pushes (move toward the edge, reset, repeat) rather than parking it.
- **No self-drift.** Because a resting pointer never edge-pans, an OS pointer that can't be hidden (iTerm2 et al.) sitting anywhere on screen leaves the camera still - the look only responds to active mouse motion. Pulling the pointer back from a border turns cleanly via the delta with no fighting edge component.
- `dims` is the live `[rows cols]` (the `& [dims]` arg); it supplies the axis lengths for the delta turn math and the edge-pan band. Omitting it (used by any non-loop caller) yields nil deltas and zero yaw/pitch while fire intent still parses, so nothing auto-aims without knowing the viewport.
- `:pos` threads forward as the next frame's cached pointer (in `game-loop`, alongside `prev-keys`). `game-loop` seeds it to `nil` at game start and resets it to `nil` on a **resize** - a nil previous pointer produces no delta on the first frame and after resize, so the view holds steady (no jolt).

`commands/play` calls `state/reset-reticle` (the nil sentinel) every frame to keep the crosshair centred; `apply-mouse-look` folds the yaw/pitch turn into the player before the tick (so the frame renders + aims with the new heading), gated on not-paused so the camera can't drift while a menu is up.

The mouse-aim math (delta + edge-pan) stays **pure** in `glue/controls` and is unit-tested (delta scaling, edge-pan band, ease-in shape, sign, sensitivity scaling, held-at-edge, pointer re-entry, nil/-prev pointer, nil/degenerate axis). The escape re-assert that re-arms reporting lives in `io/` (next section).

### Re-arming mouse reporting (issue #288)

A focus loss / regain (or some resizes) can make a terminal **silently drop** mouse tracking, leaving mouselook dead even though the pointer is still over the window. `init-input!` only enables tracking once at startup, so `io/input.rearm-mouse!` re-asserts the `\e[?1003h\e[?1006h` escapes (plus `\e[?25l` to keep the caret hidden across the same mode flip). The play loop calls it - gated on the Mouse setting - on a resize (where tracking most often drops) or every `rearm-mouse-frames` (60th) frame, via the pure `rearm-mouse?` cadence predicate. One short idempotent escape burst; the frame budget is untouched.

### Fire

A left-button **press** (`b=0`, final `M`) sets `:fire?`, which the game loop ORs into the existing `:fire` rising edge - so a click shoots exactly like space. A held / dragged left button (`b=32`) sets `:fire-held?`, ORed into `:fire-held` so auto-fire weapons (pistol, chaingun) spray while the button is down, matching the space `:fire-held` path. Release (`m`) clears both.

### Aim point: the fixed-centre crosshair (hidden OS pointer)

The aim is the **`+` crosshair**, which is pinned at screen centre always (`paint-crosshair` draws it at row `svh/2`, col `cols/2`, exact center). The OS pointer itself stays hidden - it is *not* the aim indicator (the terminal offers no pointer warp, and a visible arrow would only confuse). Three things keep that contract:

- **Caret stays hidden.** `init-input!` hides the terminal caret once with `\e[?25l`, and `render!` re-asserts `\e[?25l` every frame. A terminal can resurface the caret on a mode flip, a resize, or when SGR mouse tracking is enabled; the per-frame re-assert (one idempotent escape) keeps it hidden for the whole session.
- **OS pointer hidden (issue #295).** The OS mouse pointer (the arrow the terminal draws) is a different cursor from the text caret, so `\e[?25l` never affected it - and enabling any-motion tracking makes xterm's default (XTSMPOINTER 1 = hide only when tracking is off) actually *show* it. `mouse-enable` now also sends XTSMPOINTER `\e[>3p` (always hide the pointer, even leaving / entering the window); `mouse-disable` restores the default with `\e[>1p`. Terminals that do not implement XTSMPOINTER ignore it (the pointer can stay visible there), and since no escape can warp or confine the pointer, this hides but cannot truly *lock* it inside the window - the delta-driven turn + edge-pan fallback above keeps a drifting pointer from ever freezing the aim.
- **Crosshair is always the aim indicator while mouse-aiming.** `paint-crosshair` reads a `:mouse` flag (the Mouse setting, threaded through `frame-stats`). When the mouse is ON, an `:off` Crosshair style still draws a minimal dot `·` so the player is never left with no aim point. With the mouse OFF, `:off` keeps hiding the idle crosshair exactly as before. The hit-marker (`✗` kill / `×` wound) overrides regardless of style or mouse state, at screen centre.

### Centred firing: the gun aims dead-ahead

The **hitscan always aims at the screen-centre crosshair**, along the player's facing direction. `core/combat.aim-angle-offset` exists but is dormant: when `:aim-col` is nil (which it always is now), the offset is 0 and the shot fires dead-ahead, byte-identical to the non-mouselook path. Every fire path (`shoot` / `pierce` / `spread-shoot` / `beam-impact`), the wall probe, and shot-direction knockback fire along `:angle`, with no column-based offset. Multi-target patterns (pistol pierce, shotgun cone, BFG splash) all centre on the screen-centre axis. The vertical aim gate (see [Combat.md](combat.md)) still applies: the enemy must be within the sprite's height at screen centre to register a hit.

### Hiding the OS mouse pointer: per-terminal reality (issue #312)

`mouse-enable` sends XTSMPOINTER `\e[>3p` ("always hide the pointer") whenever Mouse is on, but whether the OS pointer actually vanishes **while you move the mouse** is up to the terminal - an application cannot force it, and there is no portable escape that reliably hides the pointer during continuous motion.

| Terminal | OS pointer during active mouselook | Mechanism |
|----------|------------------------------------|-----------|
| `xterm` | Hidden | Honors XTSMPOINTER `\e[>3p` (we send it), so it stays hidden even while moving |
| iTerm2 | Visible | No XTSMPOINTER and no hide-pointer setting (confirmed against iTerm2's own docs) - cannot be hidden by the app |
| macOS Terminal.app | Visible | Same: no escape, no setting |
| kitty / WezTerm / Ghostty / Alacritty | Visible while moving | They hide the pointer only on idle or while *typing* (`mouse_hide_wait` / `hide_mouse_cursor_when_typing` / `mouse.hide_when_typing`); motion shows it again, so it reappears during mouselook |

So on iTerm2 - and on most popular terminals - the arrow stays visible while you actively move the mouse. This is a terminal limitation, not a game option, and it does NOT affect play: the fixed centre crosshair is the aim point and the camera turns with the mouse regardless of where the (best-effort hidden) pointer sits. For a pointer that genuinely disappears during mouselook you need a terminal that implements XTSMPOINTER `Ps=3` (xterm does) - the game already emits the escape, so nothing else is needed there. The positional steering above also means the pointer rarely has to leave the centre region in the first place, so even a visible arrow barely moves.

### Sensitivity

A `Sensitivity` percent setting (0..100, step 10, default 50) maps through `core/settings.mouse-sensitivity` to a multiplier, **geometric** around the slider midpoint (issue #275): `3 ^ ((pct - 50) / 50)`. So 50% is the neutral 1.0x (kept exact for saved-settings back-compat), 0% slows to ~0.33x (1/3) for a gentle turn, and 100% speeds up to 3.0x for a fast spin. Each end sits the same ratio away from neutral (1/3x vs 3x). `mouse-aim` applies this multiplier to both the delta turn and the edge-pan rate. At the default (50% / 1.0x) the delta turn is 1:1 with pointer motion and the far-edge yaw is `mouse-yaw-rate-max` 0.16 rad/frame (a full 360 in ~0.65s held at the edge); at 100% the delta is 3.0x faster and edge yaw is 0.48 rad/frame for a quick spin, and at 0% the delta is ~0.33x and edge yaw is ~0.053 rad/frame for slow, deliberate turning. Sensitivity also scales how quickly the edge-pan rate ramps in from the interior deadzone.

No acceleration curve: the position -> rate mapping (deadzone + ease-in to the edge max) is the only shaping. The ease-in already gives fine control near centre and a fast turn at the edge, so a second curve would add nothing testable.

### Backward-compat guard

The SGR reports share the `\e[` prefix with kitty CSI-u key events and arrow sequences, and a report body like `<32;15;10M` contains `<` (the turn-left byte) and digits. `refresh-from-keys` strips every SGR report (`mouse-report-re`) **before** the movement byte-walk, so those bytes can never be misread as a keyboard turn / weapon-select; conversely `mouse-aim` only matches the `\e[<...` SGR shape, so a kitty key / arrow / F-key never moves the cached pointer or produces a phantom fire. Both directions are regression-tested.

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
