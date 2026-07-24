#!/usr/bin/env bash
# Release script for phel-doom.
#
# Usage: ./tools/release.sh [version] [--dry-run] [--force] [--name "Release name"]
#
# Steps:
#   1. Validate semver and preflight (clean tree, on main, gh CLI ready, tag free).
#   2. Move CHANGELOG.md "## [Unreleased]" block into "## [X.Y.Z] - YYYY-MM-DD".
#   3. Build a self-contained phel-doom.phar, smoke-test it, write its SHA256.
#   4. Commit, tag vX.Y.Z, push branch and tag.
#   5. Create GitHub release (changelog as notes + SHA256), attaching the PHAR + checksum.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
# tools/ lives one level below the repo root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"
VERSION_FILE="$REPO_ROOT/src/core/version.phel"
PHAR_SCRIPT="$REPO_ROOT/build/phar.sh"
PHAR_OUTPUT="$REPO_ROOT/build/out/phel-doom.phar"
CHECKSUM_OUTPUT="$REPO_ROOT/build/out/checksum"
MAIN_BRANCH="main"
REMOTE="origin"
DEFAULT_REPO_SLUG="Chemaclass/phel-doom"

NEW_VERSION=""
RELEASE_NAME=""
DRY_RUN=0
FORCE=0
DRAFT=0
SKIP_TESTS=0
SKIP_PHAR=0
REPO_SLUG=""
PHAR_SHA256=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; NC=""
fi

log()     { printf '%b\n' "$*"; }
log_ok()  { log "${GREEN}[OK]${NC} $*"; }
log_warn(){ log "${YELLOW}[WARN]${NC} $*"; }
log_err() { log "${RED}[ERR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Backup / rollback. Track which side-effects happened so EXIT can undo the
# right subset (CHANGELOG file, release commit, local tag) when an error
# trips mid-flow.
# ---------------------------------------------------------------------------
BACKUP_DIR=""
COMMITTED=0
TAGGED=0
PUSHED=0

cleanup_backup() {
    [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] && rm -rf "$BACKUP_DIR"
    return 0
}

rollback() {
    if [[ $PUSHED -eq 1 ]]; then
        log_err "Push already completed — manual cleanup required:"
        log_err "  git push $REMOTE :refs/tags/v$NEW_VERSION"
        log_err "  git push $REMOTE +HEAD~1:$MAIN_BRANCH   # if main was advanced"
        cleanup_backup
        return 0
    fi
    log_warn "Rolling back changes..."
    if [[ $TAGGED -eq 1 ]]; then
        git -C "$REPO_ROOT" tag -d "v$NEW_VERSION" >/dev/null 2>&1 \
            && log_ok "Removed local tag v$NEW_VERSION"
    fi
    if [[ $COMMITTED -eq 1 ]]; then
        git -C "$REPO_ROOT" reset --hard HEAD~1 >/dev/null 2>&1 \
            && log_ok "Reverted release commit"
    fi
    if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/CHANGELOG.md" ]]; then
        cp "$BACKUP_DIR/CHANGELOG.md" "$CHANGELOG_FILE"
        log_ok "Restored CHANGELOG.md"
    fi
    if [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/version.phel" ]]; then
        cp "$BACKUP_DIR/version.phel" "$VERSION_FILE"
        log_ok "Restored src/core/version.phel"
    fi
    cleanup_backup
}

on_exit() {
    local code=$?
    [[ $code -ne 0 ]] && rollback
    cleanup_backup
    exit $code
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: ./release.sh [version] [options]

Arguments:
  [version]           Semver X.Y.Z (e.g. 0.1.0). Optional.
                      If omitted, bumps the minor of the latest git tag
                      (vX.Y.Z -> vX.(Y+1).0). Falls back to 0.1.0 if no tags.

Options:
  --name "<title>"    Release title suffix shown in GitHub (default: just vX.Y.Z)
  --dry-run           Print actions without changing files or pushing
  --force             Skip confirmation prompt
  --skip-tests        Skip composer ci gate (NOT recommended)
  --skip-phar         Skip building + attaching the phel-doom.phar
  --draft             Create the GitHub release as a draft
  -h, --help          Show this help

Examples:
  ./tools/release.sh                  # auto-bump minor from latest tag
  ./tools/release.sh 0.1.0
  ./tools/release.sh 0.2.0 --name "DDA raycaster" --dry-run
EOF
}

# Print next minor version based on latest vX.Y.Z tag. Defaults to 0.1.0.
compute_next_minor() {
    local latest major minor
    latest=$(git -C "$REPO_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' \
        | sed 's/^v//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -n1)

    if [[ -z "$latest" ]]; then
        echo "0.1.0"
        return
    fi

    IFS='.' read -r major minor _ <<<"$latest"
    echo "${major}.$((minor + 1)).0"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)    DRY_RUN=1; shift ;;
            --force)      FORCE=1; shift ;;
            --skip-tests) SKIP_TESTS=1; shift ;;
            --skip-phar)  SKIP_PHAR=1; shift ;;
            --draft)      DRAFT=1; shift ;;
            --name)       RELEASE_NAME="${2:-}"; shift 2 ;;
            -h|--help)    show_help; exit 0 ;;
            -*)        log_err "Unknown flag: $1"; show_help; exit 1 ;;
            *)
                if [[ -z "$NEW_VERSION" ]]; then
                    NEW_VERSION="$1"
                else
                    log_err "Unexpected argument: $1"; exit 1
                fi
                shift ;;
        esac
    done

    if [[ -z "$NEW_VERSION" ]]; then
        NEW_VERSION=$(compute_next_minor)
        log "No version specified - auto-bumping minor to ${BOLD}$NEW_VERSION${NC}"
    fi
}

validate_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Derive "owner/repo" from origin URL. Supports ssh + https forms.
# Falls back to DEFAULT_REPO_SLUG if origin is unset or unparseable.
detect_repo_slug() {
    local url slug
    url=$(git -C "$REPO_ROOT" remote get-url "$REMOTE" 2>/dev/null || true)
    if [[ -z "$url" ]]; then
        echo "$DEFAULT_REPO_SLUG"
        return
    fi
    # git@github.com:owner/repo(.git) or https://github.com/owner/repo(.git)
    slug=$(printf '%s' "$url" \
        | sed -E 's#\.git$##' \
        | sed -E 's#^.*github\.com[:/]##')
    [[ -n "$slug" && "$slug" != "$url" && "$slug" == */* ]] \
        && echo "$slug" \
        || echo "$DEFAULT_REPO_SLUG"
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
check_gh_cli() {
    command -v gh >/dev/null 2>&1 || { log_err "gh CLI not installed"; return 1; }
    gh auth status >/dev/null 2>&1 || { log_err "gh CLI not authenticated (run: gh auth login)"; return 1; }
}

check_git_state() {
    git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || { log_err "Not a git repo: $REPO_ROOT"; return 1; }

    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
        log_err "Working tree not clean. Commit or stash first."
        git -C "$REPO_ROOT" status --short
        return 1
    fi
}

check_branch() {
    local branch
    branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
    if [[ "$branch" != "$MAIN_BRANCH" ]]; then
        log_err "Must release from '$MAIN_BRANCH' (currently on '$branch')"
        return 1
    fi
}

check_tag_free() {
    local tag="v$1"
    if git -C "$REPO_ROOT" rev-parse "$tag" >/dev/null 2>&1; then
        log_err "Tag $tag already exists locally"
        return 1
    fi
    if git -C "$REPO_ROOT" ls-remote --exit-code --tags "$REMOTE" "refs/tags/$tag" >/dev/null 2>&1; then
        log_err "Tag $tag already exists on $REMOTE"
        return 1
    fi
}

check_changelog_unreleased() {
    [[ -f "$CHANGELOG_FILE" ]] || { log_err "CHANGELOG.md not found"; return 1; }
    grep -qE '^## \[Unreleased\]' "$CHANGELOG_FILE" \
        || { log_err "CHANGELOG.md missing '## [Unreleased]' section"; return 1; }

    # Ensure Unreleased has at least one bullet
    local body
    body=$(extract_unreleased)
    if ! grep -qE '^[*-] ' <<<"$body"; then
        log_err "Unreleased section is empty. Add notes before releasing."
        return 1
    fi
}

check_network() {
    git -C "$REPO_ROOT" ls-remote --exit-code "$REMOTE" HEAD >/dev/null 2>&1 \
        || { log_err "Cannot reach remote '$REMOTE'"; return 1; }
}

# Full CI gate (format-check + lint + test + build) before tagging.
# Skippable via --skip-tests, logs a warning so audit trail exists.
check_tests() {
    if [[ $SKIP_TESTS -eq 1 ]]; then
        log_warn "Skipping composer ci (--skip-tests)"
        return 0
    fi
    log "Running composer ci..."
    (cd "$REPO_ROOT" && composer ci >/dev/null 2>&1) \
        || { log_err "composer ci failed — run 'composer ci' to see output"; return 1; }
    log_ok "composer ci"
}

run_preflight() {
    log "\n${BOLD}Pre-flight checks${NC}"
    check_gh_cli
    check_git_state
    check_branch
    check_network
    check_tag_free "$NEW_VERSION"
    check_changelog_unreleased
    check_tests
    log_ok "All checks passed"
}

# ---------------------------------------------------------------------------
# CHANGELOG handling
# ---------------------------------------------------------------------------
# Print body lines between "## [Unreleased]" and the next "## " heading.
extract_unreleased() {
    awk '
        /^## \[Unreleased\]/ { in_block=1; next }
        in_block && /^## / { exit }
        in_block { print }
    ' "$CHANGELOG_FILE"
}

update_changelog() {
    local version="$1"
    local date_str
    date_str=$(date -u +%Y-%m-%d)

    local prev_tag
    prev_tag=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || true)

    local compare_url
    if [[ -n "$prev_tag" ]]; then
        compare_url="https://github.com/${REPO_SLUG}/compare/${prev_tag}...v${version}"
    else
        compare_url="https://github.com/${REPO_SLUG}/releases/tag/v${version}"
    fi
    local unreleased_compare="https://github.com/${REPO_SLUG}/compare/v${version}...HEAD"

    local tmp
    tmp=$(mktemp)

    awk -v ver="$version" -v date="$date_str" -v unrel="$unreleased_compare" -v rel="$compare_url" '
        BEGIN { replaced_heading=0 }
        /^## \[Unreleased\]/ && !replaced_heading {
            print "## [Unreleased]"
            print ""
            print "## [" ver "] - " date
            replaced_heading=1
            next
        }
        /^\[Unreleased\]:/ {
            print "[Unreleased]: " unrel
            print "[" ver "]: " rel
            next
        }
        { print }
    ' "$CHANGELOG_FILE" >"$tmp"

    mv "$tmp" "$CHANGELOG_FILE"
}

# Print the notes block for a given version (between "## [X.Y.Z]" and next "## ").
extract_release_notes() {
    local version="$1"
    awk -v ver="$version" '
        $0 ~ "^## \\[" ver "\\]" { in_block=1; next }
        in_block && /^## / { exit }
        in_block && /^\[[^]]+\]: / { exit }
        in_block { print }
    ' "$CHANGELOG_FILE"
}

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
confirm_release() {
    [[ $FORCE -eq 1 || $DRY_RUN -eq 1 ]] && return 0
    echo ""
    log "${BOLD}Release v$NEW_VERSION${NC}"
    [[ -n "$RELEASE_NAME" ]] && log "Name: $RELEASE_NAME"
    if [[ $SKIP_PHAR -eq 1 ]]; then
        log "Actions: update CHANGELOG.md, commit, tag v$NEW_VERSION, push, create GitHub release"
    else
        log "Actions: update CHANGELOG.md, build+smoke-test PHAR, commit, tag v$NEW_VERSION, push, create GitHub release (with PHAR asset)"
    fi
    echo ""
    read -rp "Proceed? [y/N] " response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) log_warn "Cancelled"; exit 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Git + GitHub
# ---------------------------------------------------------------------------
# Bump the version literal in src/core/version.phel so the compiled game (and
# thus the PHAR), the start menu, and the credits all report the released
# version. This is the single source of truth; the build does not stamp.
bump_src_version() {
    # Line-anchored (^ + /m) so only the real `(def version ...)` form is
    # rewritten, never a `(def version ...)` mention in a comment.
    perl -0pi -e 's/^(\(def version )"[^"]*"/${1}"'"$NEW_VERSION"'"/m' "$VERSION_FILE"
    grep -qE "^\(def version \"$NEW_VERSION\"\)" "$VERSION_FILE" \
        || { log_err "Failed to bump version in src/core/version.phel"; return 1; }
}

git_commit_release() {
    git -C "$REPO_ROOT" add "$CHANGELOG_FILE" "$VERSION_FILE"
    git -C "$REPO_ROOT" commit -m "chore(release): v$NEW_VERSION"
    COMMITTED=1
}

git_create_tag() {
    git -C "$REPO_ROOT" tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"
    TAGGED=1
}

# Atomic push: branch + tag land together or neither does. Without --atomic
# a branch push can succeed while the tag push fails, leaving remote main
# advanced without the corresponding tag.
git_push() {
    git -C "$REPO_ROOT" push --atomic "$REMOTE" \
        "$MAIN_BRANCH" "v$NEW_VERSION"
    PUSHED=1
}

# Build the distributable single-file PHAR. The version was already bumped into
# src/core/version.phel, so phar.sh just compiles + packages.
build_phar() {
    if [[ $SKIP_PHAR -eq 1 ]]; then
        log_warn "Skipping PHAR build (--skip-phar)"
        return 0
    fi
    [[ -x "$PHAR_SCRIPT" ]] || { log_err "PHAR build script not found: $PHAR_SCRIPT"; return 1; }
    log "Building phel-doom.phar..."
    "$PHAR_SCRIPT" >/dev/null \
        || { log_err "PHAR build failed — run '$PHAR_SCRIPT' to see output"; return 1; }
    [[ -f "$PHAR_OUTPUT" ]] || { log_err "PHAR not found at $PHAR_OUTPUT after build"; return 1; }
    log_ok "Built $PHAR_OUTPUT"

    # Publish a checksum so downloaders can verify integrity. `php hash_file`
    # avoids shasum/sha256sum portability differences. The file mirrors the
    # `<hash>  <name>` shasum format, so `shasum -a 256 -c checksum` works once
    # both assets sit in the same directory.
    PHAR_SHA256=$(php -r 'echo hash_file("sha256", $argv[1]);' "$PHAR_OUTPUT") \
        || { log_err "Failed to compute PHAR checksum"; return 1; }
    printf '%s  %s\n' "$PHAR_SHA256" "phel-doom.phar" >"$CHECKSUM_OUTPUT"
    log_ok "SHA256: $PHAR_SHA256"
}

# Smoke-test the freshly built PHAR: it must report the released version and
# emit no PHP diagnostics on stderr. The game itself needs a TTY, so we only
# exercise the non-interactive --version path here.
smoke_test_phar() {
    [[ $SKIP_PHAR -eq 1 ]] && return 0
    local out err rc
    out=$(mktemp); err=$(mktemp)
    php "$PHAR_OUTPUT" --version >"$out" 2>"$err"; rc=$?
    if [[ $rc -ne 0 ]]; then
        log_err "PHAR smoke test failed (exit $rc)"; sed -n '1,20p' "$err" >&2
        rm -f "$out" "$err"; return 1
    fi
    if grep -qE 'PHP (Warning|Fatal|Parse|Deprecated) ' "$err"; then
        log_err "PHAR smoke test emitted PHP diagnostics:"; grep -E 'PHP ' "$err" | head -3 >&2
        rm -f "$out" "$err"; return 1
    fi
    if ! grep -qE "phel-doom $NEW_VERSION" "$out"; then
        log_err "PHAR --version did not report $NEW_VERSION:"; sed -n '1,5p' "$out" >&2
        rm -f "$out" "$err"; return 1
    fi
    rm -f "$out" "$err"
    log_ok "PHAR smoke test passed (phel-doom $NEW_VERSION)"
}

create_github_release() {
    local notes
    notes=$(extract_release_notes "$NEW_VERSION")
    [[ -z "$notes" ]] && notes="Release v$NEW_VERSION"

    # Append the checksum so the hash is visible in the notes (and the file is
    # attached below for `shasum -c`).
    if [[ -n "$PHAR_SHA256" ]]; then
        notes="$notes

## Checksum
SHA256: \`$PHAR_SHA256\`"
    fi

    local title="v$NEW_VERSION"
    [[ -n "$RELEASE_NAME" ]] && title="v$NEW_VERSION - $RELEASE_NAME"

    local notes_file
    notes_file=$(mktemp)
    printf '%s\n' "$notes" >"$notes_file"

    local draft_flag=""
    [[ $DRAFT -eq 1 ]] && draft_flag="--draft"

    # Attach the PHAR + its checksum as assets when present (skipped via
    # --skip-phar). Scalars (not an array) so empty values vanish cleanly
    # under `set -u` on bash 3.2.
    local phar_asset="" sum_asset=""
    if [[ $SKIP_PHAR -eq 0 && -f "$PHAR_OUTPUT" ]]; then
        phar_asset="$PHAR_OUTPUT"
        [[ -f "$CHECKSUM_OUTPUT" ]] && sum_asset="$CHECKSUM_OUTPUT"
    fi

    gh release create "v$NEW_VERSION" \
        --repo "$REPO_SLUG" \
        --title "$title" \
        --notes-file "$notes_file" \
        $draft_flag \
        ${phar_asset:+"$phar_asset"} \
        ${sum_asset:+"$sum_asset"}

    rm -f "$notes_file"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    log "\n${BOLD}phel-doom release${NC}\n"
    [[ $DRY_RUN -eq 1 ]] && log "${YELLOW}DRY-RUN mode - no changes will be made${NC}\n"

    REPO_SLUG=$(detect_repo_slug)
    log "Repo: $REPO_SLUG"

    validate_semver "$NEW_VERSION" \
        || { log_err "Invalid version: $NEW_VERSION (expected X.Y.Z)"; exit 1; }
    log_ok "Version format valid: $NEW_VERSION"

    run_preflight

    confirm_release

    # Backup mutated files so failures can roll back
    BACKUP_DIR=$(mktemp -d)
    cp "$CHANGELOG_FILE" "$BACKUP_DIR/CHANGELOG.md"
    cp "$VERSION_FILE" "$BACKUP_DIR/version.phel"

    log "\n${BOLD}Updating CHANGELOG.md${NC}"
    update_changelog "$NEW_VERSION"
    log_ok "Moved Unreleased → [$NEW_VERSION]"

    log "\n${BOLD}Bumping version${NC}"
    bump_src_version
    log_ok "Set version to $NEW_VERSION"

    if [[ $DRY_RUN -eq 1 ]]; then
        log "\n${BOLD}Release notes preview${NC}"
        extract_release_notes "$NEW_VERSION"
        if [[ $SKIP_PHAR -eq 1 ]]; then
            log "\n[DRY-RUN] Would: git commit, tag v$NEW_VERSION, push, gh release create (no PHAR)"
        else
            log "\n[DRY-RUN] Would: build phel-doom.phar (v$NEW_VERSION), smoke-test it, checksum it,"
            log "[DRY-RUN]       git commit, tag v$NEW_VERSION, push, gh release create + attach PHAR + checksum"
        fi
        rollback
        log_ok "Dry-run complete - CHANGELOG.md + version.phel restored"
        exit 0
    fi

    log "\n${BOLD}Building PHAR${NC}"
    build_phar
    smoke_test_phar

    log "\n${BOLD}Committing${NC}"
    git_commit_release
    log_ok "Created release commit"

    log "\n${BOLD}Tagging${NC}"
    git_create_tag
    log_ok "Created tag v$NEW_VERSION"

    log "\n${BOLD}Pushing${NC}"
    git_push
    log_ok "Pushed $MAIN_BRANCH and v$NEW_VERSION"

    log "\n${BOLD}Creating GitHub release${NC}"
    create_github_release
    log_ok "GitHub release v$NEW_VERSION created"

    cleanup_backup
    echo ""
    log_ok "Release v$NEW_VERSION complete!"
}

main "$@"
