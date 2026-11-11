#!/bin/bash
# Called by tmux-resurrect via @resurrect-hook-post-restore-all, before
# the prefill hook. Kills every bootstrap session left on the server:
# the placeholders bin/tmux_boot.bash (_tmux_boot_<pid>) and
# tmux_main_session (_main_boot_<pid>) create to start a server for the
# restore, and any such session an older snapshot brought back (before
# the save filter existed, leaked placeholders were saved and restored
# again on every boot, adding one more each time).
#
# Nothing is killed unless a non-bootstrap session exists: a server with
# only bootstrap sessions would exit, and the boot paths still need it.
# Bash 3.2 compatible (macOS /bin/bash).
set -uo pipefail

BOOT_RE='^_(tmux|main)_boot_[0-9]+$'

sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null) || exit 0
grep -Evq "${BOOT_RE}|^$" <<<"${sessions}" || exit 0

grep -E "${BOOT_RE}" <<<"${sessions}" | while IFS= read -r session; do
    # `kill-ses` (unique prefix): tmux.conf aliases kill-session to an
    # interactive confirm-before, which fails without a client. `=`:
    # exact name, no prefix match.
    tmux kill-ses -t "=${session}" 2>/dev/null || true
done
exit 0
