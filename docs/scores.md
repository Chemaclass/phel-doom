# High scores

`src/io/scores.phel`. Persists three running bests to `$HOME/.phel-doom-scores.json`.

File schema (plain JSON):
```json
{
  "best-kills": 42,
  "best-level": 10,
  "fastest-victory-s": 180
}
```

- `best-kills`: most kills in any single run
- `best-level`: deepest level reached
- `fastest-victory-s`: shortest L10-clear time in seconds (0 = no win yet)

API: `load-scores` -> map, `update-scores! kills level survived-s victory?` -> updates file and returns new map (called from `commands/play`). End screen renders bests alongside current-run totals.

Error tolerance: missing/malformed file returns all zeros. Write failures are silent. "We'd rather lose a score than block the game."
