#!/bin/bash
# Called by tmux-resurrect via @resurrect-hook-post-restore-all after a
# snapshot restore. For every restored pane, look up the last-typed shell
# command recorded by dot_bashrc / dot_zshrc and send it to the pane
# without pressing Enter. Operator hits Enter to run.
#
# State layout (written by PROMPT_COMMAND / precmd_functions):
#   $XDG_STATE_HOME/tmux/panes/<session>:<window_index>.<pane_index>.last
#
# Skipped: text containing any terminal-control byte (multi-line
# heredocs / pasted blocks, CR, Tab, ESC, DEL, Ctrl+O, NUL) — Readline
# and ZLE act on those even when typed literally (LF, CR and Ctrl+O
# accept the line), so the command could run without Enter. Skipped:
# non-shell panes (vim, less, watch) — they get restored by
# resurrect-processes / capture-pane-contents.
set -euo pipefail

# True when $1 holds a C0 control byte (0x01-0x1f) or DEL. Byte-wise
# (C locale) so multibyte UTF-8 text is not misread.
has_control_bytes() {
    local LC_ALL=C
    [[ "$1" == *[$'\001'-$'\037'$'\177']* ]]
}

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

    # Refuse NUL: `$(<file)` would silently drop it and type a different
    # command than the one recorded.
    [[ $(tr -cd '\000' <"${file}" | wc -c) -eq 0 ]] || continue

    # $(<...) strips the recorder's trailing line separator; any control
    # byte left (embedded newline included) refuses the whole command.
    last=$(<"${file}")
    has_control_bytes "${last}" && continue
    # Skip empty / whitespace-only.
    [[ -n "${last//[[:space:]]/}" ]] || continue

    # `-l`: type the text literally, so a recorded `Enter` or `C-m` is
    # not looked up as a key name.
    # `|| true`: keep iterating when a pane closed between list-panes
    # and send-keys (realistic race during a restore). Without it,
    # `set -euo pipefail` + subshell would abort remaining panes.
    tmux send-keys -l -t "${sess}:${win}.${pane}" -- "${last}" || true
done
