# AI Rules Repository Migration Plan

**Date:** 2026-04-02
**Goal:** Extract all AI agent rules and skills into a standalone repository, connected to the dotfiles repo as a git submodule.

---

## Why

Currently, AI agent rules (`AGENTS.md`, skills in `dot_agents/skills/`) live inside the chezmoi dotfiles repository. This creates coupling between system configuration (dotfiles) and AI workflow definitions (rules + skills). Separating them allows:

- **Reuse across machines**: The AI rules repo can be cloned independently, without requiring the full dotfiles setup.
- **Separate versioning**: Dotfiles and AI rules evolve at different rates; separate history is cleaner.
- **Sharing**: The rules and skills can be made public or shared with other users without exposing personal dotfiles.
- **Cleaner structure**: The dotfiles repo becomes focused on system config; the AI rules repo owns all AI workflow content.

---

## Target Architecture

```
~/.local/share/chezmoi/            ← dotfiles repo (this repo)
├── dot_agents/
│   └── skills/                    ← submodule → ai-rules repo
├── AGENTS.md                      ← symlink or chezmoi template sourcing from submodule
└── bin/claude_wrapper_data/       ← stays here (system-specific wrapper config)

~/projects/ai-rules/               ← standalone ai-rules repo
├── AGENTS.md                      ← canonical AI rules file
├── skills/                        ← all skill definitions
│   ├── orchestrator-mode/
│   ├── bulletproof/               ← (already a submodule, stays as-is)
│   ├── writing-plans/
│   ├── subagent-driven-development/
│   ├── requesting-code-review/
│   ├── using-git-worktrees/
│   ├── finishing-a-development-branch/
│   ├── executing-plans/
│   └── find-skills/
└── README.md
```

---

## Migration Tasks

### Task 1: Create the `ai-rules` repository

**Files:**
- Create: `~/projects/ai-rules/` (new git repo)

**Steps:**

1. Create and initialize the repo:
   ```bash
   mkdir -p ~/projects/ai-rules
   cd ~/projects/ai-rules
   git init
   git remote add origin <remote-url>   # e.g. github.com/username/ai-rules
   ```

2. Copy `AGENTS.md` from the dotfiles repo:
   ```bash
   cp ~/.local/share/chezmoi/AGENTS.md ~/projects/ai-rules/AGENTS.md
   ```

3. Copy the skills (excluding the bulletproof submodule, which will be re-added as a submodule):
   ```bash
   cp -r ~/.local/share/chezmoi/dot_agents/skills/* ~/projects/ai-rules/skills/
   rm -rf ~/projects/ai-rules/skills/bulletproof   # will be added as submodule
   ```

4. Re-add bulletproof as a submodule:
   ```bash
   cd ~/projects/ai-rules
   git submodule add <bulletproof-remote-url> skills/bulletproof
   ```

5. Create `README.md` describing the repo purpose and structure.

6. Initial commit:
   ```bash
   git add .
   git commit -m "feat: initial AI rules and skills repository"
   git push -u origin main
   ```

**Acceptance criteria:**
- `~/projects/ai-rules/` is a valid git repo with the skills and AGENTS.md
- `skills/bulletproof/` is a submodule pointing to the correct upstream

---

### Task 2: Connect `ai-rules` as a submodule in the dotfiles repo

**Files:**
- Modify: `.gitmodules`
- Modify: `dot_agents/skills/` (replace with submodule)
- Create: chezmoi script to initialize submodule on `chezmoi apply`

**Steps:**

1. Remove the current `dot_agents/skills/` directory contents (they move to the submodule):
   ```bash
   cd ~/.local/share/chezmoi
   git rm -r dot_agents/skills/orchestrator-mode dot_agents/skills/writing-plans \
     dot_agents/skills/subagent-driven-development dot_agents/skills/requesting-code-review \
     dot_agents/skills/using-git-worktrees dot_agents/skills/finishing-a-development-branch \
     dot_agents/skills/executing-plans dot_agents/skills/find-skills
   ```

2. Add `ai-rules` as a submodule at `dot_agents/skills/`:
   ```bash
   git submodule add <ai-rules-remote-url> dot_agents/ai-rules
   ```

3. Create a symlink so `dot_agents/skills/` still resolves correctly:
   ```bash
   ln -s ai-rules/skills dot_agents/skills
   git add dot_agents/skills
   ```
   Or restructure so `dot_agents/` directly contains the submodule at `dot_agents/skills/`.

4. Commit:
   ```bash
   git add .gitmodules dot_agents/
   git commit -m "refactor: replace skills dir with ai-rules submodule"
   ```

**Acceptance criteria:**
- `dot_agents/skills/` resolves to the skills in the `ai-rules` submodule
- `chezmoi apply` still deploys the skills correctly
- `git submodule update --init --recursive` populates the skills

---

### Task 3: Move `AGENTS.md` to the `ai-rules` repo and reference it from the dotfiles repo

**Files:**
- Modify: `AGENTS.md` in dotfiles repo (replace with symlink or chezmoi template)
- Canonical location: `dot_agents/ai-rules/AGENTS.md` (via submodule)

**Option A — Symlink (simpler):**
```bash
# In chezmoi source dir
rm AGENTS.md
ln -s dot_agents/ai-rules/AGENTS.md AGENTS.md
```
Note: chezmoi does not follow symlinks in the source dir by default. May need `.chezmoiignore` adjustment or a chezmoi script to create the symlink on the target machine.

**Option B — Chezmoi template:**
```bash
# AGENTS.md.tmpl that includes content from the submodule path
```
Complexity: requires chezmoi template syntax and the submodule to be initialized before `chezmoi apply`.

**Option C — Keep a stub in dotfiles, canonical in submodule (recommended):**
Keep `AGENTS.md` in the dotfiles repo as a short redirect file pointing to `dot_agents/ai-rules/AGENTS.md`. The canonical rules live in the `ai-rules` repo.

**Acceptance criteria:**
- `AGENTS.md` in dotfiles repo is either the canonical file or clearly points to the canonical location
- AI agents reading `AGENTS.md` from the dotfiles root find the correct content

---

### Task 4: Update `run_always_register-agent-skills.bash` for submodule initialization

**Files:**
- Modify: `run_always_register-agent-skills.bash`

The chezmoi post-apply hook currently assumes skills are in `~/.agents/skills/`. After the migration, it must also ensure the submodule is initialized:

```bash
# After existing symlink logic, add:
cd "${CHEZMOI_SOURCE_DIR}" && git submodule update --init --recursive
```

Or add a dedicated `run_always_init-submodules.bash` chezmoi script.

**Acceptance criteria:**
- `chezmoi apply` on a fresh machine initializes the `ai-rules` submodule
- Skills are available at `~/.agents/skills/` after `chezmoi apply`

---

### Task 5: Update wrapper prompts and documentation

**Files:**
- Modify: `bin/claude_wrapper_data/orchestrator-prompt.md` — update any paths if needed
- Modify: `CLAUDE.md` — update quick reference table
- Modify: `AGENTS.md` (stub) — note canonical location

**Steps:**
1. Update `CLAUDE.md` quick reference to point to `ai-rules` repo for skills
2. Update `AGENTS.md` resource table with new skill locations
3. Update `TODO.md` to mark this task in progress / complete

**Acceptance criteria:**
- All documentation reflects the new structure
- No stale paths to old skill locations

---

## Open Questions

1. **Remote URL for `ai-rules`**: Where will the repo be hosted? (GitHub, GitLab, private)
2. **Visibility**: Should the `ai-rules` repo be public? (Skills contain no secrets; AGENTS.md contains no secrets)
3. **Bulletproof submodule**: Currently tracked at `dot_agents/skills/bulletproof` — its remote URL needs to be confirmed before Task 1 step 4.
4. **`AGENTS.md` strategy**: Option A, B, or C from Task 3? Option C (stub + canonical in submodule) is recommended but requires deciding on the stub content.
5. **chezmoi submodule support**: chezmoi has limited native support for submodules in the source directory. Testing is needed to confirm `chezmoi apply` works correctly with nested submodules.

---

## Risk and Mitigation

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| chezmoi breaks on submodule-in-source | Medium | Test on dev machine before applying to main; keep git backup |
| Skills temporarily unavailable during migration | Low | Perform migration when not actively using AI tools |
| Bulletproof submodule remote URL unknown | Low | Check `.gitmodules` in current repo before starting |
| `chezmoi apply` on fresh machine misses submodule init | Medium | Add submodule init to the chezmoi post-apply hook (Task 4) |
