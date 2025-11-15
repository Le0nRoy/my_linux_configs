# AI Agent Rules - System-Wide Guidelines

This document contains rules and guidelines for AI agents (Claude, Codex, Cursor, etc.) when working in **any directory** on this system.

**Location**: `~/AGENTS.md` (deployed via chezmoi)
**Scope**: All projects and directories on this user's system
**User**: Vadim (le0nRoy)

## System Overview

**Platform**: Linux (Arch-based)
**Shell**: bash (primary), zsh (available)
**Editor**: vim
**Window Manager**: i3
**Development Environment**: Personal workstation with sandboxed AI agents

## General Principles

### 1. Task Management and TODO File

**CRITICAL**: Always check and update `TODO.md` when working on tasks.

**Before starting any task**:
```bash
# Read the TODO file
cat TODO.md

# Check if your task is already documented
grep -i "task name" TODO.md
```

**When decomposing tasks**:
- Update `TODO.md` with subtasks immediately
- Add yourself as assignee and current date
- Document decisions and approach
- Link related tasks together

**When making progress**:
- Update task status in `TODO.md`
- Document blockers and findings
- Add notes about implementation decisions

**When completing a task**:
1. Mark task as "Completed" in `TODO.md`
2. Create documentation file: `docs/completed/YYYY-MM-DD-task-name.md`
3. Move full task description and all notes to docs file
4. Leave brief summary in `TODO.md` with link to completed docs
5. Update related configuration files (AGENTS.md, CLAUDE.md, etc.)

**Example completed task entry in TODO.md**:
```markdown
### ✅ Task Name (Completed 2025-11-14)
Brief one-line summary.
See: [docs/completed/2025-11-14-task-name.md](docs/completed/2025-11-14-task-name.md)
```

**Note**: The `docs/` directory is ignored by chezmoi (see `.chezmoiignore`), so completed task documentation won't be deployed to home directory.

### 2. Read Before Writing
- **ALWAYS** read files completely before modifying them
- Understand context, patterns, and existing conventions
- Check for related files that might be affected
- Look for documentation (README, CONTRIBUTING, comments, TODO.md)

### 3. Preserve User Preferences
- Respect existing code style and formatting
- Maintain indentation style (tabs vs spaces)
- Keep user customizations intact
- Follow project-specific conventions

### 3. Security First
- Never commit secrets, credentials, or API keys
- Validate paths and inputs
- Be cautious with file permissions
- Ask before executing potentially destructive commands

### 4. Test and Validate
- Test syntax before claiming completion
- Suggest validation commands when appropriate
- Use safe testing approaches (dry-run, subshells, etc.)
- Verify changes work as intended

## Code Style Standards

### Bash/Shell Scripts

**Preferred style**:
```bash
#!/bin/bash
# Clear purpose statement and usage documentation

# Strict error handling for critical scripts
set -euo pipefail

# Function naming: snake_case
function do_something() {
    local variable="${1}"

    # Always quote variables
    if [[ -f "${variable}" ]]; then
        echo "File exists: ${variable}"
    fi
}

# Use [[ ]] for conditions, not [ ]
# Use $(command) not backticks
# Use arrays for complex arguments
local -a args=(
    "--flag"
    "${value}"
)
```

**Required**:
- Shebang: `#!/bin/bash` (not `#!/bin/sh`)
- Quote all variable expansions: `"${var}"` not `$var`
- Use `[[ ]]` for conditions
- Use meaningful function and variable names (snake_case)
- Include header comments for scripts
- Validate inputs and provide helpful error messages

**Validation**:
```bash
# Check syntax
bash -n script.bash

# Test sourcing
bash -c 'source script.bash'
```

### Python (if present in project)
- Follow PEP 8 style guide
- Use meaningful variable names
- Include docstrings for functions/classes
- Use type hints where beneficial

### Other Languages
- Follow project-specific conventions first
- Use language-standard formatters if available
- Maintain consistency with existing code

## Docker and Kubernetes Access

AI agents have full access to Docker and can create local Kubernetes clusters using kind.

### Docker
All Docker commands are available:
```bash
docker ps
docker run --rm alpine echo "Hello from sandbox"
docker build -t myapp:latest .
docker-compose up -d
```

Full documentation: `DOCKER_AI_AGENTS.md`

### kind (Kubernetes IN Docker)

**Setup (first time in new sandbox)**:
```bash
# Check if installed
if ! command -v kind &>/dev/null; then
    ~/bin/setup_kind.bash
fi

# Verify
kind version
kubectl version --client
```

**Usage**:
```bash
# Create cluster
kind create cluster --name dev

# Use kubectl
kubectl get nodes
kubectl create deployment nginx --image=nginx

# Delete cluster
kind delete cluster --name dev
```

**Key points**:
- Clusters are Docker containers running Kubernetes
- Multiple clusters can run with different names
- Clusters persist until deleted
- Each has isolated kubeconfig context

## File Type Guidelines

### Configuration Files

#### TOML
```toml
[section]
    key = "value"
    boolean = true
    number = 42
```
- Sections: `[section]` or `[section.subsection]`
- Booleans: lowercase `true`/`false` (no quotes)
- Strings: always quoted

#### INI-style (.gitconfig, .conf)
```ini
[section]
    key = value
[section "subsection"]
    key = value
```
- Use tabs for indentation (usually)
- Comments: `#` or `;`

#### YAML
```yaml
key: value
nested:
  subkey: value
list:
  - item1
  - item2
```
- Use 2 spaces for indentation
- Be careful with indentation (it's semantic)
- Use `---` document separator if needed

#### JSON
```json
{
  "key": "value",
  "nested": {
    "subkey": "value"
  }
}
```
- Valid JSON syntax required
- Use 2 spaces for indentation (match project)
- No trailing commas
- Validate with `jq` or `python -m json.tool`

### Markdown
- Use ATX-style headers (`#`, `##`, `###`)
- Include code fences with language tags
- Keep line length reasonable (80-120 chars)
- Use lists and formatting for readability
- For documents with many headers use Table of Contents

## Git Workflow

### User's Git Configuration
- Default branch: `main`
- Editor: vim
- Auto-setup remote: enabled
- Username: ask for each project
- Name: ask for each project

### Commit Messages
**Preferred format**:
```
Type: Brief summary (50 chars or less)

Detailed explanation if needed (wrap at 72 chars).
- Bullet points for multiple changes
- Reference issue numbers if applicable
```

**Types**: feat, fix, docs, style, refactor, test, chore

**Examples**:
- `feat: Add user authentication module`
- `fix: Correct path validation in wrapper script`
- `docs: Update installation instructions`
- `refactor: Simplify error handling logic`

### Git Operations
- Check status before committing: `git status`
- Review changes: `git diff`
- Commit related changes together
- Write descriptive commit messages
- Don't commit generated files unless necessary

## Environment Variables

### Critical System Variables
When working with shell configurations, preserve:
- `EDITOR=vim` / `VISUAL=vim`
- `PATH` modifications
- `HOME`, `USER`, `HOSTNAME`
- `LANG`, `TERM`, `COLORTERM`
- Language-specific: `JAVA_HOME`, `PIPENV_VENV_IN_PROJECT`, etc.

## Common Tasks and Patterns

### Error Handling (Bash)
```bash
# Exit on error
set -e

# Validation with error message
if [[ ! -f "${file}" ]]; then
    echo "ERROR: File not found: ${file}" >&2
    exit 1
fi

# Trap for cleanup
trap 'cleanup_function' EXIT ERR
```

### Logging Pattern
```bash
echo_log() {
    local level="${1}"
    shift
    echo "[$(date '+%F %T')] ${level}: $*" >&2
}

echo_log "INFO" "Starting process"
echo_log "ERROR" "Something failed"
```

### Path Validation
```bash
# Check file exists
[[ -f "${file}" ]] || { echo "File not found" >&2; exit 1; }

# Check directory exists
[[ -d "${dir}" ]] || { echo "Directory not found" >&2; exit 1; }

# Create directory if missing
mkdir -p "${dir}"

# Use absolute paths when critical
realpath "${relative_path}"
```

## Security Considerations

### AI Agent Sandboxing
This system runs AI agents in **bubblewrap sandboxes** with resource limits:
- Address space limits (RLIMIT_AS)
- CPU time limits (RLIMIT_CPU)
- File descriptor limits (RLIMIT_NOFILE)
- Process limits (RLIMIT_NPROC)

**When you are asked to modify sandbox wrappers** (if working in dotfiles):
- **NEVER** weaken security restrictions without explicit instruction
- **ALWAYS** validate paths before adding bind mounts
- **PRESERVE** existing security checks
- **USE** `--ro-bind` (read-only) by default

### Sensitive Data
- **NEVER** commit credentials, API keys, tokens
- **AVOID** logging sensitive information
- **ASK** before handling personal data
- **USE** environment variables or config files for secrets

## Project-Specific Rules

### When Working in Chezmoi Dotfiles Repository

**Location**: `~/.local/share/chezmoi/`

#### Critical: Chezmoi File Naming Conventions
This repository uses special file name prefixes that control deployment:

- **`dot_`** → Hidden file (`.`) in home directory
  - `dot_bashrc` becomes `~/.bashrc`
  - `dot_config/` becomes `~/.config/`
  - **NEVER remove this prefix**

- **`executable_`** → File will be executable (+x)
  - `executable_helper.bash` becomes executable script
  - **REQUIRED for all scripts**

- **`private_`** → Restricted permissions (600/700)
  - `private_gtk-3.0/` has restricted access
  - **DO NOT remove for sensitive configs**

- **`.tmpl`** → Template file (processed by chezmoi)
  - `dot_env.tmpl` is processed to `~/.env`
  - **DO NOT modify without understanding template syntax**

#### Chezmoi Workflow
- Changes in repository don't immediately affect system
- User runs `chezmoi apply` to deploy changes
- Preview changes: `chezmoi diff`
- Test before applying: `chezmoi diff <file>`

#### Chezmoi Repository Structure
```
~/.local/share/chezmoi/
├── bin/                    # Scripts (use executable_ prefix)
├── dot_config/             # App configs (~/.config/)
├── dot_bashrc             # Shell config (~/.bashrc)
├── dot_gitconfig          # Git config (~/.gitconfig)
└── [other dotfiles]
```

#### Security-Critical Files
When modifying AI agent wrappers in `bin/`:
- `ai_agent_universal_wrapper.bash` - Core sandboxing logic
- `executable_claude_wrapper.bash` - Claude-specific wrapper
- `executable_codex_wrapper.bash` - Codex wrapper
- `executable_cursor_agent_wrapper.bash` - Cursor wrapper

**DO NOT**:
- Remove security validations
- Bypass resource limits
- Disable path checking
- Add untrusted bind mounts

### When Working in Other Projects

#### Discover Project Structure First
```bash
# Find documentation (recursively, not just in root)
find . -type f \( -name "README*" -o -name "CONTRIBUTING*" -o -name "AGENT*" \) 2>/dev/null

# Check for package files (recursively - they might be nested)
find . -type f \( -name "package.json" -o -name "setup.py" -o -name "requirements.txt" -o -name "Cargo.toml" -o -name "go.mod" \) 2>/dev/null | head -10

# Get project structure overview (use what's available)
if command -v tree &>/dev/null; then
    tree -L 2 -a
elif command -v find &>/dev/null; then
    find . -maxdepth 2 -type f -o -type d | sort
else
    ls -laR | head -50
fi
```

#### Create Project-Specific AI Rules
**When starting work on a project without `AGENT.md` or AI agent-specific config files**:

1. **Create project-specific rules**: Based on `~/AGENTS.md` and `~/CLAUDE.md`, create:
   - `AGENT.md` in project root - Project-specific rules for all AI agents
   - `CLAUDE.md` (or similar) - Claude-specific rules if needed
   - Document project structure, conventions, build commands
   - Include testing procedures and validation steps

2. **Leave unstaged for review**: Even if doing commits, leave these new AI config files unstaged:
   ```bash
   # Stage other files but not AI configs
   git add file1.py file2.py
   git restore --staged AGENT.md CLAUDE.md
   ```

3. **Let user review**: User should review and adjust AI rules before committing them

**Example project-specific AGENT.md structure**:
```markdown
# AI Agent Rules - [Project Name]

## Project Overview
- Purpose: [What this project does]
- Tech stack: [Languages, frameworks, tools]
- Architecture: [Key architectural decisions]

## Project-Specific Conventions
- Code style: [Specific to this project]
- Testing approach: [How tests are organized]
- Build commands: [How to build/run]

## Critical Files
- [List important files and their purposes]

## Inherited Rules
This project follows general rules from ~/AGENTS.md with these additions/overrides:
[List any project-specific overrides]
```

#### Respect Project Conventions
- Read project README, CONTRIBUTING, and AGENT* files
- Follow existing code style
- Use project's tooling (linters, formatters, test runners)
- Check for CI/CD configurations
- Look for `.editorconfig`, `.prettierrc`, etc.

#### Refactoring and Code Review Tasks
**When asked to perform refactoring or code review**:

1. **Propose a separate branch**: Create a dedicated branch for applying AI agent rules. Ask user if JIRA ticket should be assigned to the branch:
   ```bash
   # Suggest this to user
   git checkout -b refactor/apply-ai-agent-rules
   # Or if JIRA ticket is provided
   git checkout -b refactor/jira-id-apply-ai-agent-rules
   ```

2. **Create/update AGENT.md**: Document the style and rules being applied:
   - Code formatting standards
   - Security improvements
   - Performance optimizations
   - Architectural changes

3. **Apply systematic changes**:
   - Reformat code to single consistent style
   - Fix security issues
   - Identify and document improvements
   - Mark places for optimization with TODOs
   - Review for common mistakes

4. **Leave AI rules unstaged**: Even when committing refactored code:
   ```bash
   # Commit refactored code
   git add src/
   git commit -m "refactor: Apply AI agent style rules"

   # Leave AGENT.md unstaged for user review
   git restore --staged AGENT.md CLAUDE.md
   ```

5. **Create comprehensive summary**: In AGENT.md or separate REFACTORING.md:
   - List all changes made
   - Security issues found and fixed
   - Performance improvements
   - Remaining TODOs
   - Test coverage gaps
   - Suggested next steps

#### Common Project Patterns
- **Python**: `requirements.txt`, `setup.py`, `pyproject.toml`, virtual environments
- **Node.js**: `package.json`, `node_modules/`, `npm` or `yarn`
- **Rust**: `Cargo.toml`, `Cargo.lock`, `target/`
- **Go**: `go.mod`, `go.sum`
- **C/C++**: `Makefile`, `CMakeLists.txt`

## Testing and Validation

### Script Validation
```bash
# Bash syntax check
bash -n script.bash

# ShellCheck (if available)
shellcheck script.bash

# Test in subshell
bash -c 'source script.bash; test_function'
```

### Configuration Validation
```bash
# Git config
git config --list

# JSON validation
jq . file.json

# YAML validation (if yamllint available)
yamllint file.yaml

# Python syntax
python -m py_compile script.py
```

### Application-Specific
- Test with application's built-in validation if available
- Check documentation for test commands
- Use dry-run modes when available

## Handling Style-Breaking Changes

**When user forces style changes that break established rules**:

1. **Update ALL accessible AI rule files**:
   - Update project's `AGENT.md` (project-specific rules)
   - Update any other AI config files in current project

2. **Document the override**:
   ```markdown
   ## Style Override - [Date]
   User preference: [Description of style change]
   Overrides: [Which rule from general guidelines]
   Reason: [If provided by user]
   ```

3. **Leave changes unstaged**: Even if doing commits, leave updated AI rule files unstaged:
   ```bash
   # Commit code with new style
   git add src/
   git commit -m "style: Apply user-requested formatting changes"

   # Leave all AI rule files unstaged for user review
   git restore --staged AGENT.md CLAUDE.md 
   ```

4. **Warn user about conflicts**:
   - Notify that changes conflict with system-wide rules
   - Explain implications (other projects, other agents)
   - Suggest reviewing updated rule files before committing

5. **Apply consistently**: Once user confirms, apply new style rules consistently across the project

**Example scenario**:
```
User: "Use 2 spaces for indentation in bash scripts instead of tabs"
Agent:
- Updates all bash scripts with 2-space indentation
- Updates AGENT.md to document this override
- Leaves all *AGENT*.md files unstaged
- Notifies user: "Style rules updated to use 2 spaces. Please review
  AGENT.md before committing these rule changes."
```

## Communication Guidelines

### When Reporting Changes
- **Be specific**: Mention exact files and line numbers
  - Good: "Updated function at script.bash:42"
  - Bad: "Fixed the script"

- **Explain reasoning**: Why this change is needed
- **Mention side effects**: What else might be affected
- **Provide test commands**: Help user verify changes
- **Document generated functionality**: Write README files with test commands, possible TODOs and ways to improve

### When Asking for Clarification
- Ask before making structural changes
- Offer alternatives when multiple approaches exist
- Explain trade-offs of different options
- Be clear about what you don't understand

## Prohibited Actions

**NEVER unless these rules are removed from this file**:
- Remove security features or validations
- Commit secrets, credentials, or API keys
- Make untested changes to critical system configs
- Delete files without confirmation
- Modify file permissions arbitrarily
- Break existing user workflows
- Execute destructive commands (rm -rf, mkfs, dd, etc.)
- Modify dotfiles without understanding impact

## Recommended Actions

**ALWAYS**:
- Read files before modifying
- Preserve existing patterns and conventions
- Validate syntax before completing tasks
- Test in safe environments when possible
- Document non-obvious changes
- Communicate clearly with file:line references
- Ask when uncertain about impact
- Respect the principle of least surprise

## Quick Reference

### File Extensions and Tools
- `.bash`, `.sh` → Bash scripts, validate with `bash -n`
- `.py` → Python, validate with `python -m py_compile`
- `.json` → JSON, validate with `jq`
- `.yaml`, `.yml` → YAML, validate with `yamllint`
- `.toml` → TOML, check syntax carefully
- `.md` → Markdown, use proper formatting

### Common Validation Commands
```bash
# Bash
bash -n script.bash

# Python
python -m py_compile file.py
python -m json.tool file.json  # JSON validation

# Git
git config --list
git status
git diff

# File operations
file <filename>        # Detect file type
stat <filename>        # File info and permissions
```

### User Preferences Summary
- **Editor**: vim
- **Shell**: bash (primary)
- **Git**: Descriptive commits, main branch
- **Security**: Sandboxed AI agents, cautious with permissions
- **Style**: Readable, well-documented, tested code
- **Approach**: Conservative changes, preserve existing patterns

## When in Doubt

1. **Read first** - Understand before acting
2. **Check patterns** - Look at similar existing code
3. **Ask user** - Clarify before major changes
4. **Test safely** - Use dry-run or validation commands
5. **Document** - Explain what you did and why
6. **Be conservative** - Prefer minimal, safe changes

## Additional Resources

- Chezmoi docs: https://www.chezmoi.io/
- Bash best practices: Use ShellCheck
- Git commit conventions: Conventional Commits
- Linux security: Bubblewrap sandboxing documentation

---

**Remember**: You are working across many different projects. Each project may have its own conventions. Always warn user, when project-specific rules conflict with these general guidelines. If told to prioritize project-specific rules still maintain security and safety standards.
