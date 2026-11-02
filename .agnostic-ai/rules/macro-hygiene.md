---
description: "Macro hygiene for quasiquote, gensym and expand-time evaluation; use when editing defmacro"
globs: src/**,tests/**,tools/**
---

# Macro hygiene

Phel macros are non-hygienic: a `let` or `binding` name in a macro body silently shadows a homonymous global when unquoted in `` ` ``. No error, wrong expansion.

1. Macro-local names must not collide with referenced globals. Suffix them by role (`-arg`, `-flag`, `-val`, `-sym`, `-form`):

```phel
;; bad: local shadows the global frame-stats
(let [frame-stats (php/aget ctx :frame-stats)] `(update-stats ~frame-stats))
;; good
(let [frame-stats-arg (php/aget ctx :frame-stats)] `(update-stats ~frame-stats-arg))
```

2. Symbols the expansion introduces need auto-gensym: `` `(let [acc# 0] ~@body) ``, not `acc`, which captures the caller's `acc`.
3. The macro body runs at expand time; only forms inside `` ` `` reach runtime. Splice computed values with `~`; identifiers must still resolve in the caller's namespace.

Checklist: list every `let` name in the body; grep each against in-scope globals (own ns and required modules); on collision suffix it or use `name#`; add a test with recursion or self-reference, where the shadow diverges from the global.
