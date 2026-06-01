---
description: Auto-format Phel and lint
argument-hint: "[file-path]"
disable-model-invocation: true
allowed-tools: "Read, Edit, Bash(composer *), Bash(vendor/bin/phel *)"
target: claude
---

# Fix Code Quality

## Instructions

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
