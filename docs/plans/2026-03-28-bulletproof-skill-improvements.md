# Bulletproof Skill Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Backport 8 high-value patterns from the `bulletproof` skill into the custom skill set.

**Architecture:** Each task touches exactly one skill file (or one new file + one reference). All changes are additive — no existing behaviour is removed. Deployed files in `~/.agents/skills/` are synced after every task. The stop hook (Task 6) is the only change outside the skills directory.

**Tech Stack:** Bash/Markdown/JSON — no build step needed.

---

## Task 1: Add challenge loop to writing-plans

**Files:**
- Modify: `dot_agents/skills/writing-plans/SKILL.md`
- Deploy: `~/.agents/skills/writing-plans/SKILL.md` (copy after edit)

**Step 1: Read the current file**

```bash
cat dot_agents/skills/writing-plans/SKILL.md
```

**Step 2: Add Challenge Loop section before "Execution Handoff"**

Insert this block immediately before the `## Execution Handoff` heading:

```markdown
## Challenge Loop (mandatory before handing off plan)

Before saving and offering the execution choice, answer these 3 questions
**inside the plan document** under a `## Challenge Log` heading:

**1. Does this solve the problem?**
Walk through every task against the stated goal.
Any goal uncovered → the plan is incomplete, add the missing task.

**2. Is this the most efficient solution?**
Name 2–3 alternative approaches with pros/cons.
State why the chosen approach beats each alternative.

**3. Is there "code for code's sake"?**
Every task must directly serve the stated goal.
Drive-by refactoring, speculative abstractions → remove or move to a separate plan.

Do not proceed to Execution Handoff until all three questions are answered.
```

**Step 3: Add `## Challenge Log` to the Plan Document Header template**

In the Plan Document Header block, add after the `---` separator:

```markdown
## Challenge Log

1. **Does this solve the problem?** [answer]
2. **Most efficient solution?** Alternatives considered: [list]. Chosen because: [reason]
3. **Code for code's sake?** [none / list removed items]

---
```

**Step 4: Deploy**

```bash
cp dot_agents/skills/writing-plans/SKILL.md ~/.agents/skills/writing-plans/SKILL.md
```

**Step 5: Verify**

```bash
grep -n "Challenge Loop" ~/.agents/skills/writing-plans/SKILL.md
```
Expected: line number printed (not empty).

**Step 6: Commit**

```bash
git add dot_agents/skills/writing-plans/SKILL.md
git commit -m "feat(skills): add challenge loop to writing-plans"
```

---

## Task 2: Add false-positive filter to code-reviewer template

**Files:**
- Modify: `dot_agents/skills/requesting-code-review/code-reviewer.md`
- Deploy: `~/.agents/skills/requesting-code-review/code-reviewer.md`

**Step 1: Read the current file**

```bash
cat dot_agents/skills/requesting-code-review/code-reviewer.md
```

**Step 2: Replace the "For each issue" block with the false-positive-filtered version**

Find:

```markdown
**For each issue:**
- File:line reference
- What's wrong
- Why it matters
- How to fix (if not obvious)
```

Replace with:

```markdown
**For each issue:**
- File:line reference
- What's wrong
- **Is this real?** Prove it is reproducible — describe the scenario that triggers it.
  If you cannot prove it triggers, do not report it.
- Why it matters
- How to fix (if not obvious)
```

**Step 3: Add false-positive rule to the DO/DON'T block**

In the `**DON'T:**` list, add:

```markdown
- Report bugs you cannot prove are reproducible (speculative = noise)
```

**Step 4: Deploy**

```bash
cp dot_agents/skills/requesting-code-review/code-reviewer.md \
   ~/.agents/skills/requesting-code-review/code-reviewer.md
```

**Step 5: Verify**

```bash
grep -n "Is this real" ~/.agents/skills/requesting-code-review/code-reviewer.md
```
Expected: line number printed.

**Step 6: Commit**

```bash
git add dot_agents/skills/requesting-code-review/code-reviewer.md
git commit -m "feat(skills): add false-positive filter to code-reviewer template"
```

---

## Task 3: Create impact-analysis skill + wire into subagent-driven-development

**Files:**
- Create: `dot_agents/skills/impact-analysis/SKILL.md`
- Modify: `dot_agents/skills/subagent-driven-development/SKILL.md`
- Deploy both

**Step 1: Create the skill directory**

```bash
mkdir -p dot_agents/skills/impact-analysis
mkdir -p ~/.agents/skills/impact-analysis
```

**Step 2: Write impact-analysis/SKILL.md**

```markdown
---
name: impact-analysis
description: Use after completing each implementation task or phase, before marking complete — checks for regressions, changed API contracts, and forward-compatibility issues introduced by the change
---

# Impact Analysis

After every implementation task, before marking it complete: verify you haven't broken adjacent code.

**Core principle:** A passing task test suite ≠ no regressions. Always check the wider blast radius.

## When to Run

- After each task in subagent-driven-development (after spec + quality review pass)
- After each phase/batch in executing-plans
- Before any merge to main

## Checklist

### 1. Regression Check
- Which other modules, functions, or tests depend on the files you changed?
- Run the **full project test suite**, not only the tests for your task
- If anything outside your task now fails → fix before marking complete

```bash
# Examples — use whatever applies to your stack
pytest                    # Python
go test ./...             # Go
npm test                  # JS/TS
```

### 2. Contract Changes
- Did any function signatures, exported types, API endpoints, or component props change?
- If yes → list every consumer; verify each is updated
- Unannounced breaking changes = blocker, not a suggestion

### 3. Forward Compatibility
- What problems could these changes cause in a week or a month?
- Untested edge cases: zero records, maximum records, concurrent requests?
- Unexpected user behaviour paths?

### 4. Data Compatibility
- Schema changes need safe migrations (nullable columns, default values, rollback plan)
- Breaking changes in APIs or config formats → feature flag or versioning needed?

## Report Format

After running the checklist, include in your task report:

```
Impact Analysis:
- Regressions: [none | list]
- Contract changes: [none | list of affected consumers]
- Forward concerns: [none | list]
- Verdict: ✅ Safe to proceed / ❌ Fix required before marking complete
```

## Red Flags

**Never skip because:**
- "I only changed one file" — one file can be imported everywhere
- "My task tests all pass" — those only cover your task
- "It's a hotfix" — hotfixes are the most regression-prone changes
```

**Step 3: Deploy**

```bash
cp dot_agents/skills/impact-analysis/SKILL.md ~/.agents/skills/impact-analysis/SKILL.md
```

**Step 4: Add impact-analysis reference to subagent-driven-development SKILL.md**

Read the current file:

```bash
cat dot_agents/skills/subagent-driven-development/SKILL.md
```

In the `## The Process` flowchart (dot graph), add a new node between
`"Code quality reviewer subagent approves?"` → `"Mark task complete in TodoWrite"`:

Add node `"Run impact-analysis skill"` with edges:
- `"Code quality reviewer subagent approves?" -> "Run impact-analysis skill" [label="yes"]`
- `"Run impact-analysis skill" -> "Mark task complete in TodoWrite"`

In the `## Integration` section, add under Required workflow skills:
```markdown
- **impact-analysis** — Run after each task's reviews pass, before marking complete
```

**Step 5: Deploy subagent-driven-development**

```bash
cp dot_agents/skills/subagent-driven-development/SKILL.md \
   ~/.agents/skills/subagent-driven-development/SKILL.md
```

**Step 6: Verify**

```bash
grep -n "impact-analysis" ~/.agents/skills/subagent-driven-development/SKILL.md
grep -rn "impact-analysis" ~/.agents/skills/impact-analysis/SKILL.md | head -1
```
Expected: both return matches.

**Step 7: Commit**

```bash
git add dot_agents/skills/impact-analysis/SKILL.md \
        dot_agents/skills/subagent-driven-development/SKILL.md
git commit -m "feat(skills): add impact-analysis skill, wire into subagent-driven-development"
```

---

## Task 4: Add context management, size-based mode selection, and model recommendations to orchestrator-mode

**Files:**
- Modify: `dot_agents/skills/orchestrator-mode/SKILL.md`
- Deploy: `~/.agents/skills/orchestrator-mode/SKILL.md`

**Step 1: Read the current file**

```bash
cat dot_agents/skills/orchestrator-mode/SKILL.md
```

**Step 2: Add "Pick Your Mode" section at the top (after the frontmatter overview line)**

Insert after `Keep your own context minimal — never read file contents yourself, delegate all work.`
and before `## Critical Rules`:

```markdown
## Pick Your Mode

Not every request needs all 6 phases.

| Size | Examples | Phases |
|------|----------|--------|
| **S** — Small | Bug fix, config change, 1–2 files | 0 → 4 → 6 (skip testing-planner, skip docs) |
| **M** — Medium | New feature, module refactor, 3–10 files | All phases 0–6 |
| **L** — Large | New service, architecture change, 10+ files | All phases 0–6 + git worktree isolation |

Announce your size classification before Phase 0 so the human can correct it.

## Model Recommendations Per Phase

| Phase | Recommended Model | Reason |
|-------|-------------------|--------|
| Phase 1: Planning | claude (Opus) | Cross-file reasoning, architectural decisions |
| Phase 2: Implementation | codex or claude (Sonnet) | Speed and cost for bulk coding |
| Phase 3: Testing | codex or claude (Sonnet) | Repetitive test writing |
| Phase 4: Code Review | claude (Opus) | Deep analysis, SOLID/security/legal |
| Phase 5: Documentation | claude (Sonnet) | Structured writing |
| Phase 6: Finalization | claude (Sonnet) | Verification and branch management |

Set role assignments in the session menu to match these recommendations when all agents are available.

## Context Management

### The 40% Rule
Context quality degrades as the window fills. Rules:
- Run `/compact` manually at 50% — do not wait for auto-compact
- If context is overloaded: save progress to a handoff file → `/clear` → fresh start

### Fresh Context Between Phases
Each major phase = clean context. Before `/clear`:
1. Write/update `docs/plans/YYYY-MM-DD-<feature>-context.md` with progress state
2. Start the next phase pointing at that file path — never paste large file contents

### Progressive Disclosure
Do not dump the codebase into context:
- Pass only file paths and brief descriptions between phases
- Each subagent prompt references the plan file path, not the plan content inline
```

**Step 3: Deploy**

```bash
cp dot_agents/skills/orchestrator-mode/SKILL.md ~/.agents/skills/orchestrator-mode/SKILL.md
```

**Step 4: Verify**

```bash
grep -n "Pick Your Mode\|40% Rule\|Model Recommendations" \
     ~/.agents/skills/orchestrator-mode/SKILL.md
```
Expected: 3 lines printed.

**Step 5: Commit**

```bash
git add dot_agents/skills/orchestrator-mode/SKILL.md
git commit -m "feat(skills): add context management, size mode selection, model recommendations to orchestrator-mode"
```

---

## Task 5: Add deterministic gates to implementer-prompt and executing-plans

**Files:**
- Modify: `dot_agents/skills/subagent-driven-development/implementer-prompt.md`
- Modify: `dot_agents/skills/executing-plans/SKILL.md`
- Deploy both

**Step 1: Read current files**

```bash
cat dot_agents/skills/subagent-driven-development/implementer-prompt.md
cat dot_agents/skills/executing-plans/SKILL.md
```

**Step 2: Add Tier-1 gates to implementer-prompt.md**

In the `## Your Job` numbered list, replace step 3 `"Verify implementation works"` with:

```markdown
3. Run Tier-1 gates (see below) — all must pass before committing
```

Add a new `## Deterministic Gates (Tier 1 — Required)` section before `## Before Reporting Back: Self-Review`:

```markdown
## Deterministic Gates (Tier 1 — Required)

Run every gate that applies to your stack. Show the output in your report.
A gate failure = do not commit, fix first.

| Gate | Command examples | Must pass |
|------|-----------------|-----------|
| Type check | `tsc --noEmit` / `mypy .` / `go build ./...` | 0 errors |
| Lint | `npm run lint` / `ruff check .` / `golangci-lint run` | 0 errors |
| Unit tests | `npm test` / `pytest -x` / `go test ./...` | all green |

If none of these apply to the current stack, state that explicitly in your report.
Never skip a gate that is present — a failing gate that you ignore will fail in CI.
```

**Step 3: Add gate check to executing-plans SKILL.md**

In `### Step 2: Execute Batch`, after step 3 `"Run verifications as specified"`, add:

```markdown
4. Run Tier-1 gates (type check + lint + tests) — all must be green before marking task complete
   Show gate output in your batch report
```

**Step 4: Deploy both**

```bash
cp dot_agents/skills/subagent-driven-development/implementer-prompt.md \
   ~/.agents/skills/subagent-driven-development/implementer-prompt.md
cp dot_agents/skills/executing-plans/SKILL.md \
   ~/.agents/skills/executing-plans/SKILL.md
```

**Step 5: Verify**

```bash
grep -n "Tier-1\|Deterministic Gates" \
     ~/.agents/skills/subagent-driven-development/implementer-prompt.md \
     ~/.agents/skills/executing-plans/SKILL.md
```
Expected: matches in both files.

**Step 6: Commit**

```bash
git add dot_agents/skills/subagent-driven-development/implementer-prompt.md \
        dot_agents/skills/executing-plans/SKILL.md
git commit -m "feat(skills): add deterministic gates to implementer-prompt and executing-plans"
```

---

## Task 6: Add anti-rationalization Stop hook to Claude Code settings

**Files:**
- Modify: `~/.claude/settings.json`

Current `settings.json` has no `hooks` key — this task adds one.

**Step 1: Read current settings**

```bash
cat ~/.claude/settings.json
```

**Step 2: Add the Stop hook**

Using the `update-config` skill, add a `hooks.Stop` entry to `~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "You are a JSON-only evaluator. Respond ONLY with raw JSON, no markdown.\n\nReview the assistant's final response. Reject if:\n- Rationalizing incomplete work ('pre-existing', 'out of scope', 'needs follow-up')\n- Listing problems without fixing them\n- Skipping test/lint failures with excuses\n- Making changes unrelated to the stated problem\n- Claiming completion without running verification gates\n\nRespond: {\"ok\": false, \"reason\": \"[issue]. Go back and finish.\"}\nor: {\"ok\": true}"
        }
      ]
    }
  ]
}
```

**Step 3: Verify the hook is present**

```bash
jq '.hooks.Stop[0].hooks[0].type' ~/.claude/settings.json
```
Expected: `"prompt"`

**Step 4: Smoke-test (manual)**

Start a Claude session and intentionally end a response with "This pre-existing issue is out of scope."
Expected: Claude is prompted back and must revise or justify.

> Note: No git commit for this task — `~/.claude/settings.json` is outside the chezmoi repo.

---

## Deployment Sync Reference

After all tasks, verify all deployed skills match their chezmoi sources:

```bash
for skill in writing-plans requesting-code-review impact-analysis \
             orchestrator-mode subagent-driven-development executing-plans; do
  src="dot_agents/skills/${skill}/SKILL.md"
  dst="${HOME}/.agents/skills/${skill}/SKILL.md"
  if diff -q "${src}" "${dst}" &>/dev/null; then
    echo "✓ ${skill}"
  else
    echo "✗ ${skill} — out of sync"
  fi
done
```

Expected: all lines show `✓`.
