# AI Agent Rules

> **Canonical rules** are maintained in the [`ai-wrapper`](https://github.com/Le0nRoy/ai-wrapper) repo (`AGENTS.md`).
> This is a minimal stub deployed by `chezmoi-dotfiles`. If the `ai-wrapper` repo is also applied,
> its `AGENTS.md` (the full version) will overwrite this file at `~/AGENTS.md`.

**User**: Vadim (le0nRoy) | **Platform**: Linux (Arch-based) | **Shell**: bash (primary)

---

## Minimal Rules (Fallback)

1. Never commit secrets, credentials, API keys, private keys, or tokens.
2. Read files completely before modifying them.
3. Check `git status` at the start of every session.
4. Ask before destructive operations (`rm -rf`, `git reset --hard`, `mkfs`, etc.).
5. Validate bash syntax: `bash -n script.bash` before completing tasks.
6. Respect existing code style and conventions.
7. Do not push without explicit user instruction.

---

## This Repository

This is a `chezmoi-managed` **Linux system configuration** repository (dotfiles).
AI orchestration tools, skills, and sandbox wrappers live in the separate `ai-wrapper` repo.

| Need | Location |
|------|----------|
| Full AI rules | `ai-wrapper` repo → `AGENTS.md` |
| Agent skills | `ai-wrapper` repo → `dot_agents/skills/` |
| Sandbox wrappers | `ai-wrapper` repo → `bin/executable_*_wrapper.bash` |
| Chezmoi workflow | `chezmoi-workflow` skill (if `ai-wrapper` installed) |

---

## Chezmoi-Specific

Changes in this repo don't deploy until `chezmoi apply`. Always use `chezmoi diff` to preview before applying.

See `chezmoi-workflow` skill for file naming conventions (`dot_`, `executable_`, `private_`, `.tmpl`).
