#!/bin/bash
# One-shot install of the OSC 52 pbcopy filter on every existing tmux pane.
# Hooks in tmux.conf cover new panes; this script covers the config-reload
# case where panes already exist. `pipe-pane -o` is a no-op if the pane is
# already piped, so re-running is safe.
set -euo pipefail

FILTER="${HOME}/bin/tmux_osc52_pbcopy.py"

[[ -x "${FILTER}" ]] || exit 0

tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' | while IFS= read -r target; do
    tmux pipe-pane -o -t "${target}" "${FILTER}"
done
