# Task: Unify AI Agent Rules

**Completed**: 2025-12-18
**Priority**: Low

## Original Task Description

Consolidate AGENTS.md and CLAUDE.md into a single comprehensive rule file.

## Implementation Summary

Made AGENTS.md the single source of truth for all AI agent rules, with CLAUDE.md serving as a redirect with a brief summary.

## Changes Made

### AGENTS.md (Primary File)

- Established as the comprehensive rule file for all AI agents
- Contains 751 lines of guidelines covering:
  - Task management and TODO.md workflow
  - Git policy (critical: never stage/commit without instruction)
  - Code standards for Bash, Python, and other languages
  - Security guidelines
  - Chezmoi file naming conventions
  - Communication guidelines
  - Docker and Kubernetes access
  - Project-specific rules

### CLAUDE.md (Redirect)

Simplified to 40 lines serving as:
- Redirect pointing to AGENTS.md
- Brief summary of critical rules
- Explanation of why redirect exists (single source of truth)

### Critical Policy Addition

Added explicit commit/staging policy to AGENTS.md:

```markdown
### CRITICAL: Commit and Staging Policy

**NEVER commit or stage changes unless explicitly instructed by user.**

**Rules**:
1. **No automatic commits**: Never run `git commit` unless user explicitly says "commit"
2. **No automatic staging**: Never run `git add` - let user review and stage
3. **Show changes instead**: After making changes, suggest `git diff` or `git status`
4. **Ask before committing**: If task seems complete, ask: "Would you like me to commit?"
```

## Files Changed

- `AGENTS.md` - Updated with comprehensive rules and commit policy
- `CLAUDE.md` - Simplified to redirect with summary

## Rationale

### Single Source of Truth Benefits

1. **Easier maintenance**: Update one file instead of many
2. **Consistency**: All AI agents follow the same rules
3. **No conflicts**: No risk of divergent rules between files
4. **Clear hierarchy**: AGENTS.md is authoritative

### Why Keep CLAUDE.md?

- Claude Code specifically looks for CLAUDE.md
- Redirect ensures Claude finds and follows the rules
- Brief summary helps quick reference without reading full document

## Testing

- Verified Claude Code reads both files
- Confirmed redirect is clear and unambiguous
- Tested that critical rules are prominent in summary

## Notes

- Both files are deployed to `~/` via chezmoi
- Available to AI agents in any directory
- Repository-specific docs go in `docs/` directory
