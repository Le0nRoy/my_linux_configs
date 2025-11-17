# TODO - System Development Tasks

This file tracks ongoing development tasks for the dotfiles system and AI agent configuration.

**Last Updated**: 2025-11-17

---

## Active Tasks

### 1. Create AI Tools Pipeline

**Status**: Not started
**Priority**: High
**Description**: Design and implement a pipeline workflow for AI-assisted development

**Components**:
- Prompt helper: Tool to craft effective prompts for AI agents
- Developer agent: Primary code generation and implementation
- Reviewer & tester: Automated code review and testing validation

**Requirements**:
- Pipeline should be automatable (scriptable)
- Each stage should have clear inputs/outputs
- Support parallel execution where possible
- Integrate with existing wrapper infrastructure

**Notes**:
- Consider using existing tools (pre-commit hooks, CI/CD patterns)
- Should work with Claude, Codex, and Cursor agents

---

### 2. Complete xrandr Screen Management System

**Status**: In progress
**Priority**: High
**Branch**: `xrandr_config`
**Description**: Implement comprehensive Xorg display management with automatic detection, configuration saving/loading, and dmenu interface

**All work for this task must be done in the `xrandr_config` branch.**

#### Requirements - Screen Configuration Management (3.1)

**Save multiple configurations with descriptions:**
- Support multiple named configurations (not just one)
- When saving, ask user which configuration is default
- Provide visual or text description of display positions
- Store configuration with metadata (name, description, date, which display is where)

#### Requirements - Auto-Detection (3.2)

**Detect all connections and disconnections:**
- Monitor for any display connection event
- Monitor for any display disconnection event
- Trigger appropriate actions automatically
- Update state tracking correctly

#### Requirements - Auto-Apply Configuration (3.3)

**Apply saved config when displays reconnect:**
- When a saved display connects, apply its saved settings
- Adjust positions to remove gaps between displays
- Align displays so middle axes match
- Keep displays close together with no gaps
- Preserve relative positions as much as possible

#### Requirements - Disconnection Handling (3.4)

**Smart disconnection behavior:**
- Move primary status from disconnected display to default display (DP-2)
- If default display was disconnected and was primary, set next clockwise display as primary
- Rearrange remaining displays to be close together (no gaps)
- Preserve relative positions of remaining displays
- Align middle axes of all displays

#### Requirements - dmenu UI

**Keybinding:**
- Use `$mod+Shift+F10` in i3 config (NOT `$mod+F9`)

**Per-display operations:**
- For each connected display, allow:
  - Load configuration for this display
  - Unload configuration for this display

**Menu behavior:**
- After any action, reopen dmenu in initial state
- All submenus must have "Back" button
- Main menu options:
  - Save current configuration
  - Load configuration (with submenu for available configs)
  - Per-display settings (submenu)
  - Open nvidia-settings
  - Back/Exit

#### Code Quality Requirements

**Function decomposition (AGENTS.md/CLAUDE.md compliance):**
- Each function should be small (max 20-30 lines)
- Single responsibility per function
- Extract these functions from current monolithic code:
  - `parse_xrandr_output()` - Parse xrandr output
  - `extract_mode()` - Extract display mode
  - `extract_position()` - Extract display position
  - `get_display_dimensions()` - Get width/height
  - `calculate_middle_axis()` - Calculate display center
  - `build_xrandr_command()` - Build xrandr command from config
  - `handle_disconnection()` - Handle single display disconnect
  - `rearrange_displays()` - Remove gaps and align displays
  - `find_next_clockwise()` - Find next display clockwise
  - `apply_config_for_display()` - Apply config to one display
  - `dmenu_main_menu()` - Main menu
  - `dmenu_load_config_menu()` - Load config submenu
  - `dmenu_display_settings_menu()` - Per-display submenu
  - Other small, focused functions

**Code style:**
- Quote all variables: `"${var}"`
- Use `[[ ]]` for conditions
- Validate inputs
- Proper error handling
- Clear function names (snake_case)

#### Current Status (from review of xrandr_config branch)

**Completed:**
- ✅ Basic xrandr wrapper functions
- ✅ Single config save/load
- ✅ Basic disconnection detection
- ✅ Simple dmenu interface
- ✅ i3 integration (but wrong keybinding)

**Issues to Fix:**
- ❌ Only saves ONE configuration (need multiple named configs)
- ❌ No default configuration selection
- ❌ No visual/text descriptions of layouts
- ❌ Does NOT detect new connections automatically
- ❌ Does NOT apply config when displays reconnect
- ❌ No gap removal or alignment logic
- ❌ No "next clockwise display" logic
- ❌ Wrong keybinding (`$mod+F9` instead of `$mod+Shift+F10`)
- ❌ No per-display load/unload in dmenu
- ❌ No "Back" buttons in submenus
- ❌ Does NOT reopen dmenu after actions
- ❌ No nvidia-settings option
- ❌ Functions are too large (50-60 lines) - violates code style

**Next Steps:**
1. Refactor existing functions into smaller units
2. Implement multiple configuration support
3. Add configuration naming and descriptions
4. Implement connection detection (not just disconnection)
5. Add auto-apply on reconnect logic
6. Implement gap removal and alignment algorithms
7. Add clockwise display selection
8. Rebuild dmenu interface with all required features
9. Fix i3 keybinding
10. Test all scenarios thoroughly

---

### 3. Refactor helper.bash

**Status**: Not started
**Priority**: Medium
**Description**: Break down `bin/executable_helper.bash` into smaller, modular files while preserving direct function execution

**Current Issues**:
- Single file is large (~350+ lines)
- Contains multiple unrelated functions
- Hard to maintain and extend

**Goals**:
- Split into logical modules (tmux, git, system, etc.)
- Preserve ability to call functions directly without script invocation
- Consider sourcing pattern vs wrapper pattern
- Maintain backward compatibility

**Considerations**:
- How to handle shared variables/constants
- Whether to keep single entry point or multiple scripts
- Impact on existing workflows

---

### 4. Unrestricted Sandbox Access

**Status**: Partially complete
**Priority**: High
**Description**: Allow AI agents full access within their sandboxes while maintaining sandbox security

**Completed**:
- ✅ Set all RLIMIT_* to unlimited in wrapper scripts
- ✅ Docker access enabled
- ✅ kind/Kubernetes access enabled

**Remaining**:
- Security testing of sandbox isolation
- Verify namespace isolation works correctly
- Test escape scenarios (security audit)
- Document security boundaries

**Security Testing Tasks**:
- [ ] Test filesystem isolation (can't access outside binds)
- [ ] Test process isolation (can't see/kill host processes)
- [ ] Test network isolation options
- [ ] Verify Docker-in-Docker security
- [ ] Test resource exhaustion scenarios
- [ ] Document security model

---

### 5. GitLab CI Integration

**Status**: Not started
**Priority**: Medium
**Description**: Enable AI agents to interact with GitLab CI/CD pipelines

**Requirements**:
- Read .gitlab-ci.yml configuration
- Trigger pipeline runs
- Monitor pipeline status
- Access job logs and artifacts
- Suggest CI/CD improvements

**Considerations**:
- API token management (security)
- Rate limiting
- Which operations should be allowed
- Integration with existing wrappers

---

### 6. Neovim Configuration

**Status**: Not started
**Priority**: Low
**Description**: Create comprehensive nvim configuration as PyCharm alternative

**Features Needed**:
- LSP integration (language servers)
- Code completion and IntelliSense
- Debugging support
- Git integration
- Project navigation
- Terminal integration
- Plugin management (lazy.nvim or packer.nvim)

**Must Match PyCharm Features**:
- Refactoring tools
- Find usages
- Go to definition/implementation
- Code generation
- Testing integration

---

### 7. System Installation Script

**Status**: Not started
**Priority**: Medium
**Description**: Create automated installation script for setting up the complete system on a fresh machine

**Should Install/Configure**:
- Base system packages
- chezmoi and dotfiles
- AI agent tools (Claude, Codex, Cursor)
- Docker and kind
- Development tools (compilers, runtimes)
- Shell configuration
- i3wm and related tools

**Features**:
- Idempotent (safe to run multiple times)
- Modular (select which components to install)
- Distribution-aware (Arch vs other distros)
- Backup existing configs before replacing

---

### 8. Automate upgrade_system Function

**Status**: Not started
**Priority**: Low
**Description**: Enhance and automate the `upgrade_system` function in helper.bash

**Goals**:
- Clean package cache automatically
- Remove orphaned packages
- Update all package databases
- Handle AUR packages
- Clean old kernels (keep 2 most recent)
- Clear temp files
- Restart services if needed

**Safety Features**:
- Dry-run mode
- Confirmation prompts for destructive operations
- Backup capability before major changes
- Rollback support

---

### 9. Unify AI Agent Rules

**Status**: Not started
**Priority**: Low
**Description**: Consolidate AGENTS.md and CLAUDE.md into a single comprehensive rule file

**Considerations**:
- Current separation: AGENTS.md (all agents), CLAUDE.md (Claude-specific)
- Some rules are agent-specific (tool usage patterns)
- Some rules are universal (code style, security)

**Options**:
1. Single file with agent-specific sections
2. Base file + agent-specific overrides
3. Modular system (include pattern)

**Decision Needed**: Discuss with user which approach is preferred

---

### 10. Create a fully sandboxed environment for AI agents

**Status**: Not started
**Priority**: Low
**Description**: Instead of current sandbox system with access to the host network create a sandbox, which still gets host directories mounted, however has own network, with own docker daemon running. Access to the internet should persist in the sandbox. Sandbox should consume as low resources, as possible, but must have 0 possibility to harm host system. Also while developing this feature need always double check, that no secrets are mounted to the sandboxes (instead of development/testing secrets).

---

## Task Management Rules

### When Starting a Task
1. Update status from "Not started" to "In progress"
2. Add your name/agent and date started
3. Create subtasks if needed
4. Update priority if circumstances changed

### During Task Execution
1. Update progress regularly
2. Document blockers and decisions
3. Add notes about unexpected findings
4. Link to related commits/branches

### When Task is Complete
1. Mark status as "Completed"
2. Add completion date
3. Move full task description to `docs/completed/YYYY-MM-DD-task-name.md`
4. Leave brief summary in TODO with link to docs
5. Update related documentation (AGENTS.md, CLAUDE.md, etc.)

### Task Decomposition
When a task is broken down into smaller tasks:
1. Update this file with subtasks
2. Link parent and child tasks
3. Consider if subtasks warrant separate doc entries

---

## Notes

- This file should be updated by both user and AI agents
- Check this file when starting new work to see if task has prior progress
- Completed task documentation goes to `docs/completed/` directory
- `docs/` directory is ignored by chezmoi (see .chezmoiignore)
