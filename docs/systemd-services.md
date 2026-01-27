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
    ├── syncthing.service
    ├── rclone-*-bisync.timer
    └── sshfs@.service (if enabled)
```

## Related Documentation

- [Repository Overview](repository-overview.md)
- [Helper Modules](../bin/helper/README.md) - Contains `rclone_bisync` function
- [rclone Documentation](https://rclone.org/bisync/)
- [Syncthing Documentation](https://docs.syncthing.net/)
