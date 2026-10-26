# WAD parser

`src/io/wad.phel` parses the DOOM `.wad` binary format. Asset bakers in `tools/` use it to extract Freedoom sprites and sounds (see [tools/README.md](../tools/README.md)). The game uses procedural grids and does not load WADs at runtime.

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

The parser skips linedef flags, types and sidedefs, as well as SECTORS and the BSP lumps. It reads the whole file into memory; a WAD is a few MB.

`tests/io/wad-test.phel` checks header, directory and vertex/linedef decoding against an inline minimal WAD.
