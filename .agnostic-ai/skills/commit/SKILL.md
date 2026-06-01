---
description: Auto-fix, run ci gates, and commit with a conventional message
argument-hint: "[optional commit message]"
disable-model-invocation: true
allowed-tools: "Read, Edit, Bash(composer *), Bash(vendor/bin/phel *), Bash(git *)"
target: claude
---

# Commit

## Context

!`git diff --stat`
!`git diff --cached --stat`
!`git status --short`

## Instructions

### Phase 1: Auto-fix

1. Auto-format every changed `.phel`:
   ```bash
   composer format
   ```

2. If format modified files, review and stage.

### Phase 2: Quality gates

Stop and fix issues before continuing.

3. **Lint**:
   ```bash
   composer lint
   ```

4. **Tests**:
   ```bash
   composer test
   ```

5. **Build smoke** (only if changed files touch `src/`):
   ```bash
   composer build
   ```

If any step fails, fix it and re-run from that step. Do NOT commit with failures.

> Equivalent one-shot: `composer ci`. Use it if you prefer one command.

### Phase 3: Commit

6. **Stage files** — add specific files by name. NEVER `git add -A` (would pick up generated `out/main.php`, `.phel/cache/*`).

7. **Draft commit message** in Conventional Commits format:
   - If `$ARGUMENTS` provided, use it.
   - Otherwise analyze the staged diff and generate one.
   - Prefixes: `feat:`, `fix:`, `ref:`, `chore:`, `docs:`, `test:`, `perf:`.
   - **Use `ref:` not `refactor:`**.
   - Add `(<scope>)` for single-module change. Scope ≈ filename root (`engine`, `render`, `controls`, …).
   - **NEVER mention AI tooling** in subject or body.
   - **No Co-Authored-By trailer**.
   - No emoji.

8. **Commit**:
   ```bash
   git commit -m "<message>"
   ```

9. **CHANGELOG check** — if prefix is `feat:` / `fix:` / `perf:`, ensure `CHANGELOG.md` has been updated under `## Unreleased`. If not, warn user before pushing.

10. Report: commit hash, message, files included.
