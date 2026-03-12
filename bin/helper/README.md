# Helper Modules

This directory contains modular bash scripts that provide various system utilities and functions.

## Module Structure

```
helper/
├── README.md        # This file
├── common.bash      # Shared variables and constants
├── tmux.bash        # Tmux session management
├── git.bash         # Git utilities
├── system.bash      # System/display/notifications
├── storage.bash     # Mount/unmount operations
├── backup.bash      # Backup and sync functions
├── utils.bash       # Miscellaneous utilities
└── i3.bash          # i3 window manager utilities
```

## Modules Overview

### common.bash - Shared Constants
**Dependencies**: None
**Provides**: Shared variables used across modules
- `JOB_MOUNT_DIR`, `JOB_SETUP_FILE`, `JOB_TEARDOWN_FILE`
- `PORT_SWAGGER_UI`, `PORT_SWAGGER_EDITOR`
- `DESKTOP_BG`, `LOCK_SCREEN_IMAGE`
- `TMUX_SESSION`, `SINK_NAME`

### tmux.bash - Tmux Management
**Dependencies**: `common.bash` (for TMUX_SESSION)
**Functions**:
- `tmux_ide_session()` - Create/attach IDE-focused tmux session
- `tmux_main_session()` - Create/attach main tmux session with custom layout

### git.bash - Git Utilities
**Dependencies**: None
**Functions**:
- `git_cleanout()` - Clean, fetch, pull, prune, and remove merged branches

### system.bash - System Functions
**Dependencies**: `common.bash` (for DESKTOP_BG, LOCK_SCREEN_IMAGE, SINK_NAME)
**Functions**:
- `get_display()` - Get current DISPLAY variable
- `set_us_ru_layout()` - Set US/RU keyboard layout
- `set_background()` - Set desktop background
- `polybar_start()` - Restart polybar
- `send_notification_brightnes()` - Send brightness notification
- `send_notification_volume()` - Send volume notification
- `set_volume()` - Control audio volume

### storage.bash - Storage Operations
**Dependencies**: `common.bash` (for JOB_* variables)
**Functions**:
- `sshfsctl()` - Control SSHFS mounts via systemd
- `gio_mount()` - Mount phone/device via GIO
- `gio_umount()` - Unmount device via GIO
- `job_mount()` - Mount encrypted job directory
- `job_umount()` - Unmount job directory

### backup.bash - Backup Functions
**Dependencies**: None
**Functions**:
- `rclone_systemd()` - Run rclone with systemd logging
- `rclone_to_backup()` - Backup with filters

### utils.bash - Utility Functions
**Dependencies**: None
**Functions**:
- `upgrade_system()` - System and package upgrades
- `adb_pull_music()` - Pull music from Android
- `unzip_books()` - Unzip and rename fb2 books
- `cut_video()` - Cut video segment
- `gpg_decrypt()` - Decrypt GPG file
- `gpg_encrypt()` - Encrypt with GPG

### i3.bash - i3 Window Manager
**Dependencies**: `i3-save-tree`, `i3-msg`, `jq`
**Functions**:
- `i3_save_ws <num>` - Save a single workspace to `~/.config/i3/workspaces/` and the chezmoi repo
- `i3_save_chezmoi_ws()` - Save all active workspaces to `~/.config/i3/workspaces/` and the chezmoi repo
- `i3_restore_ws <src> [target]` - Restore a workspace layout from the saved file into i3

## Usage

### Direct Module Sourcing
You can source individual modules directly:

```bash
# Source specific module
source ~/bin/helper/tmux.bash
tmux_main_session

# Source common variables first if needed
source ~/bin/helper/common.bash
source ~/bin/helper/system.bash
set_background
```

### Via Main Script
The main `helper.bash` script sources all modules automatically:

```bash
# Source main script (sources all modules)
source ~/bin/helper.bash

# Call any function
git_cleanout
tmux_main_session
```

### Command-Line Interface
Use the main helper script as a command:

```bash
helper.bash tmux_session
helper.bash git_cleanout
helper.bash volume raise
```

## Development Guidelines

### Code Style
- Quote all variables: `"${var}"`
- Use `[[ ]]` for conditions
- Function names in `snake_case`
- Add comments for complex logic
- Follow AGENTS.md and CLAUDE.md guidelines

### Adding New Functions

1. Determine which module the function belongs to
2. Add function with proper documentation
3. Update this README
4. Test the function independently
5. Validate syntax: `bash -n module.bash`

### Creating New Modules

1. Create `helper/newmodule.bash`
2. Add module header comment
3. List dependencies
4. Implement functions
5. Update main `helper.bash` to source it
6. Update this README

## Module Dependencies

```
common.bash (no dependencies)
    ├── tmux.bash
    ├── system.bash
    └── storage.bash

git.bash (no dependencies)
backup.bash (no dependencies)
utils.bash (no dependencies)
i3.bash (no dependencies)
```

## Testing

Test individual modules:
```bash
# Test syntax
bash -n ~/bin/helper/tmux.bash

# Test by sourcing
source ~/bin/helper/common.bash
source ~/bin/helper/tmux.bash
# Call functions...
```

Test via main script:
```bash
# Test command-line interface
helper.bash tmux_session

# Test function sourcing
source ~/bin/helper.bash
tmux_main_session
```

## Backward Compatibility

All existing `helper.bash` commands remain unchanged:
- Command-line: `helper.bash command_name`
- Sourcing: `source ~/bin/helper.bash; function_name`
- .bashrc integration continues to work

## Maintenance

- Keep functions small and focused (20-30 lines max)
- Document dependencies in module headers
- Update README when adding/removing functions
- Validate syntax after changes
- Test backward compatibility
