---
description: Measure cast/render cost before/after a change with the tracked `phel bench` harness (tests/bench)
argument-hint: "[baseline-ref] [candidate-ref]"
allowed-tools: "Read, Bash(vendor/bin/phel *), Bash(composer *), Bash(git *)"
target: claude
---

# Perf Bench

Validate or refute a performance hypothesis. Measurement-led — does NOT patch code.

The harness is `tests/bench/frame-bench.phel`: `defbench` rows (phel 0.50
`phel.bench`) over one fixed scene. `cast-120` / `cast-240` time `cast-frame`
alone; `frame-120x30` / `frame-180x45` / `frame-240x60` time the whole
`frame->string`. `phel bench` stores a baseline and gates a branch against it
(`docs/performance.md`, "How to measure").

## When to use

- Suspect regression after a hot-path change.
- Before/after of any change to `engine.phel`, `render/*.phel`, `physics.phel`.
- Before writing a number into `docs/performance.md` or `CHANGELOG.md`.

## Inputs

- `$ARGUMENTS` parses as `[baseline] [candidate]`. Default: `main HEAD`.

## Procedure

Both runs on the SAME machine in ONE sitting: absolute durations do not travel,
and the local php CLI runs without JIT. Close what else is running.

1. Stash any local changes:
   ```bash
   git stash --include-untracked
   ```

2. Baseline:
   ```bash
   git checkout <baseline>
   composer bench-store          # -> .phel/bench-baseline.json
   ```
   The bench file must exist on the baseline too; if it does not (a ref older
   than the harness), copy `tests/bench/frame-bench.phel` in from the candidate
   first (`git show <candidate>:tests/bench/frame-bench.phel > ...`) - it is a
   consumer of the game API, not part of what is measured.

3. Candidate:
   ```bash
   git checkout <candidate>
   composer bench-ref            # delta per row vs the baseline, exit 1 past +10%
   ```

4. Read `rstdev` before the delta. A row above a few percent is a noisy run: re-run
   that family with more revs before believing it:
   ```bash
   composer bench -- --filter=frame-120 --revs=100
   ```

5. Restore:
   ```bash
   git checkout <original-branch>
   git stash pop
   ```

6. Cross-reference `docs/performance.md`. Flag any quoted number that should
   update — do NOT edit the doc here.

## Output

Markdown report:
1. Hypothesis.
2. The `bench-ref` table (row, mean, rstdev, vs-baseline), plus a one-line
   verdict per row: >5% slower = regression; >5% faster = improvement; else noise.
3. Recommendation: ship / re-bench / abandon.
4. Doc updates needed.

## Constraints

- Single >5% data point is signal, not proof. Re-bench before declaring.
- Cast-phase work → read the `cast-*` rows, not just `frame-*`.
- The scene is fixed (3 enemies in view, minimap on). A change that only moves
  something it does not exercise (px2, truecolor, pitch, an empty room) needs a
  new `defbench` row in the same PR, not a hand-run number.
- Never change the harness in the PR whose delta it measures: land the harness
  change first, then measure.
