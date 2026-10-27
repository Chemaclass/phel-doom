---
description: Launch the game to manually verify a change. Required smoke test for io/ work.
disable-model-invocation: false
allowed-tools: "Bash(PHEL_DOOM_SILENT=1 composer play:*), Bash(PHEL_DOOM_SILENT=1 make play:*)"
x-claude:
  argument-hint: "[check-list]"
---

# Play

Launch phel-doom to verify a change end-to-end.

## When to use

- Any change in `src/io/render.phel` or `src/commands/play.phel`.
- New key binding or input behavior (`controls.phel`, `input.phel`).
- Audio change (`sound.phel`).
- HUD or pause overlay change.
- Final check before opening PR for player-visible work.

## Procedure

1. Launch:
   ```bash
   PHEL_DOOM_SILENT=1 composer play
   ```
   Sound stays off. For an audio change, ask the user to check the sound by ear.

2. Check the **golden path** from the argument (or default smoke: load → move → shoot → take damage → die → restart).

3. Check **edge cases** for the feature you changed.

4. Watch for **regressions in adjacent features** — pause, HUD, audio, render artifacts.

5. Type-checking and tests verify code correctness, not feature correctness. If `/play` cannot be run in this environment, say so explicitly — do NOT claim success.

## Report

- ✓ / ✗ per checked item.
- Screenshot path if a visual issue found (capture manually).
- Concrete next step if a regression appears.
