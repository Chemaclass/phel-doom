# High scores

Three running bests in `$HOME/.phel-doom-scores.json`, plain JSON (`src/io/scores.phel`):

```json
{
  "best-kills": 42,
  "best-level": 10,
  "fastest-victory-s": 180
}
```

- `best-kills`: most kills in one run.
- `best-level`: deepest level reached.
- `fastest-victory-s`: shortest run, in seconds, that cleared the last level (L10); 0 until the first victory.

`update-scores! kills level survived-s victory?` loads the file, merges the run with the pure `merge-run`, writes it back and returns the bests for the end screen. Only a victory can set `fastest-victory-s`, and only when it beats the record or none exists.

A missing or malformed file reads as zeros. A failed write never interrupts play: `scores-write-failed?` records it and the game reports it once on exit.

## Run summary + grade (end screen)

The death and victory screens also show a summary of the finished run. It is not persisted. `merge-run-stats` sums the counters across levels.

- **accuracy**: `accuracy-pct fired hit` (`core/format`), connecting trigger pulls over total pulls, as a rounded integer percent. `fire-shot` bumps `:shots-fired`; `stamp-hit-fx` bumps `:shots-hit`. One pull counts once, so a pistol shot piercing three enemies or a shotgun cone grazing several is one fired, one hit. A BFG or rocket blast counts as a hit only when it kills, because splash has no wound-only signal.
- **secrets**: `found/total` across every level played. Hidden when the run had no secrets.
- **damage**: total HP lost. `apply-hit` adds the HP lost after clamping to the pool, so armor-absorbed hits and overkill do not count.
- **by**: kills per weapon (`chaingun 29  shotgun 8  pistol 5`), most-used first, so a narrow box clips the least-used weapon. Bumped at each kill by `bump-weapon-kills`, keyed by the active weapon.
- **rank**: `run-grade accuracy found total` (`core/format`). `score = 0.7 * accuracy + 0.3 * secrets-ratio`, where a run with no secrets counts the ratio as 1.0. `S >= 0.9`, `A >= 0.75`, `B >= 0.6`, `C >= 0.4`, else `D`. Pure, so a recorded demo always grades the same. Colours: gold S, green A, cyan B, white C, dim D.
