---
name: orchestrator-mode
description: Use when activated as development orchestrator to manage full feature delivery — covers phase workflow, agent dispatch, file ownership rules, report conventions, and role switching
---

# Orchestrator Mode

Manage the full development workflow by dispatching fresh specialist agents for each phase.
Keep your own context minimal — never read file contents yourself, delegate all work.

## Critical Rules

### No File Conflicts Between Subagents
Multiple subagents MUST NOT work on the same file simultaneously.
Plan tasks so each file is owned by at most one active subagent at a time.
If tasks share files, run them sequentially — never in parallel.

### Report Files Are Temporary
Each agent writes a report to `reports/<agent>-<task>-YYYY-MM-DD.md`.
- Before dispatching any agent: `echo "reports/" >> .git/info/exclude`
- Report files MUST NEVER be staged or committed
- Remind each agent of this rule in every dispatch prompt

### Your Report Covers Orchestration Only
`reports/orchestrator-<feature>-YYYY-MM-DD.md` must cover:
- How tasks were divided between subagents and why
- Which agent role handled each phase and which skills were active
- Agent substitutions, parallel launches, file ownership conflicts
- Gates hit (human review, test failures) and their outcomes
- What slowed orchestration and what could be improved

## Workflow Phases

### Phase 0: Project Verification
- Dispatch agent with **common-automation-verifier** skill
- Note critical gaps (CLAUDE.md/AGENTS.md, env config, test coverage) before planning

### Phase 1: Planning
- Dispatch **task-planner** (see `agents/task-planner.md`) using **writing-plans** skill
- Plan saved to `docs/plans/YYYY-MM-DD-<feature>.md`
- Context doc at `docs/plans/YYYY-MM-DD-<feature>-context.md` covering: how to run/debug/test, key file paths, file ownership map per task
- **Gate**: Human reviews plan before proceeding

### Phase 2: Implementation
- Dispatch **code-writer** (see `agents/code-writer.md`) with the plan file path
- For large features (>5 tasks): set up a worktree first (**using-git-worktrees** skill)
- Code-writer follows the plan task by task using **subagent-driven-development**

### Phase 3: Testing
- Dispatch **testing-planner** (see `agents/testing-planner.md`)
- Dispatch **automation-tester** (see `agents/automation-tester.md`)
- If sandbox prevents proper testing: create `docs/sandbox-improvements/<feature>.md` listing required changes

### Phase 4: Code Review
- Dispatch **code-reviewer** (see `agents/code-reviewer.md`) using **requesting-code-review** skill
- Reviewer checks: architecture, logic, tests, security, legal compliance, plan compliance
- If issues found: dispatch code-writer to fix, then re-review

### Phase 5: Documentation
- Dispatch **documentation-updater** (see `agents/documentation-updater.md`)
- Updates README, API docs, env var docs, changelog, context doc

### Phase 6: Finalization
- Dispatch **task-finisher** (see `agents/task-finisher.md`) using **finishing-a-development-branch** skill
- Verifies tests pass, checks no reports committed, presents merge options

## Agent Dispatch

### Dispatching Claude Subagents
Use Task tool with subagent_type:
- Exploration/research: `subagent_type="Explore"`
- Implementation/coding: `subagent_type="general-purpose"`
- Planning: `subagent_type="Plan"`

### Dispatching Codex
```bash
codex --dangerously-bypass-approvals-and-sandbox -q "prompt"
```

### Dispatching Cursor
```bash
cursor-agent --force "prompt"
```

### No Sandbox Wrappers
Call agents directly (already inside sandbox):
- `claude` not `claude_wrapper.bash`
- `codex` not `codex_wrapper.bash`
- `cursor-agent` not `cursor_agent_wrapper.bash`

## Context Management
- Pass only file paths and brief descriptions between phases
- The plan file and context doc are the shared artifacts
- Each subagent prompt must reference the plan file path and their role description

## Role Switching
If an agent hits rate limits or errors, tell the human and offer to switch that role to a different agent.

## Agent Role Files
Full role descriptions in `~/.local/share/chezmoi/bin/claude_wrapper_data/agents/`:
- `agents/orchestrator.md` — This role
- `agents/task-planner.md` — Planning phase
- `agents/code-writer.md` — Implementation phase
- `agents/testing-planner.md` — Test strategy phase
- `agents/automation-tester.md` — Test writing and execution phase
- `agents/code-reviewer.md` — Review phase
- `agents/documentation-updater.md` — Documentation phase
- `agents/task-finisher.md` — Finalization phase
