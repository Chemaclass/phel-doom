---
description: Auto-format Phel and lint
argument-hint: "[file-path]"
disable-model-invocation: true
allowed-tools: "Read, Edit, Bash(composer *), Bash(vendor/bin/phel *)"
target: claude
---

# Fix Code Quality

## Instructions

0. If an edit left a form unreadable (formatter or lint dies on a file),
   locate the unbalanced `()` / `[]` / `{}` first - it counts through the
   lexer, so parens in strings, comments and regexes never mislead it:
   ```bash
   vendor/bin/phel balance src tests          # report
   vendor/bin/phel balance --fix "$ARGUMENTS" # append the missing closers
   ```
   `--fix` refuses anything with more than one plausible repair (a surplus
   closer, an unterminated string); fix those by hand.

1. Auto-format every `.phel` file:
   ```bash
   composer format
   ```
   Or single file:
   ```bash
   vendor/bin/phel format "$ARGUMENTS"
   ```

2. Lint:
   ```bash
   composer lint
   ```

3. Run tests to confirm nothing broke:
   ```bash
   composer test
   ```

4. Summarize: what was fixed, anything remaining that needs human attention.
