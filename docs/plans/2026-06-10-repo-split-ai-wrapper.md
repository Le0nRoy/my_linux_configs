# Repo Split: ai-wrapper Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the single chezmoi repo into two repos — `chezmoi-dotfiles` (Linux/system configs) and `ai-wrapper` (AI orchestration tools, skills, sandbox wrappers) — with chezmoi as the deployment mechanism for both.

**Architecture:** The ai-wrapper repo is built as a clean new repo (fresh history, no Linux config commits). The current repo is cleaned of AI files after validation. Both repos use chezmoi for deployment. The ai-wrapper repo is designed to be self-contained: someone who only clones it can run `chezmoi apply` and get the AI tools without any Linux-specific configs.

**Tech Stack:** git, chezmoi, bash

---

## Pre-Flight Checklist

- Current repo is at `$HOME/.local/share/chezmoi`
- The bulletproof submodule remote: `https://github.com/artemiimillier/bulletproof.git` at commit `49e9c28`
- `docs/` is ignored by chezmoi (not deployed) — stays in chezmoi-dotfiles only
- `AGENTS.md` and `CLAUDE.md` are deployed to `~/` — they move to ai-wrapper
- `chezmoi.toml` has `autoCommit = true` and `autoPush = true` — use `chezmoi apply --dry-run` during testing
- `bin/helper/` modules have **zero imports** from AI wrapper scripts — ai-wrapper is fully self-contained

---

## File Ownership Map

| Task | Files Owned |
|------|-------------|
| Task 1 | `$AI_WRAPPER_REPO/` (new repo, built in `.git/staging/ai-wrapper/`) |
| Task 2 | `$CURRENT_REPO/AGENTS.md`, `CLAUDE.md` (stubs replacing originals) |
| Task 3 | `$CURRENT_REPO/` — remove AI files via git rm |
| Task 4 | (remote setup, no local file ownership) |
| Task 5 | (validation only, no file modifications) |

---

## Environment Variables

```bash
export CURRENT_REPO="$HOME/.local/share/chezmoi"
export AI_WRAPPER_REPO="$CURRENT_REPO/.git/staging/ai-wrapper"
```

---

## Task 1: Build ai-wrapper repo in staging area

**Files:** Creates `$AI_WRAPPER_REPO/` (entire new repo)

The new repo is built at `.git/staging/ai-wrapper/` which is inside `.git/` and therefore never tracked by the parent repo.

**Step 1: Initialize git repo**

```bash
git -C "$AI_WRAPPER_REPO" init
git -C "$AI_WRAPPER_REPO" checkout -b main
```

**Step 2: Copy AI wrapper files**

```bash
# Core wrapper scripts
cp "$CURRENT_REPO/bin/ai_agent_universal_wrapper.bash" "$AI_WRAPPER_REPO/bin/"
cp "$CURRENT_REPO/bin/executable_claude_wrapper.bash" "$AI_WRAPPER_REPO/bin/"
cp "$CURRENT_REPO/bin/executable_codex_wrapper.bash" "$AI_WRAPPER_REPO/bin/"
cp "$CURRENT_REPO/bin/executable_cursor_agent_wrapper.bash" "$AI_WRAPPER_REPO/bin/"
cp "$CURRENT_REPO/bin/executable_setup_ai_kube_access.bash" "$AI_WRAPPER_REPO/bin/"
cp "$CURRENT_REPO/bin/executable_setup_kind.bash" "$AI_WRAPPER_REPO/bin/"
cp -r "$CURRENT_REPO/bin/ai_wrapper_data/" "$AI_WRAPPER_REPO/bin/"

# Agent skills (chezmoi source: dot_agents -> ~/.agents)
cp -r "$CURRENT_REPO/dot_agents/" "$AI_WRAPPER_REPO/dot_agents/"

# Chezmoi run scripts
cp "$CURRENT_REPO/run_always_register-agent-skills.bash" "$AI_WRAPPER_REPO/"
cp "$CURRENT_REPO/run_once_migrate_wrapper_data_dir.bash" "$AI_WRAPPER_REPO/"

# AI rules files
cp "$CURRENT_REPO/AGENTS.md" "$AI_WRAPPER_REPO/"
cp "$CURRENT_REPO/CLAUDE.md" "$AI_WRAPPER_REPO/"
```

**Step 3: Register bulletproof as submodule**

```bash
git -C "$AI_WRAPPER_REPO" submodule add \
  https://github.com/artemiimillier/bulletproof.git \
  dot_agents/skills/bulletproof
```

**Step 4: Create .chezmoiignore**

```
# AI agent runtime directories — managed by agents, not chezmoi
.claude
.claude.json
.codex
.cursor
.config/cursor
.local/share/cursor-agent

# Repository documentation — not deployed to ~/
README.md
docs/
TODO.md
```

**Step 5: Create README.md** (see context doc for full content)

**Step 6: Update AGENTS.md** — prepend a note identifying the repo

**Step 7: Update CLAUDE.md** — update "This Repository" section

**Step 8: Update run_always_register-agent-skills.bash** — append submodule init block

**Step 9: Initial commit**

```bash
git -C "$AI_WRAPPER_REPO" add -A
git -C "$AI_WRAPPER_REPO" commit -m "feat: initial ai-wrapper repo (split from chezmoi-dotfiles)"
```

---

## Task 2: Create AGENTS.md and CLAUDE.md stubs in current repo

**Files:** `$CURRENT_REPO/AGENTS.md`, `$CURRENT_REPO/CLAUDE.md`

These are deployed to `~/` via chezmoi. After the split, the stub versions direct users to the ai-wrapper repo for full AI rules.

**AGENTS.md stub content:**

```markdown
# AI Agent Rules

> **Canonical rules** are maintained in the `ai-wrapper` repo.
> This is a minimal stub deployed by `chezmoi-dotfiles`.

## Minimal Rules (Fallback)

1. Never commit secrets, credentials, API keys, or tokens.
2. Read files before modifying them.
3. Check `git status` at the start of every session.
4. Ask before destructive operations (`rm -rf`, `git reset --hard`).
5. Validate bash syntax: `bash -n script.bash` before completing tasks.

## This Repository

This is a `chezmoi-managed` **Linux system configuration** repository.
AI orchestration tools live in the separate `ai-wrapper` repo.
```

**CLAUDE.md stub content:** redirect pointing to ai-wrapper.

---

## Task 3: Remove AI files from current repo

**Files:** tracked AI files in `$CURRENT_REPO`

```bash
git -C "$CURRENT_REPO" rm -r \
  bin/ai_agent_universal_wrapper.bash \
  bin/executable_claude_wrapper.bash \
  bin/executable_codex_wrapper.bash \
  bin/executable_cursor_agent_wrapper.bash \
  bin/executable_setup_ai_kube_access.bash \
  bin/executable_setup_kind.bash \
  bin/ai_wrapper_data/ \
  dot_agents/ \
  run_always_register-agent-skills.bash \
  run_once_migrate_wrapper_data_dir.bash

git -C "$CURRENT_REPO" commit -m "chore: remove AI wrapper files (moved to ai-wrapper repo)"
```

---

## Task 4: Set up remotes and push

Create two new GitHub repos first:
- `https://github.com/Le0nRoy/chezmoi-dotfiles`
- `https://github.com/Le0nRoy/ai-wrapper`

Then push each.

---

## Task 5: Validate both repos deploy correctly

See context doc for full validation checklist. Key checks:
- `chezmoi diff` shows no unexpected deletions
- All wrapper scripts pass `bash -n`
- `~/.claude/skills` → `~/.agents/skills` symlink works
- `~/AGENTS.md` is full version (from ai-wrapper, applied second)
- bulletproof skill initialized at `~/.agents/skills/bulletproof/`

---

## Design Decisions

### No git history preservation
Clean new repo. AI wrapper's commit history was entangled with Linux config commits; a clean start is more readable for external contributors.

### Helper dependency
Zero dependency confirmed — none of the 7 AI wrapper files source `bin/helper/` modules.

### AGENTS.md placement
Canonical version lives in ai-wrapper. Dotfiles carries a minimal stub. When both are applied (ai-wrapper second), the full version wins at `~/AGENTS.md`.

### Two-repo chezmoi workflow
```bash
chezmoi apply                                                         # dotfiles first
CHEZMOI_SOURCE_DIR="$HOME/.local/share/ai-wrapper" chezmoi apply     # ai-wrapper second
```

### Rollback
Old repo archived on GitHub as `my_linux_configs`. Restore:
```bash
cp -r "$HOME/.local/share/chezmoi.bak" "$HOME/.local/share/chezmoi"
chezmoi apply
```
