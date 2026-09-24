# WAD parser

`src/io/wad.phel`. Parses the DOOM `.wad` binary format. The game does not load WADs at runtime (levels are procedural grids). The asset bakers in `tools/` use it to pull Freedoom sprites and sounds (see [tools/README.md](../tools/README.md)).

## Format

A WAD is an archive of named chunks ("lumps"): header | lump data | directory.

- Header (12 B): magic (`IWAD` / `PWAD`), lump count, directory offset.
- Directory entry (16 B): offset (4 B), size (4 B), 8-byte name.

Each level (E1M1, MAP01, ...) is a marker lump followed by VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, SEGS, SSECTORS, NODES, REJECT, BLOCKMAP.

## API

```phel
(parse-header bytes)          ; => {:id "IWAD"|"PWAD" :num-lumps N :dir-offset N}
(parse-directory bytes header); => PHP array of {:offset :size :name}
(find-lump dir name)          ; => {:offset :size :name} or nil
(read-vertexes bytes entry)   ; => PHP array of {:x :y} (int16 map units)
(read-linedefs bytes entry)   ; => PHP array of {:a :b} (vertex indices, 14-byte records)
```

Linedef flags, types and sidedefs are skipped, as are SECTORS and the BSP lumps. The whole file is read into memory (a WAD is a few MB).

`tests/io/wad-test.phel` covers header, directory, and vertex/linedef decoding against a minimal WAD built inline.
