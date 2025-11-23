# Helper.bash Refactoring Plan

**Date**: 2025-11-17
**Status**: Planning
**Branch**: refactor_helper

## Current State

- **File**: `bin/executable_helper.bash`
- **Lines**: 640
- **Functions**: 23 functions
- **Issues**: Monolithic, hard to maintain, mixed concerns

## Refactoring Goals

1. Split into logical modules by functionality
2. Preserve ability to call functions directly (sourcing support)
3. Maintain backward compatibility with existing case statement commands
4. Keep single entry point (`helper.bash`) for command-line usage
5. Improve maintainability and testability

## Proposed Module Structure

```
bin/
├── executable_helper.bash           # Main entry point (slim wrapper)
├── helper/                          # Helper modules directory
│   ├── common.bash                  # Shared variables and utilities
│   ├── tmux.bash                    # Tmux session management
│   ├── git.bash                     # Git utilities
│   ├── system.bash                  # System/display/notifications
│   ├── storage.bash                 # Mount/unmount operations
│   ├── backup.bash                  # Backup and sync functions
│   └── utils.bash                   # Miscellaneous utilities
```

## Module Breakdown

### 1. `helper/common.bash` - Shared Constants and Functions

**Purpose**: Define shared variables and common utilities

**Contents**:
- `HOME_HELPER_UNIQ_SCRIPT_NAME`, `HOME_HELPER_UNIQ_SCRIPT_PATH`, `HOME_HELPER_UNIQ_SCRIPT_DIR`
- `JOB_MOUNT_DIR`, `JOB_SETUP_FILE`, `JOB_TEARDOWN_FILE`
- `PORT_SWAGGER_UI`, `PORT_SWAGGER_EDITOR`
- `DESKTOP_BG`, `LOCK_SCREEN_IMAGE`
- `TMUX_SESSION`
- Common utility functions (if any)

### 2. `helper/tmux.bash` - Tmux Functions

**Functions**:
- `tmux_ide_session()` - Create/attach IDE tmux session
- `tmux_main_session()` - Create/attach main tmux session

**Dependencies**: `common.bash` (for TMUX_SESSION)

### 3. `helper/git.bash` - Git Functions

**Functions**:
- `git_cleanout()` - Clean and prune git repository

**Dependencies**: None

### 4. `helper/system.bash` - System/Display/Notifications

**Functions**:
- `get_display()` - Get current DISPLAY
- `set_us_ru_layout()` - Set US/RU keyboard layout
- `set_background()` - Set desktop background
- `polybar_start()` - Restart polybar
- `send_notification_brightnes()` - Send brightness notification
- `send_notification_volume()` - Send volume notification
- `set_volume()` - Control audio volume

**Dependencies**: `common.bash` (for DESKTOP_BG, SINK_NAME)

### 5. `helper/storage.bash` - Storage/Mount Functions

**Functions**:
- `sshfsctl()` - Control SSHFS mounts
- `gio_mount()` - Mount device via GIO
- `gio_umount()` - Unmount device via GIO
- `job_mount()` - Mount encrypted job directory
- `job_umount()` - Unmount job directory

**Dependencies**: `common.bash` (for JOB_* variables)

### 6. `helper/backup.bash` - Backup/Sync Functions

**Functions**:
- `rclone_systemd()` - Run rclone with systemd logging
- `rclone_to_backup()` - Backup to destination with filters

**Dependencies**: None

### 7. `helper/utils.bash` - Utility Functions

**Functions**:
- `upgrade_system()` - System upgrade
- `adb_pull_music()` - Pull music from Android
- `unzip_books()` - Unzip and rename book files
- `cut_video()` - Cut video segment
- `gpg_decrypt()` - Decrypt GPG file
- `gpg_encrypt()` - Encrypt with GPG

**Dependencies**: None

## Main Entry Point Design

### `executable_helper.bash` Structure

```bash
#!/bin/bash

# Script metadata
HOME_HELPER_UNIQ_SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
HOME_HELPER_UNIQ_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
HOME_HELPER_UNIQ_SCRIPT_DIR="${HOME_HELPER_UNIQ_SCRIPT_PATH%/*}"

# Source modules
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/common.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/tmux.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/git.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/system.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/storage.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/backup.bash"
source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper/utils.bash"

# Autocompletion
_helper_script() { ... }
complete -F _helper_script "$HOME_HELPER_UNIQ_SCRIPT_NAME"

# Error handler
show_error_and_usage() { ... }

# Check if sourced or executed
EXEC_NAME=$0
EXEC_NAME="${EXEC_NAME[0]##*/}"
if [[ ! "$EXEC_NAME" == "$HOME_HELPER_UNIQ_SCRIPT_NAME" ]]; then
    # Sourced - just export PATH
    export PATH="$HOME/bin:$PATH"
    [[ -e "$JOB_SETUP_FILE" ]] && source "$JOB_SETUP_FILE"
    return
fi

# Main case statement (unchanged)
case "$1" in
    "toggle_touchpad") ... ;;
    "tmux_session") tmux_main_session ;;
    ...
esac
```

## Migration Strategy

### Phase 1: Create Module Structure
1. Create `bin/helper/` directory
2. Create empty module files
3. Add common.bash with shared variables

### Phase 2: Extract Functions
1. Copy functions to appropriate modules
2. Add module headers and documentation
3. Ensure proper variable scoping

### Phase 3: Update Main Script
1. Add source statements for all modules
2. Test that all functions are available
3. Verify case statement still works

### Phase 4: Testing
1. Test direct function calls (sourcing)
2. Test command-line interface
3. Test backward compatibility
4. Verify .bashrc integration

### Phase 5: Cleanup
1. Remove duplicate code from main script
2. Add comments and documentation
3. Update TODO.md

## Backward Compatibility

### Function Sourcing
Users can source individual modules:
```bash
source ~/bin/helper/tmux.bash
tmux_main_session
```

Or source the main script:
```bash
source ~/bin/helper.bash
tmux_main_session
```

### Command-Line Interface
All existing commands remain unchanged:
```bash
helper.bash tmux_session
helper.bash git_cleanout
helper.bash volume raise
```

### .bashrc Integration
Existing sourcing in .bashrc continues to work:
```bash
source ~/bin/helper.bash
```

## Benefits

1. **Modularity**: Each module has a single responsibility
2. **Maintainability**: Easier to find and modify functions
3. **Testability**: Can test modules independently
4. **Reusability**: Modules can be sourced separately
5. **Clarity**: Clear separation of concerns
6. **Extensibility**: Easy to add new modules

## Implementation Order

1. Create `helper/common.bash` with shared variables
2. Create `helper/tmux.bash` with tmux functions
3. Create remaining modules (git, system, storage, backup, utils)
4. Update main `executable_helper.bash` to source modules
5. Test all functionality
6. Document changes

## Testing Checklist

- [ ] Source main script and call functions directly
- [ ] Run commands via command-line interface
- [ ] Verify .bashrc sourcing works
- [ ] Test each module independently
- [ ] Check autocompletion works
- [ ] Verify job mount/umount functions
- [ ] Test tmux sessions creation
- [ ] Validate all case statement commands

## Notes

- Keep original helper.bash as backup during migration
- Ensure modules are properly quoted (follow AGENTS.md/CLAUDE.md)
- Add bash syntax validation for each module
- Consider adding module version tracking
- Document dependencies between modules
