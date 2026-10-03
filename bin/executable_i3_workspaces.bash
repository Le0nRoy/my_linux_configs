#!/bin/bash
# Save / restore i3 workspace layouts across sessions.
# Called from i3 shutdown/reboot bindings (save) and i3 startup (restore).
# Uses i3-save-tree + append_layout (built-in). Placeholder windows are
# swallowed by real apps launched from i3 exec lines.

set -euo pipefail

STATE_DIR="${HOME}/.config/i3/workspaces/state-$(uname -n)"

# Titles are only needed to tell apart windows of the same class. A lone
# window's title (unread counters, timers, page names) changes between
# sessions and would block the swallow, so drop it for single-window classes.
drop_single_window_titles() {
    (( $# )) || return 0
    local single f tmp
    single=$(jq -cn '[inputs | .. | objects | .swallows? // empty | .[].class]
        | group_by(.) | map(select(length == 1)[0])' "$@") || return 0
    for f in "$@"; do
        tmp=$(mktemp)
        if jq --argjson single "${single}" 'walk(
                if type == "object" and has("swallows") then
                    .swallows |= map(if (.class as $c | any($single[]; . == $c)) then del(.title) else . end)
                else . end)' "${f}" > "${tmp}"; then
            mv "${tmp}" "${f}"
        else
            rm -f "${tmp}"
        fi
    done
}

save_all() {
    local ws safe tmp
    local -a saved=()
    while IFS= read -r ws; do
        [[ -z "${ws}" ]] && continue
        # Hex-encode workspace name for reversible filename key
        safe=$(printf '%s' "${ws}" | xxd -p | tr -d '\n')
        tmp=$(mktemp)
        i3-save-tree --workspace "${ws}" 2>/dev/null \
            | sed -e 's#^\(\s*\)// \?\("swallows"\|"instance"\|"class"\|"window_role"\|"title"\)#\1\2#' \
                  -e '/^\s*\/\//d' \
            > "${tmp}" || true
        if [[ -s "${tmp}" ]]; then
            mkdir -p "${STATE_DIR}"
            mv "${tmp}" "${STATE_DIR}/workspace_${safe}.json"
            saved+=("${STATE_DIR}/workspace_${safe}.json")
        else
            rm -f "${tmp}"
        fi
    done < <(i3-msg -t get_workspaces | jq -r '.[].name')
    drop_single_window_titles "${saved[@]}"
}

restore_all() {
    [[ -d "${STATE_DIR}" ]] || return 0
    local f hex_name ws
    for f in "${STATE_DIR}"/workspace_*.json; do
        [[ -f "${f}" ]] || continue
        hex_name=$(basename "${f}" .json | sed 's/^workspace_//')
        ws=$(printf '%s' "${hex_name}" | xxd -r -p)
        i3-msg "workspace ${ws}; append_layout ${f}" &>/dev/null || true
    done
    i3-msg 'workspace 1' &>/dev/null || true
}

case "${1:-}" in
    save)    save_all ;;
    restore) restore_all ;;
    *) echo "Usage: ${0##*/} save|restore" >&2; exit 1 ;;
esac
