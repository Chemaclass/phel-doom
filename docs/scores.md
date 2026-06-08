# High scores

Tracks three running bests in `$HOME/.phel-doom-scores.json` (plain JSON):

```json
{
  "best-kills": 42,
  "best-level": 10,
  "fastest-victory-s": 180
}
```

- `best-kills`: most kills in a single run
- `best-level`: deepest level reached
- `fastest-victory-s`: shortest L10-clear time in seconds (0 when no victory)

API: `load-scores` returns the map. `update-scores! kills level survived-s victory?` merges the run and writes the file. The end screen renders bests alongside current totals.

Missing or malformed files return zeros. Write failures are silent (lose a score before blocking the game).
