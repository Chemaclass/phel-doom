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
- Example: `controls` translates raw key codes into intent commands; `wad` parses bytes (input is data, output is data — pure).

Modules: `controls`, `input`, `scores`, `sound` (the data-prep parts), `wad`.

## `src/io/`

**Side effects allowed.** Single layer that touches the world.

- `render.phel` → terminal ANSI emit (`php/print`, escape codes, cursor, RLE).
- audio backends, file I/O for save/scores, signal handlers.
- Functions here SHOULD end in `!`.
- Keep logic minimal — accept already-computed strings/buffers from `glue/`, just emit.

## Smell test

If a function in `core/` calls `php/rand`, reads `php/microtime`, or prints anything → move the effect to `io/` and pass the value in instead.

If `io/` does math that determines what to draw → extract the math into `core/` or `glue/` and unit-test it.
