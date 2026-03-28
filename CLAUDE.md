# Claude Code Guidelines — Chezmoi Dotfiles & User-Level AI Policies

**This file redirects to the main AI agent guidelines.**

All rules for Claude Code (and other AI agents) are maintained in a single source of truth:

**→ See: [AGENTS.md](AGENTS.md)**

## This Repository

This is a **chezmoi-managed dotfiles repository** containing:
- System configuration files deployed to `~/` via `chezmoi apply`
- User-level AI agent policies (`AGENTS.md`) deployed system-wide
- User-level skills (`~/.agents/skills/`) for AI workflow automation
- AI orchestration configs (`bin/claude_wrapper_data/`)

## Quick Reference

| Need | Where |
|------|-------|
| All rules and policies | `AGENTS.md` |
| Chezmoi naming/workflow | `chezmoi-workflow` skill |
| Sandbox security | `ai-sandboxing` skill |
| Code standards | `coding-standards` skill |
| Test writing | `qa-automation` skill |
| Code review process | `requesting-code-review` skill |
| Agent role descriptions | `bin/claude_wrapper_data/agents/` |
