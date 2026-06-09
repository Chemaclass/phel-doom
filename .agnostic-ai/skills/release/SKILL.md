---
description: Cut a phel-doom release via tools/release.sh, then verify the published phar + GitHub release
argument-hint: "[version] [--dry-run]"
disable-model-invocation: false
allowed-tools: "Read, Bash(./tools/release.sh *), Bash(git *), Bash(gh *), Bash(composer *), Bash(shasum *)"
target: claude
---

# Release

Cut a release using the existing `tools/release.sh`. NEVER hand-roll the steps
(changelog move, phar build, tag, GH release) - the script owns all of them and
has rollback on failure. Your job: preflight, run the script, verify the
artifact.

## Context

!`git rev-parse --abbrev-ref HEAD`
!`git status --porcelain`

## Instructions

1. Preflight. The script also checks these, but fail fast and clearly:
   - Working tree clean (the status above prints nothing).
   - On `main`.
   - `gh auth status` OK.
   - Target version is valid semver and the tag is free
     (`git tag | grep -x "vX.Y.Z"` returns nothing).

2. If `## [Unreleased]` in `CHANGELOG.md` is messy, run `/changelog-simplify`
   first so the release notes are clean. The script moves that block verbatim
   into the dated section.

3. Dry-run first when the version bump is non-obvious or the tree had recent
   churn:

   ```bash
   ./tools/release.sh X.Y.Z --dry-run
   ```

   Read the output. Confirm the version, changelog block, and phar smoke-test
   all look right.

4. Cut the release:

   ```bash
   ./tools/release.sh X.Y.Z
   ```

   The script: validates semver + preflight, moves the CHANGELOG block, builds a
   self-contained `phel-doom.phar` + smoke-tests it + writes its SHA256, commits,
   tags `vX.Y.Z`, pushes branch + tag, and creates the GitHub release with the
   phar + checksum attached.

5. VERIFY the published artifact - do not assume the script's exit 0 means the
   release is live and correct:

   ```bash
   gh release view vX.Y.Z
   gh release download vX.Y.Z --pattern '*.phar' --dir /tmp/rel-check
   shasum -a 256 /tmp/rel-check/*.phar   # must match the published SHA256
   php /tmp/rel-check/phel-doom.phar --help   # phar runs
   ```

6. Report: version, tag URL, attached assets, SHA256 match yes/no, phar-runs
   yes/no. If anything is off, say so plainly - a half-published release is worse
   than none.
