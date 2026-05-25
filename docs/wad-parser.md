# WAD parser

`src/io/wad.phel`. Parses the DOOM .wad format. Not yet wired into gameplay (active renderer uses procedurally-generated grids). Kept for future BSP-renderer experiments.

## WAD format primer

A .wad is a flat archive of "lumps", named binary chunks. Header gives count + offset to the lump directory at the end of the file:

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

Each level (E1M1, MAP01, etc.) is a sequence of named lumps that follow the level marker in the directory: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, REJECT, BLOCKMAP.

## What this parser handles

| Lump | What it is | Status |
|---|---|---|
| Header | Magic + lump count + directory offset | yes |
| Directory | Per-lump offset/size/name records | yes |
| VERTEXES | List of (x, y) int16 vertices | yes |
| LINEDEFS | List of (v1, v2, flags, type, tag, side-r, side-l) line records | yes |
| SIDEDEFS, SECTORS, etc. | Sector + texture metadata | no |
| BSP nodes / SEGS / SSECTORS | Pre-built BSP tree for rendering | no |

Current scope: enough to read level geometry (vertices + line connectivity) for inspection / debugging / future BSP prototyping.

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

Parser operates on the in-memory file string for random access. WAD files are typically a few MB; loading into RAM is fine.

## Tests

`tests/io/wad-test.phel` covers header parse, directory walk, and the two lump decoders. Fixture is a hand-rolled minimal WAD constructed inline, so tests don't depend on shipping a real WAD.

## Why it exists

DOOM's original level format is the natural target for loading authentic maps. Procedural generation covers gameplay today; WAD parser keeps the door open: drop a real `.wad` in + write a BSP renderer that consumes the parsed geometry = next layer.
