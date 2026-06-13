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

## Run summary + grade (end screen)

The death / victory screens also show a per-run summary computed from counters accumulated across the whole run (not persisted - they describe the single run just played):

- **accuracy** - `accuracy-pct fired hit` (`core/format`): connecting trigger pulls / total trigger pulls, as an integer percent. A "hit" is one trigger pull that connects with at least one enemy, so a piercing pistol shot through three enemies, or a shotgun cone that grazes several, still counts as ONE fired and ONE hit. A BFG/rocket blast counts as a hit only when it kills (splash has no wound-only signal). The combat step bumps `:shots-fired` in `fire-shot` and `:shots-hit` in `stamp-hit-fx`; `merge-run-stats` sums them across levels.
- **secrets** - cumulative `found / total` across every level played (hidden when a run had no secrets).
- **rank** - `run-grade accuracy secrets-found secrets-total` (`core/format`): a letter S/A/B/C/D from `score = 0.7*accuracy + 0.3*secrets-ratio`, where the secrets ratio is `found/total` (treated as 1.0 when a run had no secrets, so a secret-less run is never penalised). Thresholds: `S >= 0.9`, `A >= 0.75`, `B >= 0.6`, `C >= 0.4`, else `D`. Pure + deterministic, so a recorded demo always grades the same. The letter is colour-coded on screen (gold S, green A, cyan B, white C, dim D).
