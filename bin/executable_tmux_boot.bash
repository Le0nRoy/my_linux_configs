#!/bin/bash
# Launched by the local.tmux LaunchAgent at user login on macOS.
#
# Purpose: own the tmux server under launchd so no terminal quit
# (cmd+Q, force-quit, brew-upgrade replacing the tmux binary) can drop
# sessions. If a server is already running, no-op. Otherwise start it
# and fire tmux-resurrect's restore so the last snapshot is loaded
# before the operator opens Terminal.app and runs `tmux attach`.
set -euo pipefail

# LaunchAgents inherit a minimal PATH; Homebrew tmux + git must be on it.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

TMUX_BIN=$(command -v tmux) || { echo "tmux not on PATH"; exit 0; }
RESTORE_SCRIPT="${HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

# Server already up: nothing to do — attach path handles the rest.
if "${TMUX_BIN}" list-sessions >/dev/null 2>&1; then
    exit 0
fi

# Start server via a throwaway session so tpm can source plugins.
"${TMUX_BIN}" new-session -d -s _bootstrap
# tpm sources plugins in a background run-shell; give it a moment before
# firing restore, otherwise resurrect's own script isn't on disk yet.
sleep 2

if [[ -x "${RESTORE_SCRIPT}" ]]; then
    "${TMUX_BIN}" run-shell "${RESTORE_SCRIPT}"
    sleep 1
fi

# Drop the bootstrap session if resurrect brought real sessions back.
if [[ $("${TMUX_BIN}" list-sessions 2>/dev/null | wc -l) -gt 1 ]]; then
    "${TMUX_BIN}" kill-session -t _bootstrap 2>/dev/null || true
fi
