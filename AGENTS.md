# AI Agent Rules — Chezmoi Dotfiles

These rules apply to **Claude Code** (and any other AI agents) working in this repository.

**User**: Vadim (le0nRoy) | **Platform**: Linux (Arch-based) | **Shell**: bash (primary)

---

## Where to Find Resources

| Resource | Location |
|----------|----------|
| User-level skills | `~/.agents/skills/` (symlinked from `~/.claude/skills/`) |
| Installed plugins | `~/.claude/settings.json` → `enabledPlugins` |
| Plugin marketplace | `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/` |

**Key skills (always relevant):**
- `coding-standards` — naming, nesting, no magic numbers, no race conditions
- `qa-automation` — test structure, isolation, integration patterns
- `requesting-code-review` — review process + legal compliance checks
- `chezmoi-workflow` — **required when working in this repo**
- `common-automation-verifier` — project setup verification

---

## 1. Read Before Writing

- Read files completely before modifying them
- Understand context, patterns, and existing conventions
- Check `git log --oneline -10` and `git status` at session start
- Look for `README`, `CONTRIBUTING`, `AGENTS.md`, `CLAUDE.md`, `TODO.md`

---

## 2. Preserve User Preferences

- Respect existing code style and formatting (indentation, naming, structure)
- Follow project-specific conventions over general guidelines
- **Do not revert user's SVC changes between sessions**: if the user removed files from stage, made fixes, or reset commits between sessions — honor that state. Check `git status` and `git log` before acting.
- If you find unexpected state (untracked files, uncommitted changes, detached HEAD) — investigate and ask before overwriting

---

## 3. Security First

- Never commit secrets, credentials, API keys, private keys, or tokens
- Validate all paths before operations (no directory traversal)
- Ask before executing destructive commands (`rm -rf`, `mkfs`, `dd`, etc.)
- Never modify file permissions arbitrarily

---

## 4. Test and Validate

- Validate syntax before claiming completion: `bash -n script.bash`, `python -m py_compile`, `jq .`
- Use dry-run modes when available: `chezmoi diff` before `chezmoi apply`
- Run `shellcheck` if available for bash scripts
- Verify changes work as intended before reporting done

---

## 5. Git Workflow

### Commits During Work

Commits are allowed during work. Commit at logical checkpoints, not just at the end.

**Commit message format:**
```
type: brief summary (≤50 chars)

Optional explanation of what and why (≤72 chars per line).
```
Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

### Branch Policy

- **Never commit directly to `main`** — use feature branches (`feat/`, `fix/`, `docs/`, `chore/`)
- Never push without explicit user instruction
- See `using-git-worktrees` skill for isolated feature work
- See `finishing-a-development-branch` skill for branch completion

### Session Squash (Important)

At the end of a work session, **squash all session commits** so the user can review one clean diff:

```bash
SESSION_START_SHA=<sha before this session>
git log --oneline ${SESSION_START_SHA}..HEAD
git rebase -i ${SESSION_START_SHA}
```

Present to user:
```
Session complete. N commits → squashed to 1.
Review: git diff {session_start_sha} HEAD
```

### Do Not

- Commit directly to `main` or force-push to `main`/`master`
- `git reset --hard` or discard uncommitted changes without asking
- Re-stage files the user removed from staging

---

## 6. Documentation Maintenance

Keep documentation up to date as part of completing any task.

| Doc type | Where | When to update |
|----------|-------|----------------|
| High-level design | `docs/design/` | Architecture changes |
| Feature design | `docs/features/<name>.md` | New features, significant changes |
| Onboarding (human) | `README.md` | Setup/workflow changes |
| Onboarding (AI) | `AGENTS.md`, `CLAUDE.md` | Policy/convention changes |

---

## 7. Communication

- **Be specific**: reference `file.ext:line_number` not just "the file"
- **Explain reasoning**: why, not just what
- **Mention side effects**: what else might be affected by a change
- **Provide test commands**: help the user verify changes
- Do not ask multiple questions in one message — ask the most important one first

---

## 8. Prohibited Actions

**NEVER:**
- Commit secrets, credentials, API keys, tokens, or private keys
- Commit directly to `main`
- Delete files without confirmation
- Execute destructive commands without confirmation
- Modify dotfiles without understanding their deployment impact (chezmoi prefixes)
- Stage or re-stage files the user deliberately removed from staging
- Ignore existing uncommitted user changes — always check `git status` first

---

## 9. Recommended Actions

**ALWAYS:**
- Read files before modifying
- Check `git status` at the start of every session
- Preserve existing patterns and conventions
- Validate syntax before completing tasks
- Communicate with file:line references
- Update relevant documentation when changing behavior
- When in doubt about impact on user's system — ask first

---

## 10. This Repository (Chezmoi-Specific)

See **`chezmoi-workflow`** skill for:
- File naming conventions (`dot_`, `executable_`, `private_`, `.tmpl`)
- Deployment workflow (`chezmoi diff`, `chezmoi apply`)
- Repository structure
- Run scripts (`run_once_`, `run_always_`)

**Remember:** Changes in this repo don't deploy until `chezmoi apply`. Always use `chezmoi diff` to preview before applying.
