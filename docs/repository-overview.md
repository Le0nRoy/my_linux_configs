# Chezmoi Dotfiles Repository

This document provides an overview of the chezmoi dotfiles repository and serves as the main README for the repository itself.

**Important**: This file is repository-specific documentation and is NOT deployed to the home directory (it's in `docs/` which is ignored by chezmoi).

## Table of Contents

- [What is This Repository?](#what-is-this-repository)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Key Components](#key-components)
- [Documentation Guide](#documentation-guide)
- [Configuration Management](#configuration-management)
- [Chezmoi Naming Conventions](#chezmoi-naming-conventions)

## What is This Repository?

This is a [chezmoi](https://www.chezmoi.io/) managed dotfiles repository for an Arch Linux system with i3 window manager. It contains:

- Shell configurations (bash, zsh, vim)
- Window manager configuration (i3, polybar, picom)
- System utilities and helper scripts
- AI agent sandboxing infrastructure
- Automated backup and sync services
- Display management tools

**Owner**: Vadim (le0nRoy)
**Platform**: Arch Linux
**Window Manager**: i3wm
**Shell**: bash (primary)

## Repository Structure

```
~/.local/share/chezmoi/
├── AGENTS.md                     # System-wide AI agent rules (deployed to ~/)
├── CLAUDE.md                     # Redirect to AGENTS.md (deployed to ~/)
├── TODO.md                       # Active development tasks (NOT deployed)
├── .chezmoiignore                # Files to exclude from deployment
│
├── bin/                          # Scripts and utilities
│   ├── executable_*.bash         # Standalone scripts
│   ├── helper/                   # Modular helper functions
│   │   ├── README.md             # Helper module documentation
│   │   ├── common.bash           # Shared variables
│   │   ├── tmux.bash             # Tmux session management
│   │   ├── git.bash              # Git utilities
│   │   ├── system.bash           # System/display/notifications
│   │   ├── storage.bash          # Mount/unmount operations
│   │   ├── backup.bash           # Backup and sync functions
│   │   └── utils.bash            # Miscellaneous utilities
│   └── ai_agent_universal_wrapper.bash  # Sandbox infrastructure
│
├── dot_config/                   # Application configs (~/.config/)
│   ├── i3/                       # i3wm configuration
│   ├── polybar/                  # Status bar
│   ├── alacritty/                # Terminal emulator
│   ├── tmux/                     # Terminal multiplexer
│   ├── autorandr/                # Display profiles
│   ├── systemd/user/             # User systemd services
│   └── ...                       # Other app configs
│
├── dot_local/share/applications/ # Desktop entries
│
├── docs/                         # Repository documentation (NOT deployed)
│   ├── README.md                 # Documentation guide
│   ├── repository-overview.md   # This file
│   ├── xrandr-manager.md         # Display management docs
│   ├── ai-agent-sandboxing.md    # Sandboxing architecture
│   ├── systemd-services.md       # Systemd services docs
│   └── completed/                # Completed task documentation
│
└── [Root dotfiles]               # .bashrc, .vimrc, .gitconfig, etc.
```

## Quick Start

### Installing on a New Machine

1. **Install chezmoi**:
   ```bash
   # Arch Linux
   sudo pacman -S chezmoi

   # Or using the official installer
   sh -c "$(curl -fsLS get.chezmoi.io)"
   ```

2. **Initialize with this repository**:
   ```bash
   chezmoi init <your-git-repo-url>
   ```

3. **Preview changes**:
   ```bash
   chezmoi diff
   ```

4. **Apply configuration**:
   ```bash
   chezmoi apply
   ```

### Daily Usage

```bash
# Edit a managed file
chezmoi edit ~/.bashrc

# See what would change
chezmoi diff

# Apply changes
chezmoi apply

# Add a new file to management
chezmoi add ~/.newconfig

# Update from remote repository
chezmoi update
```

## Key Components

### AI Agent Sandboxing

AI development assistants (Claude, Codex, Cursor) run in bubblewrap sandboxes with resource limits:

- `bin/ai_agent_universal_wrapper.bash` - Core sandboxing infrastructure
- `bin/executable_claude_wrapper.bash` - Claude CLI wrapper
- `bin/executable_codex_wrapper.bash` - Codex CLI wrapper
- `bin/executable_cursor_agent_wrapper.bash` - Cursor wrapper

See: [docs/ai-agent-sandboxing.md](ai-agent-sandboxing.md)

### Display Management

Comprehensive xrandr-based display management with rofi interface:

- `bin/executable_xrandr_manager.bash` - Main display manager
- Save/load named display configurations
- Automatic gap removal and display alignment
- Auto-detection of connection/disconnection events

See: [docs/xrandr-manager.md](xrandr-manager.md)

### Helper Functions

Modular bash utilities for common tasks:

- `bin/executable_helper.bash` - Main entry point
- `bin/helper/` - Modular function libraries

See: [bin/helper/README.md](../bin/helper/README.md)

### Systemd Services

User-level systemd services for automation:

- rclone bisync services (cloud backup)
- Syncthing file synchronization
- SSHFS mount management
- YouTube playlist downloader

See: [docs/systemd-services.md](systemd-services.md)

## Documentation Guide

### System-Wide vs Repository-Specific

| File | Location | Deployed | Purpose |
|------|----------|----------|---------|
| `AGENTS.md` | Root | Yes (`~/`) | AI agent rules for ALL directories |
| `CLAUDE.md` | Root | Yes (`~/`) | Redirect to AGENTS.md |
| `docs/*` | docs/ | No | Repository-specific documentation |
| `TODO.md` | Root | No | Development task tracking |

### Why This Separation?

- **AGENTS.md** contains rules that should be available system-wide for AI agents working in any directory
- **docs/** contains information specific to this repository's development and maintenance
- This prevents repository-specific documentation from cluttering the home directory

## Configuration Management

### Template Files (`.tmpl`)

Some files use chezmoi's template system for machine-specific configuration:

```
dot_config/alacritty/alacritty.toml.tmpl  # Terminal settings
dot_config/i3/config.tmpl                   # i3wm configuration
dot_config/polybar/config.ini.tmpl          # Status bar
```

Templates can access:
- `.chezmoi.hostname` - Machine hostname
- `.chezmoi.os` - Operating system
- Environment variables

### Machine-Specific Configurations

The repository supports multiple machines through:
- Template conditionals based on hostname
- Separate polybar configs in `polybar/configs/`
- Display profiles in `autorandr/`

## Chezmoi Naming Conventions

Understanding chezmoi prefixes is essential:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `dot_` | Hidden file (`.`) | `dot_bashrc` -> `~/.bashrc` |
| `executable_` | Make executable (+x) | `executable_script.bash` |
| `private_` | Restricted permissions (600/700) | `private_ssh/` |
| `.tmpl` | Template file | `dot_env.tmpl` -> `~/.env` |
| `run_` | Run script during apply | `run_once_setup.bash` |

**Warning**: Never modify these prefixes without understanding their impact on deployment.

## Related Documentation

- [AI Agent Guidelines](../AGENTS.md) - Rules for AI development assistants
- [Helper Modules](../bin/helper/README.md) - Bash utility functions
- [xrandr Manager](xrandr-manager.md) - Display management
- [AI Agent Sandboxing](ai-agent-sandboxing.md) - Sandbox architecture
- [Systemd Services](systemd-services.md) - Automated services
- [Chezmoi Documentation](https://www.chezmoi.io/) - Official chezmoi docs
