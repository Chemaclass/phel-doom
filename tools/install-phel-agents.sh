#!/usr/bin/env bash
# Install the Phel agent docs that ship with the installed Phel, with
# agnostic-ai as the only owner of the phel-lang skill.
#
# `phel agent-install` copies the .agents/ docs tree, but it also writes its
# skill straight into a tool directory that agnostic-ai generates. Left there,
# the next sync replaces the newer guide with the older source copy. So the
# bundled guide becomes the agnostic-ai source instead, and sync hands it to
# every target (Claude and Codex).
set -euo pipefail

guide=vendor/phel-lang/phel-lang/resources/agents/skills/claude/phel-lang/SKILL.md
source_skill=.agnostic-ai/skills/phel-lang/SKILL.md

[ -f "$guide" ] || { echo "install-phel-agents: $guide not found (phel layout changed?)"; exit 2; }

vendor/bin/phel agent-install claude -n --quiet --force

# The installer's own copies: the Claude skill sync writes, and the
# per-platform templates it leaves under .agents/skills/, the folder Codex
# reads project skills from.
rm -f .claude/skills/phel-lang/SKILL.md
rm -rf .agents/skills/aider .agents/skills/claude .agents/skills/codex \
  .agents/skills/copilot .agents/skills/cursor .agents/skills/gemini
rm -f .agents/skills/INSTALL.md .agents/skills/INSTALL.md.pre-phel.bak

sed '/^<!-- phel-agents v[0-9.]* -->$/d' "$guide" > "$source_skill"

if command -v agnostic-ai >/dev/null 2>&1; then
  agnostic-ai sync -q
fi
