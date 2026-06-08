# WAD parser

`src/io/wad.phel`. Parses DOOM .wad binary format. Not integrated into gameplay (renderer uses procgen grids). Available for future BSP-renderer work.

## Format

Binary archive of "lumps" (named chunks). Header (12 B): magic ("IWAD"/"PWAD") + lump count + directory offset. Each lump entry is 16 B: offset (4 B) + size (4 B) + 8-byte name.

File layout: header | lump data | directory.

Each level (E1M1, MAP01, etc.) is a marker lump followed by geometry: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, REJECT, BLOCKMAP.

## Parser coverage

Reads header (magic/count/offset), directory (all lumps), VERTEXES (int16 x/y pairs), LINEDEFS (vertex pair indices).

Skips SIDEDEFS/SECTORS (texture metadata), BSP tree (rendering nodes).

Use case: level geometry inspection, debugging, BSP prototyping.

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

Reads entire file into memory. Typical WAD: few MB.

## Tests

`tests/io/wad-test.phel` covers header parse, directory, vertex/linedef decode. Fixture: minimal WAD built inline (no file dependency).
