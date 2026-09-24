#!/bin/bash
# Called by tmux-resurrect via @resurrect-hook-post-restore-all after a
# snapshot restore. For every restored pane, look up the last-typed shell
# command recorded by dot_bashrc / dot_zshrc and send it to the pane
# without pressing Enter. Operator hits Enter to run.
#
# State layout (written by PROMPT_COMMAND / precmd_functions):
#   $XDG_STATE_HOME/tmux/panes/<session>:<window_index>.<pane_index>.last
#
# Skipped: multi-line commands (heredocs / pasted blocks) — send-keys
# would fire them mid-way. Skipped: non-shell panes (vim, less, watch)
# — they get restored by resurrect-processes / capture-pane-contents.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
[[ -d "${STATE_DIR}" ]] || exit 0

# Format: session_name<TAB>window_index<TAB>pane_index<TAB>pane_current_command
tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_current_command}' \
| while IFS=$'\t' read -r sess win pane cmd; do
    # Only pre-fill into interactive shells; other foreground programs
    # would receive send-keys as raw input.
    case "${cmd}" in
        bash|zsh|sh|fish) ;;
        *) continue ;;
    esac

    file="${STATE_DIR}/${sess}:${win}.${pane}.last"
    [[ -f "${file}" ]] || continue

    # Refuse multi-line: fires prematurely on the first newline.
    if [[ $(wc -l <"${file}") -gt 1 ]]; then
        continue
    fi

    last=$(<"${file}")
    # Skip empty / whitespace-only.
    [[ -n "${last// /}" ]] || continue

    tmux send-keys -t "${sess}:${win}.${pane}" -- "${last}"
done
