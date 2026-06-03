---
description: Tighten and de-duplicate the CHANGELOG.md `## [Unreleased]` notes, then commit + push
argument-hint: ""
disable-model-invocation: true
allowed-tools: "Read, Edit, Bash(git *)"
target: claude
---

# Simplify Changelog

Optimize the `## [Unreleased]` section of `CHANGELOG.md`: make it concise and
scannable without losing any fact. Released sections (`## [X.Y.Z]`) are never
touched.

## Context

!`git rev-parse --abbrev-ref HEAD`

## Instructions

1. Read `CHANGELOG.md`. Isolate the block from `## [Unreleased]` up to the next
   `## [` heading. That block is the only thing you may rewrite.

2. If the block has no bullets, report "Unreleased is already empty" and stop.
   Do not commit.

3. Rewrite each bullet tighter. Simplify wording only - never invent, never drop
   information:
   - Cut filler, hedging, and redundant clauses. Keep the *what* and the
     *why-it-matters*.
   - Preserve verbatim: issue/PR refs (`(#NNN)`), code in backticks, numbers,
     slot/level facts, and any `**BREAKING**` marker.
   - One bullet per user-facing change. Merge duplicates and bullets that
     describe the same change.
   - Match house style: descriptive lead phrase, then a colon or sentence with
     the detail. ASCII hyphen ` - ` for asides, never the em-dash character.
   - Drop anything not user-facing (pure `chore:` / CI / internal-only churn).

4. Place each bullet under the right subsection and drop empty ones:
   - `### Added` - new features
   - `### Changed` - behavior changes, visible refactors
   - `### Fixed` - bug fixes
   - `### Removed` - removals
   - `### Performance` - pure speed/size wins

5. Order bullets within each section by user impact (biggest first).

6. Write the simplified block back. Leave the released sections and the link
   references at the bottom untouched.

7. Guard: this skill commits + pushes `CHANGELOG.md` alone, so the working
   tree must hold no other changes. Check first:

   ```bash
   git status --porcelain | grep -v '[[:space:]]CHANGELOG\.md$'
   ```

   If that prints anything, the tree has unrelated work (often the very feature
   these notes describe, not yet committed). Do NOT commit or push. Leave
   `CHANGELOG.md` edited, report what else is pending, and tell the user to land
   those changes first (or commit the changelog alongside them).

8. Only when the tree is otherwise clean, commit and push automatically - no
   confirmation:

   ```bash
   git add CHANGELOG.md
   git commit -m "docs(changelog): simplify unreleased notes"
   git push
   ```

   This holds whether on `main` or a feature branch (the usual flow is `main`
   right after a merged PR).
