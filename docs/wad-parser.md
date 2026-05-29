# WAD parser

`src/io/wad.phel`. Parses DOOM .wad binary format. Not wired into gameplay (renderer uses procedurally-generated grids). Available for future BSP-renderer work.

## Format

Binary archive of "lumps" (named chunks). Header (12 B): magic ("IWAD" or "PWAD") + lump count + directory offset (at EOF). Each lump is (offset, size, 8-byte name).

Directory structure: header | lump payloads | lump directory.

Each level (E1M1, MAP01, etc.) is a named marker followed by geometry lumps: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, REJECT, BLOCKMAP.

## Parser coverage

Reads: header (magic/count/offset), directory (all lumps), VERTEXES (int16 x/y pairs), LINEDEFS (vertex pair indices).

Skipped: SIDEDEFS/SECTORS (texture metadata), BSP tree (pre-built rendering nodes).

Scope: level geometry (vertices + connectivity) for inspection, debugging, BSP prototyping.

## API

```phel
(parse-header bytes)
;; → {:id "IWAD"/"PWAD" :num-lumps N :dir-offset N}

(parse-directory bytes header)
;; → [PHP array of {:offset :size :name}]

(find-lump dir name)
;; → {:offset :size :name} or nil

(read-vertexes bytes entry)
;; → [PHP array of {:x :y}] (int16 map-unit coords)

(read-linedefs bytes entry)
;; → [PHP array of {:a :b}] (vertex indices, 14-byte records)
```

Reads entire file into memory for random access. Typical WAD: few MB.

## Tests

`tests/io/wad-test.phel` covers header parse, directory, vertex/linedef decode. Fixture: hand-rolled minimal WAD inline (no shipped file dependency).
