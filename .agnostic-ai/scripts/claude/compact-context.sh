#!/bin/bash
# SessionStart hook: re-inject key context after compaction
cat <<'EOF'
## Context Reminder (post-compaction)

**phel-doom** — terminal raycaster in pure Phel. PHP 8.4+. Composer scripts drive everything.

- Layout: `src/commands/` (loop), `src/core/` (pure), `src/glue/` (wiring), `src/io/` (side effects).
- Tests: `composer test` (all) or `vendor/bin/phel test tests/<file>` (one).
- CI: `composer ci` = format-check + lint + test + build. Run before commit.
- Frame budget: cast + render < 5 ms target (see `docs/performance.md`).
- Convention: kebab-case Phel, `conj` over `put`, `defn-` for private, `;` line comments.
- Commits: conventional, `ref:` not `refactor:`. NEVER mention AI. Update `CHANGELOG.md` for `feat:`/`fix:`/`perf:`.
- PRs: assign `Chemaclass`, label by type, body uses `Closes #N`.
- Issues: do NOT auto-assign on create.
- Protected: `composer.lock`, `out/main.php`, `phel-config.php`, `.phel/cache/*`.
- Auto-format: `.phel` files via PostToolUse hook (`vendor/bin/phel format`).
EOF
