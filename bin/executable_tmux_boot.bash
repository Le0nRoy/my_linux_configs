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

# launchd starts agents in `/` (systemd user units start in $HOME). The
# server keeps this cwd, and tmux resolves an empty or relative `-c`
# against it — resurrect restores a pane saved with an empty path as
# `new-window -c ""` — so without this such panes land in `/` on macOS.
cd "${HOME}" || cd /

# Bootstrap sessions (this script's and tmux_main_session's). Shared
# with bin/tmux_bootstrap_cleanup.bash and tmux_resurrect_save_filter.bash.
BOOT_RE='^_(tmux|main)_boot_[0-9]+$'

# Server already up: nothing to do — attach path handles the rest.
if "${TMUX_BIN}" list-sessions >/dev/null 2>&1; then
    exit 0
fi

# PID-suffixed bootstrap session name avoids colliding with a user
# session that happens to be called _bootstrap.
BOOT_SESSION="_tmux_boot_$$"
# TMUX_BOOT_RESTORE=1 tells tmux.conf this script owns the restore, so
# tmux-continuum's background auto-restore stays off for this server.
# Two restores racing duplicate panes and type every prefill twice.
TMUX_BOOT_RESTORE=1 "${TMUX_BIN}" new-session -d -s "${BOOT_SESSION}"

# `tmux run-shell` (without -b) is synchronous, so no sleep is needed
# before or after: by the time it returns, restore.sh has finished
# creating sessions/windows/panes.
[[ -x "${RESTORE_SCRIPT}" ]] && "${TMUX_BIN}" run-shell "${RESTORE_SCRIPT}"

# Drop the bootstrap once a real session exists (the post-restore hook
# usually did so already). If nothing came back, rename it instead of
# keeping a bootstrap name: the server must stay alive for a fresh
# attach, and bootstrap sessions are never saved (save filter) and are
# killed after every restore (cleanup hook), so a session the operator
# works in must not carry that name.
# `kill-ses` (unique prefix), not `kill-session`: tmux.conf aliases
# kill-session to an interactive confirm-before, which rejects the
# extra `-t` argument, so the bootstrap session would silently leak.
# The session list is captured first: `grep -q` closing the pipe early
# would fail the pipeline under pipefail.
sessions=$("${TMUX_BIN}" list-sessions -F '#{session_name}' 2>/dev/null || true)
if grep -Evq "${BOOT_RE}|^$" <<<"${sessions}"; then
    "${TMUX_BIN}" kill-ses -t "=${BOOT_SESSION}" 2>/dev/null || true
else
    "${TMUX_BIN}" rename-session -t "=${BOOT_SESSION}" main 2>/dev/null || true
fi
