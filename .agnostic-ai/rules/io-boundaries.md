---
description: "What belongs in core/, glue/ and io/; use when adding or moving code under src"
globs: src/**
---

# IO boundaries

Dependencies run `io/` to `glue/` to `core/`, never the reverse. `tools/check-layers.sh` enforces the direction, not which module sits in which directory.

- **`core/`**: pure logic. Same input, same output. Plain data in and out. No printing, terminal reads, time, `rand`, atoms, `php/exit`, filesystem or sleep. Throwing on invalid input is fine. Unit-test 1:1 in `tests/core/`. Modules: `engine`, `combat`, `enemy`, `level`, `map`, `physics`, `state`.
- **`glue/`**: pure wiring over `core/` output, deterministic, same purity rules. Modules: `controls` (key codes to intents), `demo/phases` (pure phase transforms).
- **`io/`**: the only layer that touches the world: `render/` (ANSI, cursor, RLE), audio, file I/O, signal handlers. Functions end in `!`. Keep logic minimal; emit strings or buffers computed in `glue/`. `input`, `scores`, `sound`, `savegame` and `wad` live here, each with its pure kernel (`merge-run`, `encode`/`decode`, the WAD byte parser) colocated and unit-tested beside it.

## Output: `print` / `println`, never `php/fwrite`

`php/fwrite` can write fewer bytes than asked (full terminal buffer, or EINTR under `pcntl_async_signals`), and the render loop does not retry, so frames truncate silently. PHP `print` and `echo` loop internally. Flush with `php/flush`, not `php/fflush php/STDOUT`.

## Signals

Never call `php/pcntl_async_signals true` in the play loop: every `write(2)`, `read(2)` and `exec(3)` can then return EINTR mid-call and break code that does not retry, including all of render. For SIGWINCH resize, call `pcntl_signal_dispatch` at safe checkpoints.

## Smells

- `core/` calls `php/rand` or `php/microtime`, or prints: move the effect to `io/` and pass the value in.
- `io/` does math that decides what to draw: extract it to `core/` or `glue/` and unit-test it.
