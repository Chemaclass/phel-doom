# WAD parser

`src/modules/io/wad.phel`. Parses the DOOM .wad file format. Not yet
wired into the gameplay (the active renderer uses procedurally-
generated grids, not WAD geometry) — kept around for future BSP-
renderer experiments.

## WAD format primer

A .wad is a flat archive of "lumps" — named binary chunks. The
header at the start of the file gives a count + offset to the
**lump directory** at the end:

```
+------------------+
| header (12 B)    |  "IWAD" or "PWAD" magic + num-lumps + dir-offset
+------------------+
| lump bytes       |  raw payload of each lump back-to-back
| ...              |
+------------------+
| lump directory   |  array of {offset, size, name} records
+------------------+
```

Each level (E1M1, MAP01, etc.) is represented by a sequence of
specifically-named lumps that immediately follow the level marker
in the directory: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS,
SSECTORS, NODES, REJECT, BLOCKMAP.

## What this parser handles

| Lump | What it is | Status |
|---|---|---|
| Header | Magic + lump count + directory offset | ✅ |
| Directory | Per-lump offset/size/name records | ✅ |
| VERTEXES | List of (x, y) int16 vertices | ✅ |
| LINEDEFS | List of (v1, v2, flags, type, tag, side-r, side-l) line records | ✅ |
| SIDEDEFS, SECTORS, etc. | Sector + texture metadata | ❌ (not parsed) |
| BSP nodes / SEGS / SSECTORS | Pre-built BSP tree for rendering | ❌ |

The current scope is enough to read out the geometry of a level
(vertices + line connectivity) for inspection / debugging / future
BSP renderer prototyping.

## API

```phel
(read-wad path)
;; → {:header  {:magic "IWAD"/"PWAD" :num-lumps N :dir-offset N}
;;    :lumps   <PHP array of {:name :offset :size}>
;;    :raw     <file contents as a PHP string>}

(read-vertexes wad lump-record)
;; → vector of {:x :y}

(read-linedefs wad lump-record)
;; → vector of {:v1 :v2 :flags :type :tag :side-r :side-l}
```

The parser operates on the in-memory file string for random access
(WAD files are typically a few MB; loading into RAM is fine).

## Tests

`tests/modules/io/wad-test.phel` has fixtures + assertions covering
the header parse, directory walk, and the two lump decoders. The
fixture is a hand-rolled minimal WAD constructed inline so the
tests don't depend on shipping a real WAD file.

## Why it exists

DOOM's original level format is the natural target if you want to
load authentic maps into this raycaster. The procedural generator
covers gameplay needs today, but the WAD parser keeps the door
open: dropping a real `.wad` into the project + writing a BSP
renderer that consumes the parsed geometry would be the next layer.
