---
description: What belongs in core/ vs glue/ vs io/
globs: src/**,*.phel
---

# IO Boundaries

Three layers. Direction of dependency: `io/` → `glue/` → `core/`. Never the reverse.

## `src/core/`

**Pure logic.** Same input → same output, no observable effect.

- Accepts and returns plain data (maps, vectors, structs).
- May NOT: print, read terminal, query time, `rand`, mutate atoms, call `php/exit`, hit filesystem, sleep.
- MAY: do math, return new maps, throw on invalid input.
- Test target: 1:1 deterministic unit tests in `tests/core/`.

Modules: `engine`, `combat`, `enemy`, `level`, `map`, `physics`, `state`.

## `src/glue/`

**Pure wiring.** Composes core/ pieces. Stays deterministic.

- Accepts core/ outputs, returns data to be consumed by `io/`.
- Same purity rules as `core/`. The split is structural, not behavioral.
- Example: `controls` translates raw key codes into intent commands.

Modules: `controls`, plus `demo/phases` (pure phase transforms over `core/`, guarded by the same rule).

`input`, `scores`, `sound`, `savegame` and `wad` live in `io/`, not here: each is a file/terminal/device module with its pure kernel (`merge-run`, `encode`/`decode`, the WAD byte parser) colocated and unit-tested next to it. `tools/check-layers.sh` enforces the dependency DIRECTION, which is the invariant that matters; it does not police which module sits in which directory.

## `src/io/`

**Side effects allowed.** Single layer that touches the world.

- `render.phel` → terminal ANSI emit (`php/print`, escape codes, cursor, RLE).
- audio backends, file I/O for save/scores, signal handlers.
- Functions here SHOULD end in `!`.
- Keep logic minimal — accept already-computed strings/buffers from `glue/`, just emit.

## Output primitive: `print` / `println`, NEVER `php/fwrite`

`php/fwrite($fh, $s)` returns the byte count written and can be `< strlen($s)` on partial writes (full kernel terminal buffer, or EINTR from a signal under `pcntl_async_signals`). The renderer is a tight loop that does not retry partial writes; result is silently truncated frames. PHP's `print` / `echo` loop internally via the output handler chain, so they are the safe primitive.

Same applies to flush: use `php/flush`, not `php/fflush php/STDOUT` direct.

## Signal handlers

Do NOT call `php/pcntl_async_signals true` in the play loop. With async signals on, every `write(2)` / `read(2)` / `exec(3)` can return EINTR mid-call, breaking any code path that doesn't retry — including all of render. If a SIGWINCH-aware resize feature is ever needed, drive it via explicit `pcntl_signal_dispatch` at safe checkpoints, not via async dispatch.

## Smell test

If a function in `core/` calls `php/rand`, reads `php/microtime`, or prints anything → move the effect to `io/` and pass the value in instead.

If `io/` does math that determines what to draw → extract the math into `core/` or `glue/` and unit-test it.
