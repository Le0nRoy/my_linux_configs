# Systemd User Services

This document describes the user-level systemd services managed by this dotfiles repository.

**Location**: `dot_config/systemd/user/` -> `~/.config/systemd/user/`

## Table of Contents

- [Overview](#overview)
- [Service Categories](#service-categories)
- [Notification Templates](#notification-templates)
- [rclone Bisync Services](#rclone-bisync-services)
- [File Synchronization](#file-synchronization)
- [Media Services](#media-services)
- [Mount Services](#mount-services)
- [tmux Session Persistence](#tmux-session-persistence)
- [Management Commands](#management-commands)

## Overview

All services run as user services (not system-wide) and use standardized patterns:
- Failure notifications via desktop notifications
- Success notifications for critical operations
- Environment files for configuration
- Helper scripts for complex logic

## Service Categories

| Category | Services | Purpose |
|----------|----------|---------|
| Cloud Backup | rclone-*-bisync | Bidirectional sync with cloud storage |
| File Sync | syncthing | Continuous file synchronization |
| Media | yt-mp3 | YouTube playlist to MP3 |
| Mounts | sshfs@ | SSHFS remote filesystem mounts |
| Utility | notification templates | Desktop notifications |

## Notification Templates

### failure-notification@.service

Sends desktop notification when a service fails.

```ini
[Unit]
Description=Failure notification for %i

[Service]
Type=oneshot
ExecStart=/usr/bin/notify-send -u critical "Service Failed" "%i"
```

### success-notification@.service

Sends desktop notification when a service succeeds.

```ini
[Unit]
Description=Success notification for %i

[Service]
Type=oneshot
ExecStart=/usr/bin/notify-send "Service Succeeded" "%i"
```

**Usage in other services**:
```ini
[Unit]
OnFailure=failure-notification@%n.service
OnSuccess=success-notification@%n.service
```

## rclone Bisync Services

Bidirectional synchronization with cloud storage using rclone's bisync feature.

### Service Pairs

Each sync target has three files:
- `rclone-*-bisync.service` - Regular sync operation
- `rclone-*-bisync.timer` - Scheduled trigger
- `rclone-*-bisync-resync.service` - Full resync (recovery)

### Available Sync Targets

#### 1. Encrypted Cloud (rclone-encrypt-cloud-bisync)

Syncs encrypted data with cloud storage.

```bash
# Regular sync (via timer)
systemctl --user status rclone-encrypt-cloud-bisync.timer

# Manual sync
systemctl --user start rclone-encrypt-cloud-bisync.service

# Full resync (after conflicts)
systemctl --user start rclone-encrypt-cloud-bisync-resync.service
```

#### 2. Linux Cloud (rclone-linux-cloud-bisync)

Syncs Linux-related files with cloud storage.

```bash
systemctl --user status rclone-linux-cloud-bisync.timer
systemctl --user start rclone-linux-cloud-bisync.service
```

#### 3. Media Cloud (rclone-media-cloud-bisync)

Syncs media files with cloud storage.

```bash
systemctl --user status rclone-media-cloud-bisync.timer
systemctl --user start rclone-media-cloud-bisync.service
```

#### 4. Minecraft Local (rclone-minecraft-local-bisync)

Syncs Minecraft data locally (likely between machines or backup location).

```bash
systemctl --user status rclone-minecraft-local-bisync.timer
systemctl --user start rclone-minecraft-local-bisync.service
```

### Configuration

Services use environment files for configuration:

```ini
[Service]
EnvironmentFile=%h/.config/environment.d/rclone-bisync.conf
ExecStart=/usr/bin/bash ${HOME}/bin/helper.bash rclone_bisync ...
```

Environment variables typically include:
- `BISYNC_*_FILTERS_FILE` - Filter rules file path
- `BISYNC_*_SOURCE` - Source path/remote
- `BISYNC_*_TARGET` - Target path/remote

### Resync Services

When bisync encounters conflicts or errors, a full resync may be required:

```bash
# Check service logs for errors
journalctl --user -u rclone-encrypt-cloud-bisync.service

# Run full resync (takes longer, resolves conflicts)
systemctl --user start rclone-encrypt-cloud-bisync-resync.service
```

**Warning**: Resync can take a long time depending on data size.

## File Synchronization

### syncthing.service

Continuous file synchronization daemon.

```ini
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization
After=network.target

[Service]
ExecStart=/usr/bin/syncthing serve --no-browser --logflags=0
Restart=on-failure

[Install]
WantedBy=default.target
```

**Management**:
```bash
# Enable and start
systemctl --user enable --now syncthing.service

# Check status
systemctl --user status syncthing.service

# View logs
journalctl --user -u syncthing.service -f

# Web UI (default)
# http://localhost:8384
```

## Media Services

### yt-mp3.service / yt-mp3.timer

Downloads YouTube playlists as MP3 files.

```ini
[Unit]
Description=Download YouTube playlist as mp3
OnFailure=failure-notification@%n.service
OnSuccess=success-notification@%n.service

[Service]
Type=oneshot
ExecStart=%h/bin/yt_playlist_mp3.bash
```

**Management**:
```bash
# Check timer status
systemctl --user status yt-mp3.timer

# Manual run
systemctl --user start yt-mp3.service

# View logs
journalctl --user -u yt-mp3.service
```

## Mount Services

### sshfs@.service

Template service for SSHFS mounts.

```ini
[Unit]
Description=SSHFS mount for %I
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/bin/sshfs-mount.sh start "%I"
ExecStop=%h/bin/sshfs-mount.sh stop "%I"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

**Usage** (template service with instance name):
```bash
# Mount a specific target (e.g., "server")
systemctl --user start sshfs@server.service

# Unmount
systemctl --user stop sshfs@server.service

# Enable auto-mount on login
systemctl --user enable sshfs@server.service
```

The instance name (`%I`) is passed to `sshfs-mount.sh` which handles the actual mount configuration.

## tmux Session Persistence

Two separate mechanisms are involved. They are often confused.

| | Plugin persistence (tmux-resurrect + tmux-continuum) | Service lifetime (`tmux.service` / LaunchAgent) |
|---|---|---|
| What it does | Writes snapshot files: sessions, windows, layout/geometry, pane cwd, pane contents, selected programs (`$XDG_STATE_HOME/tmux/resurrect/`) | Decides which process tree owns the tmux server and when it starts |
| When | continuum autosave every 5 min, prefix + `C-s`/`C-r` manually | `tmux.service` start (`default.target`), LaunchAgent `RunAtLoad` |
| Can start a server | No, it runs only inside a running server | Yes: `bin/tmux_boot.bash` starts the server and runs resurrect's `restore.sh` |
| Survives | Files survive anything; they restore only layout and state | A server started by the unit lives in the unit's cgroup, not in a login session scope |
| Does not preserve | Running processes, unsaved editor buffers, work after the last snapshot | Nothing if the server was started elsewhere first |

Restore-side helpers:
- per-pane shell history files and `.last` files under `$XDG_STATE_HOME/tmux/panes/` (mode 0600, directory 0700);
- `bin/tmux_prefill_last_cmd.bash` (resurrect post-restore hook) types each pane's last command
  **without Enter**. It skips non-shell panes and empty or whitespace-only text. It refuses text
  containing any control byte (LF, CR, Tab, ESC, DEL, Ctrl+O, NUL, ...), because Readline/ZLE run
  the line on LF/CR/Ctrl+O even when the text is typed literally. Assumes default emacs keymaps in a
  UTF-8 locale; keys rebound by the user are out of scope;
- `bin/tmux_boot.bash` with a server already running: exits 0 and changes nothing. With no server:
  creates `_tmux_boot_<pid>`, runs the restore, and drops that session only if real sessions came back.

### Service ownership: what is and is not verified

`Type=forking` + `ExecStart=%h/bin/tmux_boot.bash`: if a tmux server already runs on the default
socket (for example started from a terminal inside a login `session-N.scope`), the boot script
exits 0 without starting anything. The unit then owns no process, and the existing server stays
in the login scope. Whether that server survives logout depends on logind `KillUserProcesses`,
the user manager and linger; a session scope alone does not imply loss.

`tests/test_tmux_preservation.bash` covers the script, prefill, hook and file-ownership behaviour
with a private socket and synthetic HOME/XDG. It does **not** cover the systemd lifecycle (cgroup
placement, active/dead state after each branch, boot with linger, logout). The suite reports
that as GAP. Real tmux + plugin runs need `tmux` installed and local plugin checkouts
(nothing is downloaded):

```bash
F_TMUX_PLUGIN_ROOT=/path/with/tpm,tmux-resurrect,tmux-continuum bash tests/test_tmux_preservation.bash
```

Plugin inputs must be clean git checkouts outside the host's runtime plugin dirs
(`~/.tmux/plugins`, `~/.config/tmux/plugins` are refused), with tpm at `TPM_TAG_SHA` from
`run_once_install-tpm-plugins.bash`. The suite copies them into its temp tree (never links),
logs each full SHA, and checks after the run that every source is byte-, mode- and
mtime-identical. Every tmux call goes through a guard that works out the socket the way tmux
does (`-S`, then `-L`, then `$TMUX`, then the default label, across option order and clusters)
and refuses anything outside the temp tree. The guard is first on the server's PATH, so pane
shells and resurrect's `run-shell` scripts reach it too. Before the first tmux call the suite
creates the socket parent `<temp>/tmuxtmp/tmux-UID` itself (0700, owned by the test user, not
a link): tmux does not create the parents of an explicit `-S` path. A test server is stopped
only after it reports the test socket and a tmux PID, on the normal path and in the exit trap.
The first owner-side native run (tmux 3.8) failed at server start on that missing socket
parent. The next one started the server but found no `.last` for `f_dev:1.0`: the Bash and
Zsh `_tmux_log_last_cmd` loggers resolved `#S:#I.#P` without a target, i.e. for the client's
active pane, so a command run in an inactive pane was recorded under another pane's position.
Both loggers now resolve the calling pane with `-t "$TMUX_PANE"` and skip when `TMUX_PANE` is
missing, not a `%<n>` pane ID, or unknown to tmux. The third run reached the end of the real
save, stop, boot and restore; its 6 failures were in the test's own assumptions, now fixed:
the prefill checks read `capture-pane -J` (long commands wrap at the pane width), and the
before/after inventory drops only each `window_layout`'s checksum and pane IDs (tmux gives
restored panes fresh `%N` IDs; the bootstrap session takes `%0`). Sizes, offsets, split
orientation, active flags, names and working directories are still compared, with negative
controls. Real save/restore stays unproven until a native run passes.

The agent runner has no systemd user manager, no container daemon and no user namespaces,
so these lifecycle checks stay open acceptance items until the owner either runs them or grants
a disposable systemd sandbox (a VM, or a container with systemd as PID 1, which needs a
privileged or cgroup-delegated runtime).

Smallest systemd verification option (owner-run, in a **disposable VM or systemd-booted
container with a throwaway user**, never against the owner's live server):

```bash
# as the throwaway user, with the repo's files deployed to its HOME
systemctl --user daemon-reload
systemctl --user start tmux.service                      # branch: no server
systemctl --user show -p ActiveState,SubState,MainPID,ControlGroup tmux.service
cat /proc/"$(tmux display-message -p '#{pid}')"/cgroup   # expect .../tmux.service
tmux list-sessions                                       # restored sessions, no _tmux_boot_*
systemctl --user stop tmux.service
tmux new-session -d -s unmanaged                         # branch: server already running
systemctl --user start tmux.service
systemctl --user show -p ActiveState,SubState tmux.service
cat /proc/"$(tmux display-message -p '#{pid}')"/cgroup   # still the login scope
tmux kill-server                                         # throwaway server only
# boot with linger / logout (root in the VM, throwaway user only)
systemctl --user enable tmux.service
loginctl enable-linger throwaway && reboot               # after boot, without logging in:
systemctl --machine=throwaway@ --user show -p ActiveState,SubState tmux.service
loginctl terminate-user throwaway                        # logout: server must survive with linger
systemctl --machine=throwaway@ --user show -p ActiveState,SubState tmux.service
```

### Owner maintenance transition (manual, owner-confirmed)

Moving a live server under `tmux.service` restarts it. Running programs, unsaved buffers and
anything after the last snapshot are lost. Do this only in a planned maintenance window, after
the deployed config includes the prefill/hook/boot fixes, with explicit owner confirmation at
step 3. Agents must not run it.

1. Prepare: save editor buffers, finish or stop running jobs, note what each pane runs.
2. Snapshot and back up: prefix + `C-s`, then
   `cp -a "${XDG_STATE_HOME:-$HOME/.local/state}/tmux" ~/tmux-state-backup-"$(date +%F)"` and
   `tmux list-windows -a > ~/tmux-inventory-before.txt`.
3. Stop the old server (owner-confirmed): `tmux kill-server`.
4. Start under the unit: `systemctl --user daemon-reload && systemctl --user start tmux.service`.
   Enabling at login (`systemctl --user enable tmux.service`) and boot without login
   (`loginctl enable-linger "$USER"`) are separate owner decisions.
5. Verify: `systemctl --user show -p ActiveState,SubState,ControlGroup tmux.service`, the server's
   `/proc/<pid>/cgroup` ends in `tmux.service`, `tmux list-windows -a` matches the inventory, and
   no `_tmux_boot_*` session is left. Prefilled commands wait for Enter.
6. Rollback if the unit fails: `systemctl --user stop tmux.service`, restore the backed-up state
   directory if needed, then start a server by hand and restore through tmux (restore.sh needs
   `$TMUX`, so never run it directly):
   `tmux new-session -d -s _rescue && tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`.

## Management Commands

### Common Operations

```bash
# List all user services
systemctl --user list-units --type=service

# List all user timers
systemctl --user list-timers

# Reload after configuration changes
systemctl --user daemon-reload

# View logs for a service
journalctl --user -u <service-name> -f

# Check why a service failed
systemctl --user status <service-name>
journalctl --user -u <service-name> --since "1 hour ago"
```

### Enabling Services

After deploying with chezmoi:

```bash
# Apply chezmoi changes
chezmoi apply

# Reload systemd
systemctl --user daemon-reload

# Enable specific services
systemctl --user enable --now syncthing.service
systemctl --user enable --now rclone-encrypt-cloud-bisync.timer
```

### Debugging

```bash
# Test a service manually
systemctl --user start <service>.service

# Check exit status
systemctl --user show -p ExecMainStatus <service>.service

# View detailed logs
journalctl --user -u <service>.service -n 50 --no-pager

# Check environment
systemctl --user show-environment
```

## Service Dependencies

```
network-online.target
    └── sshfs@.service

default.target
    ├── tmux.service
    ├── syncthing.service
    ├── rclone-*-bisync.timer
    └── sshfs@.service (if enabled)
```

## Related Documentation

- [Repository Overview](repository-overview.md)
- [Helper Modules](../bin/helper/README.md) - Contains `rclone_bisync` function
- [rclone Documentation](https://rclone.org/bisync/)
- [Syncthing Documentation](https://docs.syncthing.net/)
