#!/bin/bash
# Helper i3 Module - i3 window manager utilities
# Dependencies: i3-save-tree, i3-msg, jq
#
# Workspace files use the naming convention: workspace_<num>-<hostname>.json
# in both the live dir and the chezmoi repo, matching the i3 config.tmpl.

# Resolve hostname; fails loudly if empty so no file is written without a hostname
_i3_get_host() {
    local host
    host="$(_i3_get_host)" || return 1
    if [[ -z "${host}" ]]; then
        echo "Error: could not determine hostname (uname -n returned empty)" >&2
        return 1
    fi
    echo "${host}"
}

# Validate workspace number (1-9)
_i3_check_ws_num() {
    if [[ -z "${1}" || ! "${1}" =~ ^[1-9]$ ]]; then
        echo "Error: workspace number must be 1-9, got '${1}'" >&2
        return 1
    fi
}

# Apply standard cleanup to raw i3-save-tree output (stdin → stdout)
_i3_clean_layout() {
    sed --regexp-extended \
        --expression='s|^(\s*)// "|\1"|g' \
        --expression='/^\s*\/\//d' \
        --expression='/"machine":/d' \
        --expression='s/("name": "\[.*\]).*$/\1",/' \
        --expression='s/("title": ".*\[.*\]).*$/\1",/' \
        --expression='s/("name": "Telegram).*$/\1",/' \
        --expression='s/("title": "\^Telegram).*"(,*)$/\1"\2/'
}

# Save all active i3 workspaces to both the live config dir and the chezmoi repo.
# Files in both locations: workspace_<num>-<host>.json
#
# Usage: i3_save_chezmoi_ws
i3_save_chezmoi_ws() {
    if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
        echo "Usage: i3_save_chezmoi_ws"
        echo ""
        echo "Save all active i3 workspaces to both the live config dir and the chezmoi repo."
        echo ""
        echo "Output files (same name in both locations):"
        echo "  ~/.config/i3/workspaces/workspace_<num>-<host>.json                          (live)"
        echo "  ~/.local/share/chezmoi/dot_config/i3/workspaces/workspace_<num>-<host>.json  (repo)"
        echo ""
        echo "Empty workspaces (no open windows) are skipped."
        return 0
    fi

    local home_ws_dir="${HOME}/.config/i3/workspaces"
    local chezmoi_ws_dir="${HOME}/.local/share/chezmoi/dot_config/i3/workspaces"
    local host
    host="$(_i3_get_host)" || return 1

    for cmd in i3-save-tree i3-msg jq; do
        if ! command -v "${cmd}" &>/dev/null; then
            echo "Error: ${cmd} not found" >&2
            return 1
        fi
    done

    mkdir -p "${home_ws_dir}" "${chezmoi_ws_dir}"

    local ws_nums
    mapfile -t ws_nums < <(i3-msg -t get_workspaces | jq '[.[].num] | sort | unique[]')

    if [[ ${#ws_nums[@]} -eq 0 ]]; then
        echo "No active workspaces found." >&2
        return 1
    fi

    local saved=0
    local ws_num
    for ws_num in "${ws_nums[@]}"; do
        local raw
        raw="$(i3-save-tree --workspace "${ws_num}" 2>/dev/null)"
        if [[ -z "${raw}" ]]; then
            echo "  Workspace ${ws_num}: empty (no windows), skipping"
            continue
        fi

        local cleaned
        cleaned="$(echo "${raw}" | _i3_clean_layout)"

        local filename="workspace_${ws_num}-${host}.json"
        echo "${cleaned}" > "${home_ws_dir}/${filename}"
        echo "${cleaned}" > "${chezmoi_ws_dir}/${filename}"

        echo "  Saved workspace ${ws_num} -> ${filename}"
        (( saved++ )) || true
    done

    echo "Done. ${saved} workspace(s) saved for host '${host}'."
    echo "You may want to review and fix the saved files."
}

# Save a single i3 workspace to both the live config dir and the chezmoi repo.
# Usage: i3_save_ws <ws_num>
i3_save_ws() {
    if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
        echo "Usage: i3_save_ws <ws_num>"
        echo ""
        echo "Save a single i3 workspace to both the live config dir and the chezmoi repo."
        echo ""
        echo "Arguments:"
        echo "  ws_num  Workspace number to save (1-9)"
        echo ""
        echo "Output files (same name in both locations):"
        echo "  ~/.config/i3/workspaces/workspace_<num>-<host>.json                          (live)"
        echo "  ~/.local/share/chezmoi/dot_config/i3/workspaces/workspace_<num>-<host>.json  (repo)"
        return 0
    fi

    local ws_num="${1}"
    _i3_check_ws_num "${ws_num}" || return 1

    local home_ws_dir="${HOME}/.config/i3/workspaces"
    local chezmoi_ws_dir="${HOME}/.local/share/chezmoi/dot_config/i3/workspaces"
    local host
    host="$(_i3_get_host)" || return 1

    mkdir -p "${home_ws_dir}" "${chezmoi_ws_dir}"

    local raw
    raw="$(i3-save-tree --workspace "${ws_num}" 2>/dev/null)"
    if [[ -z "${raw}" ]]; then
        echo "Workspace ${ws_num}: empty (no windows)" >&2
        return 1
    fi

    local cleaned
    cleaned="$(echo "${raw}" | _i3_clean_layout)"

    local filename="workspace_${ws_num}-${host}.json"
    echo "${cleaned}" > "${home_ws_dir}/${filename}"
    echo "${cleaned}" > "${chezmoi_ws_dir}/${filename}"

    echo "Saved workspace ${ws_num} to:"
    echo "  ${home_ws_dir}/${filename}"
    echo "  ${chezmoi_ws_dir}/${filename}"
    echo "You may want to review and fix the saved file."
}

# Restore i3 workspace layout from a saved file.
# Usage: i3_restore_ws <src_ws_num> [target_ws_num]
#   src_ws_num    - workspace number whose saved file to load
#   target_ws_num - workspace to restore into (defaults to src_ws_num)
i3_restore_ws() {
    if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
        echo "Usage: i3_restore_ws <src_ws_num> [target_ws_num]"
        echo ""
        echo "Restore an i3 workspace layout from a saved file."
        echo ""
        echo "Arguments:"
        echo "  src_ws_num     Workspace number whose saved file to load (1-9)"
        echo "  target_ws_num  Workspace to restore into (default: same as src_ws_num)"
        echo ""
        echo "Reads from: ~/.config/i3/workspaces/workspace_<src_ws_num>-<host>.json"
        return 0
    fi

    local src_num="${1}"
    local target_num="${2:-${src_num}}"
    _i3_check_ws_num "${src_num}" || return 1
    _i3_check_ws_num "${target_num}" || return 1

    local host
    host="$(_i3_get_host)" || return 1
    local ws_path="${HOME}/.config/i3/workspaces/workspace_${src_num}-${host}.json"
    if [[ ! -f "${ws_path}" ]]; then
        echo "Error: ${ws_path} not found" >&2
        return 1
    fi

    i3-msg "workspace ${target_num}; append_layout ${ws_path}"
    echo "Restored layout from workspace ${src_num} into workspace ${target_num}"
}
