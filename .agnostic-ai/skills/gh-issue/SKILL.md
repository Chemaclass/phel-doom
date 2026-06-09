---
description: Fetch a GitHub issue, branch, implement test-first, ship via /pr
argument-hint: "[issue-number]"
disable-model-invocation: false
target: claude
---

# GitHub Issue Workflow

## Context

Read body **and every comment**. Maintainer comments often override or extend the body. On conflict, prefer the comment.

!`gh issue view ${ARGUMENTS#\#} --json number,url,title,body,labels,assignees,state,comments 2>/dev/null || echo "Provide an issue number"`

## Instructions

### Phase 1: Setup

1. Parse issue number from `$ARGUMENTS` (strip leading `#`).

2. Self-assign:
   ```bash
   gh issue edit <number> --add-assignee @me
   ```

3. Branch from fresh `main`. Prefix from label:
   - `bug` → `fix/`
   - `enhancement` → `feat/`
   - `documentation` → `docs/`
   - `performance` → `perf/`
   - No label → `feat/`

   Branch name: `<prefix><issue-number>-<slug>`.

   ```bash
   git checkout main && git pull
   git checkout -b <branch-name>
   ```

### Phase 2: Plan

4. Enter plan mode:
   - Explore affected areas (use built-in `Explore` agent for unfamiliar modules).
   - Identify files to change.
   - Consider IO boundary (`core/` / `glue/` / `io/`).
   - Test strategy (deterministic core/glue unit tests; `/play` smoke for `io/`).

5. Output plan: summary, files, test list, step order.

### Phase 3: Implement

6. After plan approval, TDD:
   - Failing test first (red).
   - Minimum code to pass (green).
   - Refactor while green.

   For specialists: delegate to `raycaster-expert` (engine math), `render-expert` (visuals), `perf-profiler` (numbers). Run in parallel where independent.

7. Run gates:
   ```bash
   composer ci
   ```
   Fix ALL errors before proceeding.

### Phase 4: Ship

8. Update `CHANGELOG.md` under `## Unreleased` (only for `feat:` / `fix:` / `perf:`).

9. Commit:
   ```bash
   git add <specific-files>
   git commit -m "<type>(<scope>): <description>

   Related to #<issue-number>"
   ```

10. **Final review pass** — invoke `clean-code-reviewer` over the diff. Apply blocking fixes. If review changes anything, commit as separate `ref(<scope>):` commit before opening PR. If review surfaces nothing, note it in the PR body.

11. Open PR via `/pr <issue-number>`.

### Phase 5: Verify & Merge

12. Watch CI:
    ```bash
    gh pr checks --watch
    ```
    Fix red checks before merging.

13. Merge:
    ```bash
    gh pr merge <pr-number> --squash --admin --delete-branch
    ```
    Fall back to `--auto --squash --delete-branch` if `--admin` denied.

14. Sync `main`:
    ```bash
    git checkout main && git fetch origin main && git reset --hard origin/main
    ```

## Checklist
- [ ] Issue + comments read
- [ ] Self-assigned
- [ ] Branch from fresh `origin/main`
- [ ] Plan approved
- [ ] Red test first
- [ ] `composer ci` green
- [ ] CHANGELOG updated (if user-facing)
- [ ] Feature commit with `Related to #N`
- [ ] Final `ref(...)` commit if reviewer found anything
- [ ] PR via `/pr`
- [ ] CI green
- [ ] Squash-merged, branch deleted
- [ ] Local `main` synced
