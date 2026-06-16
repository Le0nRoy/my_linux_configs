# Context: Repo Split — ai-wrapper

**Date:** 2026-06-10
**Plan file:** `docs/plans/2026-06-10-repo-split-ai-wrapper.md`

---

## Confirmed Architecture Facts

1. **Zero helper dependency** — verified: none of the 7 AI wrapper scripts source `bin/helper/` modules. ai-wrapper is fully self-contained.

2. **Deployment chain**: `executable_claude_wrapper.bash` → sources `ai_agent_universal_wrapper.bash` → sources `ai_wrapper_data/claude_wrapper_lib.bash` → sources `ai_wrapper_data/ai_wrapper_lib.bash`. All four files live in `~/bin/` after `chezmoi apply`.

3. **Skills discovery**: Claude Code reads from `~/.claude/skills/`. `run_always_register-agent-skills.bash` creates `~/.claude/skills -> ~/.agents/skills`. Skills are deployed from `dot_agents/skills/` → `~/.agents/skills/`.

4. **bulletproof submodule**: `https://github.com/artemiimillier/bulletproof.git` at commit `49e9c28` (tag `v5.0.0-8-g49e9c28`).

5. **chezmoi.toml**: `autoCommit = true` and `autoPush = true`. Always use `chezmoi apply --dry-run` first during testing.

6. **docs/ not deployed**: `docs/` is in `.chezmoiignore` — docs stay in repo, never touch `~/`.

7. **Supersedes**: `docs/plans/2026-04-02-ai-rules-repository-migration.md`. The prior plan abandoned submodules due to chezmoi compatibility risks; after evaluation, the git submodule approach was formally adopted (2026-06-14) because: (a) the `ai-wrapper/` path is excluded via `.chezmoiignore` so chezmoi never tries to deploy submodule files as dotfiles; (b) the submodule is initialized and applied by a dedicated `run_always_` script, keeping the two repos independent at the chezmoi level while sharing a git link for convenient co-deployment.

---

## Key File Paths After Split

| Path | Repo | Deployed To |
|------|------|-------------|
| `bin/ai_agent_universal_wrapper.bash` | ai-wrapper | `~/bin/ai_agent_universal_wrapper.bash` |
| `bin/executable_claude_wrapper.bash` | ai-wrapper | `~/bin/claude_wrapper` |
| `bin/executable_codex_wrapper.bash` | ai-wrapper | `~/bin/codex_wrapper` |
| `bin/executable_cursor_agent_wrapper.bash` | ai-wrapper | `~/bin/cursor_agent_wrapper` |
| `bin/ai_wrapper_data/` | ai-wrapper | `~/bin/ai_wrapper_data/` |
| `dot_agents/skills/` | ai-wrapper | `~/.agents/skills/` |
| `dot_agents/skills/bulletproof/` | ai-wrapper | `~/.agents/skills/bulletproof/` (submodule) |
| `run_always_register-agent-skills.bash` | ai-wrapper | executes on `chezmoi apply` |
| `AGENTS.md` | ai-wrapper (canonical) | `~/AGENTS.md` (full rules) |
| `AGENTS.md` | chezmoi-dotfiles (stub) | `~/AGENTS.md` (fallback, overwritten by ai-wrapper) |
| `bin/helper/` | chezmoi-dotfiles | `~/bin/helper/` |
| `dot_config/i3/` | chezmoi-dotfiles | `~/.config/i3/` |

---

## Two-Repo Apply Workflow

```bash
# Single apply — run_always_install-ai-wrapper.bash handles AI-Wrapper automatically
chezmoi apply
```

The `run_always_install-ai-wrapper.bash` script initializes the `ai-wrapper` submodule and applies it as a secondary chezmoi source in one step. The ai-wrapper `AGENTS.md` overwrites the dotfiles stub because it's applied second.

---

## How to Debug

### Wrapper can't find ai_agent_universal_wrapper.bash

It uses `source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"`.
The file must be in `~/bin/` alongside the wrappers. Check: `ls ~/bin/ai_agent_universal_wrapper.bash`

### Skills not appearing in Claude Code

```bash
ls ~/.agents/skills/
ls -la ~/.claude/skills
readlink ~/.claude/skills  # must be -> ~/.agents/skills
```

---

## Quick Validation Checklist

```bash
# Syntax check all wrapper scripts
for f in ~/bin/claude_wrapper ~/bin/codex_wrapper ~/bin/cursor_agent_wrapper \
          ~/bin/setup_ai_kube_access ~/bin/setup_kind; do
    bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# Verify skills symlink
readlink ~/.claude/skills   # expected: ~/.agents/skills

# Verify bulletproof skill
ls ~/.agents/skills/bulletproof/SKILL.md

# Verify full AGENTS.md deployed
head -3 ~/AGENTS.md   # should NOT say "minimal stub"
```
