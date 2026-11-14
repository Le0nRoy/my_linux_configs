# Helper Modules

This directory contains modular bash scripts that provide various system utilities and functions.

Interactive shells (bash and zsh) expose only the public `hh_*` helpers plus
the `hh_cp_ssh` alias: type `hh` then Tab to list them. Everything else is
script-private and loads only when `helper.bash <command>` runs.

## Module Structure

```
helper/
├── README.md        # This file
├── common.bash      # Shared variables and constants
├── tmux.bash        # Tmux session management
├── tmux_last_cmd.bash # Tmux pane prompt/history callbacks (bash)
├── aliases.shrc     # Interactive aliases shared by bash and zsh
├── shell.bash       # Portable interactive conveniences (hh_colors, hh_unar)
├── bash_exec.zsh    # zsh entry points that run Bash-only helpers in bash
├── git.bash         # Git utilities
├── system.bash      # System/display/notifications
├── storage.bash     # Mount/unmount operations
├── backup.bash      # Backup and sync functions
├── utils.bash       # Miscellaneous utilities
├── transfer.bash    # File transfer utilities (rsync/SSH)
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
- Sources `tmux_last_cmd.bash` for the pane history callbacks

### tmux_last_cmd.bash - Tmux Pane Plumbing
**Dependencies**: None
**Functions**: `_tmux_log_last_cmd`, `_tmux_pane_hist_path`, `_tmux_pane_hist_claim`,
`_tmux_pane_hist_sync` and their `PROMPT_COMMAND` registration. Interactive shells
load only this file, not the session builders.

### git.bash - Git Utilities
**Dependencies**: None
**Functions**:
- `hh_git_cleanout()` - Clean, fetch, pull, prune, and remove merged branches

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
**Dependencies**: None
**Functions**:
- `hh_sshfsctl [args]` - Run the interactive SSHFS mount manager `~/bin/sshfs.bash`
  with the given arguments (no arguments in a terminal opens its menu;
  `mount`, `umount`, `status`, `help`). It does not change caller options.
- `hh_gio_mount()` - Mount phone/device via GIO and `cd` into it
- `hh_gio_umount()` - Unmount device via GIO

### backup.bash - Backup Functions
**Dependencies**: None
**Functions**:
- `rclone_systemd()` - Run rclone with systemd logging
- `rclone_to_backup()` - Backup with filters

### utils.bash - Utility Functions
**Dependencies**: None
**Functions**:
- `hh_upgrade_system()` - System and package upgrades
- `hh_yay_no_cache()` - Non-interactive AUR upgrade, then trim the pacman cache
- `hh_adb_pull_music()` - Pull music from Android
- `hh_unzip_books()` - Unzip and rename fb2 books
- `hh_cut_video()` - Cut video segment
- `hh_gpg_decrypt <in.asc> <out>` - Decrypt into <out> and verify the signature
- `hh_gpg_encrypt <recipient>` - Sign and encrypt stdin (armoured, to stdout)

### shell.bash - Interactive Conveniences
**Dependencies**: None (portable; deployed on Linux and macOS)
**Functions**:
- `hh_colors()` - Print the terminal's ANSI color table
- `hh_unar <file>` - Extract an archive by extension

### aliases.shrc - Shared Aliases
Aliases for both shells (`ls`, `grep`, `cp -i`, ..., `claude_wrapper` →
`~/ai-wrapper/bin/claude_wrapper.bash`). Sourced before the helper modules so
function bodies expand them, and by the bash child of `bash_exec.zsh`.

### transfer.bash - File Transfer Utilities
**Dependencies**: None
**Functions**:
- `hh_rsync_ssh()` - Transfer files to/from a remote host over SSH using rsync with fast cipher; supports dry-run, compression, custom port/cipher
- `hh_rm_ssh()` - Delete files/directories on a remote host via a single SSH connection; supports dry-run and confirmation prompts

Aliases: `hh_cp_ssh` → `hh_rsync_ssh`

Bash completion (`~/.bash_completion.d/transfer.bash`) and zsh completion
(`compdef` in `~/.zshrc`) cover options, ciphers, SSH hosts from
`~/.ssh/config` and local paths.

### i3.bash - i3 Window Manager
**Dependencies**: `i3-save-tree`, `i3-msg`, `jq`
**Functions**:
- `hh_i3_save_ws <num>` - Save a single workspace to `~/.config/i3/workspaces/` and the chezmoi repo
- `hh_i3_save_chezmoi_ws()` - Save all active workspaces to `~/.config/i3/workspaces/` and the chezmoi repo
- `hh_i3_restore_ws <src> [target]` - Restore a workspace layout from the saved file into i3

### tmux_commands.bash - Tmux User Commands
**Dependencies**: None (bash/zsh common subset)
**Functions**:
- `hh_tmux_restore()` - Attach to tmux, starting the OS service first if needed
- `hh_git_watch()` - Watch git branch and short status (sent to panes by the session builders)

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

### Via Main Script (bash)
Sourcing `helper.bash` (as `.bashrc` does) loads public helpers only:
`tmux_last_cmd`, `tmux_commands`, `git`, `storage`, `utils`, `transfer` and
`shell`, plus `hh_i3_*` wrappers that run `i3.bash` in a subshell.
Script-private modules (tmux session builders, `system`, `backup`, `firefox`)
and their `_`-prefixed or nested helpers are never defined in the interactive
shell; they load only when `helper.bash` runs as a command. Re-sourcing
`.bashrc` is idempotent: `~/bin` and `~/ai-wrapper/bin` are added to `PATH`
at most once and the tmux prompt hooks are neither lost nor duplicated.

```bash
# Source main script (public helpers only)
source ~/bin/helper.bash

# Call a public function
hh_git_cleanout
hh_i3_save_ws 1
```

### zsh
`.zshrc` provides the same public helpers, aliases and environment
(`common.bash`, `~/bin/.env`, `$JOB_SETUP_FILE`, `PATH`):
- in-process: `tmux_commands.bash`, `git.bash`, `storage.bash` (helpers that
  must change the caller's cwd run in the calling shell; `hh_sshfsctl` only
  runs `~/bin/sshfs.bash`);
- via `bash_exec.zsh`: `shell`, `utils`, `transfer` and `i3` helpers rely on
  Bash semantics (mapfile, word splitting, failed globs, `printf %q`), so
  each runs its unchanged module in a child `bash` with the shared aliases.
  Output, exit status, quoted arguments, cwd and environment pass through;
  module internals never enter zsh.

Bash-only modules and completion callbacks are never sourced into zsh.

### Command-Line Interface
Use the main helper script as a command:

```bash
helper.bash tmux_session
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
transfer.bash (no dependencies)
i3.bash (no dependencies)
```

## Testing

Test individual modules:
```bash
# Test syntax
bash -n ~/bin/helper/tmux.bash
bash -n ~/bin/helper/transfer.bash

# Test by sourcing
source ~/bin/helper/common.bash
source ~/bin/helper/tmux.bash
# Call functions...

# Test transfer functions
source ~/bin/helper/transfer.bash
hh_rsync_ssh -h
hh_rm_ssh -h
```

Test via main script:
```bash
# Test command-line interface
helper.bash tmux_session

# Test function sourcing
source ~/bin/helper.bash
hh_git_cleanout

# Interactive isolation, re-source and baseline control-probe regression
bash tests/test_shell_helper_isolation.bash
# Public hh_ API, bash/zsh parity and PTY key tests
bash tests/test_hh_public_api.bash
```

## Backward Compatibility

All existing `helper.bash` dispatch commands remain unchanged
(`helper.bash command_name`). Interactive helpers were renamed to the `hh_`
prefix without compatibility aliases; `job_mount`/`job_umount` were removed
(the `JOB_*` variables and `$JOB_SETUP_FILE` sourcing remain).

## Maintenance

- Keep functions small and focused (20-30 lines max)
- Document dependencies in module headers
- Update README when adding/removing functions
- Validate syntax after changes
- Test backward compatibility
