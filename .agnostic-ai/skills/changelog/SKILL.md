---
description: Update CHANGELOG.md `## Unreleased` from recent commits or a manual entry
disable-model-invocation: true
allowed-tools: "Read, Edit, Bash(git *)"
x-claude:
  argument-hint: "[entry text]"
---

# Update Changelog

## Context

::target claude
!`git log $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~30)..HEAD --oneline`
::end
::target codex
Run first: `git log $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~30)..HEAD --oneline`.
::end

## Instructions

1. Read `CHANGELOG.md`.

2. If an entry was passed as the argument, add it under the right `## Unreleased` subsection.

3. Otherwise analyze commits and draft entries:
   - `### Added` — `feat:`
   - `### Changed` — `ref:` (visible), `perf:` that changes behavior, behavior tweaks
   - `### Fixed` — `fix:`
   - `### Removed` — removals
   - `### Performance` — `perf:` (pure speed/size)

4. Entry format:
   - Imperative: "Add" not "Added".
   - Code in backticks.
   - Under 100 chars per entry.
   - Skip non-user-facing (`chore:`, CI, internal-only `ref:`).
   - Prefix breaking changes with **BREAKING**.

5. Present draft. Edit only after approval.

## Section template

```markdown
## Unreleased

### Added

### Changed

### Fixed

### Performance
```

Drop empty sections from the final write.
