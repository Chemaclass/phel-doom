---
description: Walk all open GitHub issues (unassigned or assigned to me) and process each via /gh-issue
argument-hint: "[--limit N] [--label foo] [--dry-run]"
disable-model-invocation: true
allowed-tools: "Read, Bash(gh *), Bash(git *), Bash(composer *), Skill(gh-issue), Skill(pr)"
target: claude
---

# GitHub Issues Watcher

## Purpose

Process every open issue that is **unassigned** or **assigned to `@me`**, oldest first, delegating each to `/gh-issue`. Stop on first hard failure.

## Args

- `--limit N` — process at most N (default: all).
- `--label foo` — only issues carrying label `foo`.
- `--dry-run` — print queue, exit.

Strip leading `#` from issue references.

## Phase 1: Discover

```bash
gh issue list --state open --search "no:assignee" \
  --json number,title,labels,assignees,createdAt --limit 200

gh issue list --state open --assignee "@me" \
  --json number,title,labels,assignees,createdAt --limit 200
```

Merge:
- Dedupe by `number`.
- Keep only empty `assignees` or containing current user (`gh api user -q .login`).
- Apply `--label` filter.
- Apply `--limit`.
- Sort ascending by `createdAt` (FIFO).

Print queue: `#<num> <title> [assignee]`. Empty → exit.

## Phase 2: Worktree sanity

```bash
git status --porcelain
git fetch origin main
git checkout main && git reset --hard origin/main
```

Abort if dirty. Never auto-stash.

## Phase 3: Loop

For each issue:

1. Re-check assignment (someone may have grabbed it).
2. Invoke `/gh-issue <num>`. That skill owns full workflow.
3. Wait CI: `gh pr checks --watch`.
4. Merge: `gh pr merge --auto --squash --admin`.
5. Sync `main`: `git checkout main && git fetch origin main && git reset --hard origin/main`.
6. Next issue.

## Stop conditions

- `/gh-issue` errors or leaves dirty worktree.
- `composer ci` fails.
- CI red after one fix attempt.
- Merge blocked beyond `--admin`.
- `--limit` reached.
- Queue empty.

No blind retries. Report failed issue + reason.

## Dry run

`--dry-run`: print queue, do not touch anything.

## Preconditions

- `gh` authenticated.
- Clean worktree.
- `main` tracks `origin/main`.
- `/gh-issue` and `/pr` available.
