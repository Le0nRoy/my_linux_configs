# Documentation Directory

This directory contains documentation for completed tasks and system development work.

**Note**: This directory is ignored by chezmoi (see `.chezmoiignore`) and will not be deployed to the home directory.

## Structure

```
docs/
├── README.md          # This file
└── completed/         # Completed task documentation
    └── YYYY-MM-DD-task-name.md
```

## Completed Tasks

Completed tasks are documented here with the following naming convention:
- `YYYY-MM-DD-task-name.md` - Date-based naming for easy sorting

Each completed task document should contain:
1. **Task Overview**: Original description from TODO.md
2. **Implementation Details**: How the task was completed
3. **Decisions Made**: Key technical decisions and rationale
4. **Files Changed**: List of modified/created files
5. **Testing**: How the implementation was validated
6. **Notes**: Any important observations or future considerations

## Usage

### When Completing a Task

1. Create file: `docs/completed/YYYY-MM-DD-task-name.md`
2. Move full task description from `TODO.md` to this file
3. Add implementation details and notes
4. Update `TODO.md` with brief summary and link to this doc

### Example

```markdown
# Task: Implement Docker Access for AI Agents

**Completed**: 2025-11-14
**Agent**: Claude Code

## Original Task Description
[Full description from TODO.md]

## Implementation
[How it was done]

## Files Changed
- `bin/ai_agent_universal_wrapper.bash` - Added Docker socket bindings
- ...

## Testing
[How it was validated]

## Notes
[Important observations]
```

## Guidelines

- Keep documentation concise but complete
- Include code snippets where relevant
- Link to related tasks/documentation
- Update this README when adding new documentation categories
