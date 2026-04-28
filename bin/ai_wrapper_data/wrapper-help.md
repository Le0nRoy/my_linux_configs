# Claude Wrapper Help

This wrapper provides an interactive menu for starting Claude CLI sessions with
optional orchestration workflows.

## Menu Options

### 1) Start orchestration
Launches Claude with the `orchestrator-mode` skill pre-loaded as a system prompt.
Use for multi-phase development workflows: plan → implement → test → review → merge.

**Phases:**
- Phase 0: Project verification
- Phase 1: Planning (produces `docs/plans/YYYY-MM-DD-<feature>.md`)
- Phase 2: Implementation (TDD, per-task subagents)
- Phase 3: Testing (test plan + automated tests)
- Phase 4: Code review
- Phase 5: Documentation
- Phase 6: Finalization (merge options)

### 2) Start bulletproof
Launches Claude with the `bulletproof` skill pre-loaded as a system prompt.
Use for the 12-stage adaptive development workflow (research → spec → plan →
implement → verify → review → deploy).

### 3) Start new conversation
Launches a plain Claude session with no additional system prompt.

### 4) Resume from list
Resumes a previous Claude session (Claude will show a session picker).

### h) Help
Shows this help document.

## Skills

Skills are located in `~/.agents/skills/` (symlinked from `~/.claude/skills/`).
Claude Code discovers them automatically.

Key skills available:
- `orchestrator-mode` — Full feature delivery orchestration
- `bulletproof` — 12-stage verified dev workflow
- `writing-plans` — Implementation plan creation
- `implementing-tasks` — TDD task execution with file ownership and self-review
- `planning-tests` — Test strategy design (produces test plan for automation-tester)
- `writing-automated-tests` — AAA-structured test writing with isolation and control cases
- `updating-documentation` — Post-review doc updates (README, env vars, changelog)
- `subagent-driven-development` — Same-session plan execution with reviews
- `executing-plans` — Parallel session plan execution
- `requesting-code-review` — Code review dispatch
- `using-git-worktrees` — Isolated workspace creation
- `finishing-a-development-branch` — Branch completion and merge options
- `find-skills` — Discover installable skills

## Keyboard Shortcuts

In Claude CLI:
- `Ctrl+C`: Cancel current operation
- `Ctrl+D`: Exit session
- `/help`: Show Claude CLI help
