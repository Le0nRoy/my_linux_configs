# Documentation Directory

This directory contains **repository-specific** documentation for the chezmoi dotfiles repository.

**Important distinctions**:
- `AGENTS.md` and `CLAUDE.md` are **deployed to `~/`** via chezmoi and are **system-wide** AI agent rules
- This `docs/` directory is **repository-specific** and is **NOT deployed** (ignored by chezmoi)

Use this directory for:
- Repository overview and setup guides
- Feature documentation
- Completed task documentation
- Development history and decisions

**Note**: This directory is ignored by chezmoi (see `.chezmoiignore`) and will not be deployed to the home directory.

## Documentation Index

### Main Documentation

| Document | Description |
|----------|-------------|
| [repository-overview.md](repository-overview.md) | Repository structure, quick start, key components |
| [xrandr-manager.md](xrandr-manager.md) | Display management tool documentation |
| [ai-agent-sandboxing.md](ai-agent-sandboxing.md) | Bubblewrap sandbox architecture |
| [systemd-services.md](systemd-services.md) | User systemd services reference |
| [helper_refactor_plan.md](helper_refactor_plan.md) | Helper module design document |

### Related Documentation (Outside docs/)

| Document | Location | Description |
|----------|----------|-------------|
| AGENTS.md | Root (deployed to ~/) | AI agent rules for all directories |
| CLAUDE.md | Root (deployed to ~/) | Redirect to AGENTS.md |
| bin/helper/README.md | bin/helper/ | Helper module usage guide |

## Directory Structure

```
docs/
├── README.md                   # This file - documentation index
├── repository-overview.md      # Repository overview and quick start
├── xrandr-manager.md           # Display management documentation
├── ai-agent-sandboxing.md      # Sandbox architecture documentation
├── systemd-services.md         # Systemd services reference
├── helper_refactor_plan.md     # Design document for helper refactor
└── completed/                  # Completed task documentation
    ├── 2025-11-18-helper-bash-refactor.md
    ├── 2025-12-05-xrandr-screen-management.md
    └── 2025-12-18-unify-ai-agent-rules.md
```

## Completed Tasks

Completed tasks are documented with the naming convention: `YYYY-MM-DD-task-name.md`

| Date | Task | Document |
|------|------|----------|
| 2025-11-18 | Refactor helper.bash | [2025-11-18-helper-bash-refactor.md](completed/2025-11-18-helper-bash-refactor.md) |
| 2025-12-05 | xrandr Screen Management | [2025-12-05-xrandr-screen-management.md](completed/2025-12-05-xrandr-screen-management.md) |
| 2025-12-18 | Unify AI Agent Rules | [2025-12-18-unify-ai-agent-rules.md](completed/2025-12-18-unify-ai-agent-rules.md) |

## Completed Task Documentation Format

Each completed task document should contain:
1. **Task Overview**: Original description from TODO.md
2. **Implementation Summary**: Brief summary of what was done
3. **Files Changed**: List of modified/created files
4. **Testing**: How the implementation was validated
5. **Related Documentation**: Links to relevant docs

### Example Format

```markdown
# Task: [Task Name]

**Completed**: YYYY-MM-DD
**Priority**: High/Medium/Low

## Original Task Description
[Full description from TODO.md]

## Implementation Summary
[Brief summary of what was done]

## Files Changed
- `path/to/file` - Description of changes

## Testing
[How it was validated]

## Related Documentation
- [Link to related doc](path/to/doc.md)
```

## Guidelines

- Keep documentation concise but complete
- Include code snippets where relevant
- Link to related tasks/documentation
- Update this README when adding new documentation
- Use relative links between documentation files
