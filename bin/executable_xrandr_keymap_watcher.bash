#!/bin/bash
# Watch xrandr for external changes (nvidia-settings, external xrandr calls,
# driver reloads) and re-apply keyboard layout. Runs as an i3 exec daemon.
# ponytail: polling every 2s; switch to `srandrd` if event-driven wanted.

set -euo pipefail

INTERVAL="${XRANDR_WATCH_INTERVAL:-2}"

prev=""
while true; do
    curr=$(xrandr --query 2>/dev/null | sha1sum | awk '{print $1}') || curr=""
    if [[ -n "${prev}" && "${curr}" != "${prev}" ]]; then
        "${HOME}/bin/helper.bash" set_us_ru_keymap &>/dev/null || true
    fi
    prev="${curr}"
    sleep "${INTERVAL}"
done
