# High scores

`src/io/scores.phel`. Persists three running bests to a JSON file in `$HOME`.

## File

`$HOME/.phel-doom-scores.json`. Plain JSON, user can inspect or wipe without tooling.

```json
{
  "best-kills": 42,
  "best-level": 5,
  "fastest-victory-s": 180
}
```

## Schema

| Key | Meaning | Default |
|---|---|---|
| `best-kills` | Most kills in any single run | 0 |
| `best-level` | Deepest level reached | 0 |
| `fastest-victory-s` | Shortest L5-clear time in seconds (0 = no win yet) | 0 |

## API

```phel
(load-scores)
;; → {:best-kills N :best-level N :fastest-victory-s N}

(update-scores! kills level survived-s victory?)
;; merge this run into the file, write back, return the new map
```

`update-scores!` is the entry point used by `run-levels` in `commands/play.phel`:

```phel
(let [scores (update-scores! kills level survived-s victory?)]
  (death-loop kills survived-s level level-name scores))
```

End screen renders persisted bests next to current-run totals.

## Error tolerance

File IO never crashes the game:

- Missing file: return `empty-scores` (all zeros).
- Malformed JSON: return `empty-scores`.
- Disk write failure: silent.

> "we'd rather lose a score than block a game from running"

## Why `io/`

Reads/writes disk. `(load-scores)` result is consumed in pure code (rendered into end screen), but the read/write itself is a side effect.
