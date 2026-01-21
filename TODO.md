# TODO - System Development Tasks

This file tracks ongoing development tasks for the dotfiles system and AI agent configuration.

**Last Updated**: 2025-12-18

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

**Status**: ✅ Completed (2025-12-05)
**Priority**: High
**Branch**: `xrandr_config`
**Description**: Implement comprehensive Xorg display management with automatic detection, configuration saving/loading, and dmenu interface

#### Completed Implementation

**Major rewrite of `bin/executable_xrandr_manager.bash` (783 lines, modular architecture):**

**Configuration Management (3.1):**
- ✅ Multiple named configurations stored in `~/.config/xrandr-manager/configs/`
- ✅ Default configuration selection via dmenu prompt when saving
- ✅ Visual layout descriptions: `DP-2*@0,0 HDMI-0@2560,0` (sorted left-to-right)
- ✅ Full metadata: name, description, date, layout, output configurations

**Auto-Detection (3.2):**
- ✅ Connection detection via `detect_connections()` function
- ✅ Disconnection detection via `detect_disconnections()` function
- ✅ State tracking in `~/.config/xrandr-manager/current_state`
- ✅ Automatic actions triggered on state change

**Auto-Apply on Reconnect (3.3):**
- ✅ Default config applied automatically when displays reconnect
- ✅ `rearrange_displays()` removes gaps between displays
- ✅ Middle-axis alignment via `calculate_middle_axis()`
- ✅ Displays positioned contiguously (no gaps)

**Disconnection Handling (3.4):**
- ✅ Primary moves to DEFAULT_PRIMARY (DP-2) if available
- ✅ `find_next_clockwise()` selects next display when default unavailable
- ✅ `rearrange_displays()` closes gaps after disconnect
- ✅ Middle axes aligned across remaining displays

**dmenu UI:**
- ✅ Keybinding changed to `$mod+Shift+F10` in i3 config
- ✅ Per-display settings: Enable/Disable/Set Primary via submenu
- ✅ All submenus have "Back" button
- ✅ Menu reopens after actions (while loop)
- ✅ Main menu: Load config, Save config, Per-display settings, Rearrange, nvidia-settings, List outputs, Exit

**Code Quality:**
- ✅ 40+ small functions (most under 20 lines)
- ✅ All variables quoted: `"${var}"`
- ✅ All conditions use `[[ ]]`
- ✅ Clear snake_case function names
- ✅ Organized into sections with clear headers

**Functions implemented:**
- Parsing: `get_connected_outputs`, `get_disconnected_outputs`, `get_primary_output`, `extract_mode`, `extract_position`, `get_display_dimensions`, `get_display_offset`, `is_primary_output`, `is_output_enabled`
- Config: `list_configs`, `get_default_config`, `set_default_config`, `generate_layout_description`, `save_config`, `save_output_config`, `load_config`, `delete_config`
- Apply: `apply_config_file`, `build_output_args`, `add_mode_args`, `add_position_args`, `execute_xrandr_command`
- Geometry: `calculate_middle_axis`, `get_displays_left_to_right`, `find_next_clockwise`, `rearrange_displays`
- Auto: `get_current_state`, `save_state`, `load_previous_state`, `handle_disconnection`, `select_new_primary`, `handle_connection`, `auto_configure`, `detect_disconnections`, `detect_connections`
- Display: `list_outputs`, `format_output_info`
- dmenu: `dmenu_main_menu`, `dmenu_load_config_menu`, `dmenu_save_config_menu`, `dmenu_display_settings_menu`, `dmenu_single_display_menu`

**CLI Commands:**
```bash
xrandr_manager.bash save <name> [description]  # Save config
xrandr_manager.bash load <name>                # Load config
xrandr_manager.bash delete <name>              # Delete config
xrandr_manager.bash list-configs               # List all configs
xrandr_manager.bash set-default <name>         # Set default config
xrandr_manager.bash auto                       # Auto-configure
xrandr_manager.bash rearrange                  # Remove gaps/align
xrandr_manager.bash list                       # List outputs
xrandr_manager.bash dmenu                      # Interactive menu
xrandr_manager.bash monitor                    # Continuous monitoring
```

---

### 3. Refactor helper.bash

**Status**: ✅ Completed (2025-11-18)
**Priority**: Medium
**Description**: Break down `bin/executable_helper.bash` into smaller, modular files while preserving direct function execution

**Completed Implementation**:
- ✅ Created modular directory structure: `bin/helper/`
- ✅ Split into 7 focused modules (429 total lines):
  - `common.bash` (27 lines) - Shared variables and constants
  - `tmux.bash` (102 lines) - Tmux session management functions
  - `git.bash` (13 lines) - Git utility functions
  - `system.bash` (88 lines) - System, display, and notification functions
  - `storage.bash` (110 lines) - Mount/unmount operations
  - `backup.bash` (36 lines) - Backup and sync functions
  - `utils.bash` (53 lines) - Miscellaneous utility functions
- ✅ Reduced main script from 640 lines to 292 lines
- ✅ Created comprehensive README: `bin/helper/README.md`
- ✅ Validated all module syntax with `bash -n`
- ✅ Tested backward compatibility (sourcing and command-line)
- ✅ Maintained all existing functionality
- ✅ Preserved autocompletion and error handling

**Documentation**:
- See `bin/helper/README.md` for module overview and usage
- See `docs/helper_refactor_plan.md` for detailed design decisions

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

**Status**: ✅ Completed (2025-12-18)
**Priority**: Low
**Description**: Consolidate AGENTS.md and CLAUDE.md into a single comprehensive rule file

**Completed Implementation**:
- ✅ Made `AGENTS.md` the single source of truth
- ✅ `CLAUDE.md` now redirects to `AGENTS.md` with brief summary
- ✅ Added CRITICAL commit/staging policy: never stage or commit without explicit instruction
- ✅ Updated all sections that referenced automatic staging/committing

---

### 10. Create a fully sandboxed environment for AI agents

**Status**: Not started
**Priority**: Low
**Description**: Instead of current sandbox system with access to the host network create a sandbox, which still gets host directories mounted, however has own network, with own docker daemon running. Access to the internet should persist in the sandbox. Sandbox should consume as low resources, as possible, but must have 0 possibility to harm host system. Also while developing this feature need always double check, that no secrets are mounted to the sandboxes (instead of development/testing secrets).

---

### 11. PulseAudio/PipeWire Audio Profiles Manager

**Status**: Not started
**Priority**: Medium
**Description**: Create audio routing profiles with dmenu interface for managing which applications output to which audio sinks

**Use Cases**:
- Gaming: Game audio to headphones, Discord/music to speakers
- Streaming: Capture specific apps while monitoring on headphones
- Music production: Route DAW to specific interface, system sounds elsewhere
- Video calls: Meeting audio to headphones, other apps to speakers

**Features Needed**:
- Save/load named audio routing profiles
- dmenu interface for profile selection
- Per-application sink assignment
- Move running applications between sinks
- Set default sink for new applications
- Show current audio routing status

**Implementation Ideas**:
```bash
# Profile format (JSON or simple config)
# ~/.config/audio-profiles/gaming.conf
default_sink=speakers
app:firefox=headphones
app:discord=speakers
app:steam*=headphones

# CLI commands
audio_profile.bash list              # List profiles
audio_profile.bash load <name>       # Apply profile
audio_profile.bash save <name>       # Save current routing
audio_profile.bash dmenu             # Interactive menu
audio_profile.bash move <app> <sink> # Move single app
audio_profile.bash status            # Show current routing
```

**Technical Considerations**:
- Use `pactl` for PulseAudio or `wpctl` for PipeWire
- Detect which sound server is running
- Handle sink-inputs (running streams) vs clients
- Match applications by name pattern (regex/glob)
- Handle apps that start after profile is loaded

**Related Tools**:
- `pactl list sink-inputs` - List running audio streams
- `pactl move-sink-input` - Move stream to different sink
- `pactl set-default-sink` - Set default output
- `wpctl` - PipeWire equivalent commands

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
