# Claude Code Guidelines

**This file redirects to the main AI agent guidelines.**

All rules and guidelines for Claude Code (and other AI agents) are maintained in a single source of truth:

**→ See: [AGENTS.md](AGENTS.md)**

## Why This Redirect?

- Single source of truth for all AI agents
- Easier maintenance - update one file instead of many
- Consistent rules across Claude, Codex, Cursor, and other agents
- Reduces duplication and potential conflicts

## Quick Reference

The main guidelines in `AGENTS.md` cover:

1. **Task Management** - TODO.md workflow
2. **Git Policy** - NEVER stage/commit without explicit instruction
3. **Code Standards** - Bash, Python, and other languages
4. **Security** - Sandboxing, credentials, prohibited actions
5. **Chezmoi** - Special file naming conventions
6. **Communication** - How to report changes and ask questions

## Critical Rules (Summary)

These are the most important rules - see `AGENTS.md` for full details:

1. **Read files before modifying**
2. **NEVER stage or commit without explicit user instruction**
3. **Preserve chezmoi prefixes** (`dot_`, `executable_`, `private_`)
4. **Never weaken sandbox security**
5. **Validate syntax** (`bash -n`, etc.)
6. **Quote all bash variables**: `"${var}"`

---

**For complete guidelines**: Read `~/AGENTS.md` or `~/.local/share/chezmoi/AGENTS.md`
