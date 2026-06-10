# Claude Code Guidelines — Chezmoi Dotfiles

**This file redirects to the main AI agent guidelines.**

All rules for Claude Code (and other AI agents) are maintained in a single source of truth:

**→ See: [AGENTS.md](AGENTS.md)**

## This Repository

This is a **chezmoi-managed Linux system configuration** repository (dotfiles):
- Shell configs (bash, zsh), editor (vim), git
- Window manager (i3), status bar (polybar), terminal (alacritty)
- Systemd user services (rclone sync, sshfs, syncthing)
- Display management (autorandr, xrandr)

> AI orchestration tools (wrappers, skills, AGENTS.md full rules) live in the separate **`ai-wrapper`** repo.

## Quick Reference

| Need | Where |
|------|-------|
| All AI rules and policies | `ai-wrapper` repo → `AGENTS.md` |
| Chezmoi naming/workflow | `chezmoi-workflow` skill |
| Sandbox security | `ai-sandboxing` skill |
| Code standards | `coding-standards` skill |
| Test writing | `qa-automation` skill |
| Code review process | `requesting-code-review` skill |
