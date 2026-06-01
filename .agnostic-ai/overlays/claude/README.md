# Claude Code project config

Claude Code-native config for phel-doom. Multi-agent setup tuned for a pure-Phel terminal game.

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Project entrypoint loaded into every session. |
| `settings.json` | Permissions, hooks, status line config. |
| `settings.local.json` | Local-only allowances. Git-ignored. |
| `hooks/` | Auto-format on Edit/Write, protect files, post-compact reminder. |
| `agents/` | Subagent prompts. Spawn via Agent tool. |
| `skills/` | Slash-command workflows. Invoke via `/name`. |
| `rules/` | Scoped conventions auto-loaded by path glob. |

Shared repo policy stays in root `README.md` / `docs/contributing.md`. This folder is tooling, not gameplay docs.
