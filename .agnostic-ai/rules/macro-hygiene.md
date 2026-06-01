---
description: Macro-hygiene pitfalls for quasiquote, gensym, and expand-time evaluation
globs: src/**,tests/**,*.phel
---

# Macro Hygiene

Phel macros non-hygienic. `let`/`binding` names in macro body silently shadow homonymous globals when unquoted in `` ` ``. No error → wrong expansion.

## 1. Local names must not collide with referenced globals

```phel
;; bad — local `frame-stats` shadows global
(let [frame-stats (php/aget ctx :frame-stats)]
  `(update-stats ~frame-stats))

;; good — role suffix
(let [frame-stats-arg (php/aget ctx :frame-stats)]
  `(update-stats ~frame-stats-arg))
```

Convention: suffix macro-local bindings with role (`-arg`, `-flag`, `-val`, `-sym`, `-form`).

## 2. New symbols introduced into expansion need auto-gensym

```phel
`(let [acc 0] ~@body)    ; bad — captures user's `acc`
`(let [acc# 0] ~@body)   ; good
```

## 3. Expand-time vs runtime

Macro body runs expand-time. Only forms inside `` ` `` reach runtime. Splice computed values via `~`; identifiers must still resolve in caller ns.

## Checklist

- List every `let`-binding name in body
- Grep each against in-scope globals (own ns + required modules)
- Collision → suffix or `name#`
- New scope-introduced symbol → `name#`
- Add a test exercising recursion / self-reference (where shadow diverges from global)
