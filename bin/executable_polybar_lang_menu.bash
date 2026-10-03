#!/bin/bash
# Rofi menu of keyboard layouts. Called by polybar xkeyboard applet (right-click).
# Adds more layouts than the alt+shift toggle pair (e.g. georgian).

set -euo pipefail

choice=$(printf 'us,ru\nus,ge\nus,ru,ge\nus\nru\nge\n' \
    | rofi -dmenu -i -p 'Layout:') || exit 0

[[ -z "${choice}" ]] && exit 0

setxkbmap -layout "${choice}" -option grp:alt_shift_toggle

# Restart kbdd so per-window layout tracker sees the new layout set
pkill -x kbdd 2>/dev/null || true
kbdd &>/dev/null &
disown 2>/dev/null || true
