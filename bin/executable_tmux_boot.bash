#!/bin/bash
# Shared startup script — invoked by both the macOS LaunchAgent
# (Library/LaunchAgents/local.tmux.plist) and the Linux systemd user
# unit (dot_config/systemd/user/tmux.service).
#
# Purpose: own the tmux server under launchd / systemd so no terminal
# quit (cmd+Q, force-quit, brew-upgrade replacing the tmux binary,
# terminal window close) can drop sessions. If a server is already
# running, no-op. Otherwise start it and fire tmux-resurrect's
# restore so the last snapshot is loaded before the operator opens
# a terminal and runs `tmux attach`.
set -euo pipefail

# LaunchAgents / systemd --user inherit a minimal PATH; Homebrew tmux
# and system tmux must both be reachable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Missing tmux is a legitimate state on a bare host — exit 0 so the
# service manager does not restart-loop.
TMUX_BIN=$(command -v tmux) || { echo "tmux not on PATH"; exit 0; }
RESTORE_SCRIPT="${HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

# Server already up: nothing to do — attach path handles the rest.
if "${TMUX_BIN}" list-sessions >/dev/null 2>&1; then
    exit 0
fi

# PID-suffixed bootstrap session name avoids colliding with a user
# session that happens to be called _bootstrap.
BOOT_SESSION="_tmux_boot_$$"
"${TMUX_BIN}" new-session -d -s "${BOOT_SESSION}"

# `tmux run-shell` (without -b) is synchronous, so no sleep is needed
# before or after: by the time it returns, restore.sh has finished
# creating sessions/windows/panes.
[[ -x "${RESTORE_SCRIPT}" ]] && "${TMUX_BIN}" run-shell "${RESTORE_SCRIPT}"

# Drop the bootstrap only if resurrect brought real sessions back;
# otherwise keep it so the server stays alive for a fresh attach.
if [[ $("${TMUX_BIN}" list-sessions 2>/dev/null | wc -l) -gt 1 ]]; then
    "${TMUX_BIN}" kill-session -t "${BOOT_SESSION}" 2>/dev/null || true
fi
