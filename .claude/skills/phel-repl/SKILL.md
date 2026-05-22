---
description: Evaluate a Phel expression to verify behavior without writing a test
argument-hint: "<phel expression>"
disable-model-invocation: true
allowed-tools: "Bash(vendor/bin/phel *), Bash(echo *), Bash(timeout *), Read, Write"
---

# Phel REPL

Evaluate ad-hoc Phel expressions. Use to confirm syntax, fn shape, or quick math.

## Instructions

1. Take expression from `$ARGUMENTS`. Ask if empty.

2. Write a one-shot file (REPL eval-from-stdin is unreliable):
   ```bash
   cat > /tmp/phel-doom-repl.phel <<'EOF'
   (ns phel-doom-repl)
   (println $ARGUMENTS)
   EOF
   timeout 10 vendor/bin/phel run /tmp/phel-doom-repl.phel
   ```

3. If the expression needs project namespaces:
   ```bash
   cat > /tmp/phel-doom-repl.phel <<'EOF'
   (ns phel-doom-repl
     (:require phel-doom.modules.core.engine :as engine))
   (println (engine/cast-ray ...))
   EOF
   timeout 10 vendor/bin/phel run /tmp/phel-doom-repl.phel
   ```

4. Report result. If error, explain layer (lexer / analyzer / runtime).

## Examples

```
/phel-repl (+ 1 2)
/phel-repl (map inc [1 2 3])
/phel-repl (let [w 80 h 24] (* w h))
```

## When to NOT use this

- Anything you want to persist → write a `deftest` in `tests/`.
- Stateful game behavior → use `/play`.
