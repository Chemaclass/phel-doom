---
description: Run phel-doom tests with smart scope filtering
argument-hint: "[scope-or-file]"
disable-model-invocation: true
allowed-tools: "Bash(composer *), Bash(vendor/bin/phel *)"
---

# Quick Test Runner

## Scope mapping

Run the **minimum** scope for the changed files.

| Changed | Command |
|---------|---------|
| `src/core/**` or `src/glue/**` | `composer test` |
| `src/io/**` (no test) | `composer play` for manual smoke (use `/play`) |
| One file, one module | `vendor/bin/phel test tests/<layer>/<name>-test.phel` |
| Format/lint only | `composer format-check && composer lint` |
| Everything (pre-commit) | `composer ci` |

## Composer scripts

```bash
composer test          # phel tests (PHEL_DOOM_SILENT=1 set)
composer format        # auto-format
composer format-check  # dry-run format check
composer lint          # static analysis on src tests
composer ci            # format-check + lint + test + build
composer build         # build out/main.php
composer play          # launch game (interactive)
composer repl          # phel repl
composer doctor        # env check
```

## Instructions

1. Empty `$ARGUMENTS` or `all`:
   ```bash
   composer test
   ```

2. Known scope:
   - `ci` → `composer ci`
   - `lint` → `composer lint`
   - `format` → `composer format-check`
   - `quick` → `composer test`
   - `build` → `composer build`

3. Looks like file path:
   ```bash
   vendor/bin/phel test "$ARGUMENTS"
   ```

4. Looks like module name (e.g. `engine`):
   ```bash
   vendor/bin/phel test tests/core/$ARGUMENTS-test.phel 2>/dev/null \
   || vendor/bin/phel test tests/glue/$ARGUMENTS-test.phel 2>/dev/null \
   || vendor/bin/phel test tests/commands/$ARGUMENTS-test.phel
   ```

5. Report pass/fail count clearly.
