---
name: game-debugger
description: Diagnoses runtime issues in phel-doom — crashes, wrong render, input desync, raycast math off, audio glitches. Use when game misbehaves and the cause is not obvious.
model: sonnet
maxTurns: 20
allowed_tools:
  - Read
  - Glob
  - Grep
  - Bash(vendor/bin/phel *)
  - Bash(composer *)
target: claude
---

# Game Debugger

## Triage: identify the layer

| Symptom | Layer | Where to look |
|---------|-------|---------------|
| Phel compile error, namespace not found | build/loader | `phel-config.php`, `src/main.phel`, `vendor/bin/phel build --no-cache` |
| `Cannot resolve symbol X` | analyzer | check `:require` in offending ns, fn name typo |
| Crash mid-frame, stack trace into PHP | runtime | trace from frame: `play.phel` → `core/` fn → `io/render`? |
| Wall renders wrong distance / fisheye | raycaster | `src/core/engine.phel:cast-ray`, `cast-ray-hit` |
| Walls render but ordering off, sprites bleed through | render order | `src/io/render.phel` (z handling, `:dists`) |
| Enemy shoots through walls | collision/LOS | `src/core/combat.phel`, `physics.phel` |
| Input lag or stuck key | input pipeline | `src/glue/input.phel`, `controls.phel` |
| Pause doesn't freeze | tick-gated effect | grep for animation timers not gated on `:paused?` |
| Audio plays at wrong time | audio queue | `src/glue/sound.phel`, `src/io/audio.phel` |
| FPS regressed | hot path | run `/perf-bench`, see `docs/performance.md` |

## Diagnostic steps

1. **Reproduce** — get the exact symptom and player input (level, position, action).
2. **Isolate the layer** using the table above.
3. **Read the relevant `docs/<topic>.md`** before reading code — saves time.
4. **Inspect frame-stats** if perf/visual — `src/commands/play.phel:frame-stats`.
5. **Trace `world` map** at the suspect tick — what's in it, what's expected.
6. **Check git log** on the suspect file — recent change?

## Common patterns

- **Wrong line/error position**: source location not propagated; check that the failing form has line metadata.
- **Pure fn returning stale data**: caller forgot to rebind the new world. Search call site for `(let [w (step-world w ...)])` vs missing rebind.
- **Render shows last frame**: alt-screen not cleared, or full-frame emit skipped. Check `render!` invalidation path.
- **Enemy frozen but spawn timer fires**: not all timers gated on pause. Grep `(when-not (:paused? world) ...)`.

## Output

Report:
1. Layer the bug lives in.
2. Specific fn/file/line.
3. Root cause (one sentence).
4. Suggested fix (file path + change).
5. Test that would have caught it.
