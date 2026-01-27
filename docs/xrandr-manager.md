# xrandr Manager Documentation

Comprehensive X display management tool with automatic configuration, named profiles, and rofi interface.

**Script**: `bin/executable_xrandr_manager.bash`
**Configuration Directory**: `~/.config/xrandr-manager/`

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [CLI Commands](#cli-commands)
- [Rofi Interface](#rofi-interface)
- [Configuration Files](#configuration-files)
- [Auto-Detection](#auto-detection)
- [Integration](#integration)
- [Troubleshooting](#troubleshooting)

## Overview

The xrandr manager provides a comprehensive solution for managing multiple displays on Linux. It wraps xrandr with additional features:

- Named display configurations with descriptions
- Automatic gap removal between displays
- Middle-axis alignment for different height displays
- Connection/disconnection event handling
- Interactive rofi menu interface
- Integration with polybar and desktop environment

## Features

### Configuration Management

- **Multiple named configurations**: Save different display setups with descriptive names
- **Default configuration**: Set a default config to auto-apply on display reconnection
- **Visual layout descriptions**: Configs show layout like `DP-2*@0,0 HDMI-0@2560,0`
- **Metadata storage**: Each config saves date, description, and full output details

### Automatic Display Handling

- **Connection detection**: Automatically applies default config when displays connect
- **Disconnection handling**: Moves primary to next available display
- **Gap removal**: Removes gaps between displays when reconfiguring
- **Middle-axis alignment**: Aligns display centers for different height monitors

### Desktop Integration

- **Polybar reload**: Automatically restarts polybar after display changes
- **Background reset**: Re-applies desktop background via feh
- **nvidia-settings integration**: Quick access to NVIDIA control panel

## CLI Commands

```bash
# Save current configuration
xrandr_manager.bash save <name> [description]
# Example: xrandr_manager.bash save "docked" "Desk setup with two monitors"

# Load saved configuration
xrandr_manager.bash load <name>
# Example: xrandr_manager.bash load docked

# Delete configuration
xrandr_manager.bash delete <name>

# List all saved configurations
xrandr_manager.bash list-configs

# Set default configuration (auto-applies on reconnection)
xrandr_manager.bash set-default <name>

# Auto-configure (detect and handle changes)
xrandr_manager.bash auto

# Remove gaps and align displays
xrandr_manager.bash rearrange

# Reload polybar and background
xrandr_manager.bash reload-desktop

# List all outputs and their status
xrandr_manager.bash list

# Open rofi interface
xrandr_manager.bash dmenu

# Continuous monitoring mode
xrandr_manager.bash monitor
```

## Rofi Interface

Launch with `xrandr_manager.bash dmenu` or the i3 keybinding `$mod+Shift+F10`.

### Main Menu

```
Screen Manager:
├── Load configuration      # Select and apply saved config
├── Save configuration      # Save current setup with name
├── Per-display settings    # Configure individual displays
├── Rearrange displays      # Remove gaps, align centers
├── Open nvidia-settings    # Launch NVIDIA control panel
├── Reload desktop          # Restart polybar, reset background
├── List outputs            # Show all output status
└── Exit
```

### Per-Display Settings

For each connected display:
```
Display Settings:
├── Enable (auto mode)      # Turn on with best resolution
├── Set resolution/mode     # Choose specific resolution
├── Set position            # Place relative to other displays
├── Disable                 # Turn off display
├── Set as primary          # Make this the primary display
└── Back
```

### Position Options

When positioning a display:
- Left of [other display]
- Right of [other display]
- Above [other display]
- Below [other display]
- Same as [other display] (mirror)

## Configuration Files

### Directory Structure

```
~/.config/xrandr-manager/
├── configs/                    # Saved configurations
│   ├── docked.conf
│   ├── mobile.conf
│   └── presentation.conf
├── current_state               # Last known display state
└── default_config              # Name of default configuration
```

### Configuration File Format

```conf
# Xrandr configuration: docked
# Description: Desk setup with two monitors
# Saved: 2025-12-05 14:30:00
# Layout: DP-2*@0,0 HDMI-0@2560,0
# Format: OUTPUT|MODE|POSITION|PRIMARY|ENABLED

DP-2|2560x1440|2560x1440+0+0|yes|yes
HDMI-0|2560x1440|2560x1440+2560+0|no|yes
eDP-1|auto|0x0+0+0|no|no
```

## Auto-Detection

### Monitor Mode

Run continuous monitoring for display changes:

```bash
xrandr_manager.bash monitor
```

This mode:
1. Checks for display state changes every 2 seconds
2. Detects new connections and applies default config
3. Detects disconnections and selects new primary
4. Removes gaps and realigns displays

### Integration with i3

Add to i3 config for automatic handling:

```
# Manual trigger via keybinding
bindsym $mod+Shift+F10 exec --no-startup-id ~/bin/xrandr_manager.bash dmenu

# Auto-configure on startup (optional)
exec_always --no-startup-id ~/bin/xrandr_manager.bash auto
```

### Integration with udev

For automatic handling when displays are plugged/unplugged, create a udev rule:

```bash
# /etc/udev/rules.d/95-monitor-hotplug.rules
ACTION=="change", SUBSYSTEM=="drm", RUN+="/usr/bin/su - USERNAME -c '/home/USERNAME/bin/xrandr_manager.bash auto'"
```

## Primary Display Selection

When the current primary display is disconnected:

1. First tries `DEFAULT_PRIMARY` (DP-2 by default)
2. If unavailable, selects next display clockwise from the disconnected one
3. Automatically rearranges remaining displays

## Key Functions

| Function | Purpose |
|----------|---------|
| `get_connected_outputs` | List all connected display outputs |
| `extract_mode` | Get current resolution of an output |
| `extract_position` | Get position (WxH+X+Y) of an output |
| `save_config` | Save current configuration to file |
| `load_config` | Apply saved configuration |
| `rearrange_displays` | Remove gaps and align middle axes |
| `auto_configure` | Handle connection/disconnection events |
| `dmenu_main_menu` | Show rofi interface |

## Troubleshooting

### Display Not Detected

```bash
# Check xrandr directly
xrandr --query

# List outputs via manager
xrandr_manager.bash list
```

### Configuration Won't Load

1. Check config file exists: `ls ~/.config/xrandr-manager/configs/`
2. Verify output names match current hardware
3. Check for syntax errors in config file

### Polybar Not Reloading

The script kills polybar and restarts via `polybar-supervisor.bash`. Ensure:
- `polybar-supervisor.bash` exists in `~/bin/`
- Polybar is installed and configured

### Gaps Between Displays

Run rearrange to fix:
```bash
xrandr_manager.bash rearrange
```

This calculates the average middle axis and positions all displays contiguously.

## Related Documentation

- [Repository Overview](repository-overview.md)
- [Helper Modules](../bin/helper/README.md) - Contains `polybar_start()` function
- [i3 Configuration](../dot_config/i3/) - Window manager integration
