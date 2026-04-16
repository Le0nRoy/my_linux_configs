#!/bin/bash
# Helper Firefox Module - Profile management and launch functions
# Used by: helper.bash (firefox case) and firefox_rofi.bash

FIREFOX_CMD="${FIREFOX_CMD:-/usr/bin/firefox}"

# Find profiles.ini across standard installation locations
function _ff_find_profiles_ini() {
    local candidates=(
        "${HOME}/.cache/mozilla/firefox/profiles.ini"
        "${HOME}/.mozilla/firefox/profiles.ini"
        "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini"
    )
    for f in "${candidates[@]}"; do
        [[ -f "${f}" ]] && { echo "${f}"; return; }
    done
    echo ""
}

# Parse profiles.ini and emit one line per [ProfileN] section: "path|name|is_default"
function _ff_parse_profiles_ini() {
    local ini_file="${1}"
    local in_profile=0 name="" path="" is_default="0"

    __emit() { [[ -n "${path}" ]] && printf '%s|%s|%s\n' "${path}" "${name}" "${is_default}"; }

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        if [[ "${line}" =~ ^\[Profile[0-9] ]]; then
            __emit; in_profile=1; name=""; path=""; is_default="0"
        elif [[ "${line}" =~ ^\[ ]]; then
            __emit; in_profile=0; name=""; path=""; is_default="0"
        elif [[ "${in_profile}" -eq 1 ]]; then
            case "${line}" in
                Name=*)    name="${line#Name=}" ;;
                Path=*)    path="${line#Path=}" ;;
                Default=1) is_default="1" ;;
            esac
        fi
    done < "${ini_file}"
    __emit
    unset -f __emit
}


# Launch Firefox with the right WM class:
#   - default profile → standard class (matches i3 firefox workspace rule)
#   - non-default     → --class job_navigator (excluded from that rule)
function _ff_launch() {
    local profile_path="${1}" is_default="${2}"
    shift 2
    if [[ "${is_default}" == "1" ]]; then
        "${FIREFOX_CMD}" --profile "${profile_path}" "$@" &
    else
        "${FIREFOX_CMD}" --class job_navigator --profile "${profile_path}" "$@" &
    fi
}

# Return 0 if the profile directory has a live, locally-owned Firefox lock.
# Handles stale locks (crashed Firefox) and remote locks (NFS home, other hosts).
function _ff_profile_is_open() {
    local profile_path="${1}"
    local lock="${profile_path}/lock"
    [[ -L "${lock}" ]] || return 1

    local lock_target
    lock_target="$(readlink "${lock}" 2>/dev/null)" || return 1

    # lock format: <ip>:+<pid>
    local lock_ip lock_pid
    lock_ip="${lock_target%%:*}"
    lock_pid="${lock_target##*+}"

    # Reject locks from other hosts — they appear when the home dir is on NFS
    local local_ips
    local_ips="$(hostname -I 2>/dev/null)"
    [[ " ${local_ips} " == *" ${lock_ip} "* ]] || return 1

    # Verify the process is still alive
    kill -0 "${lock_pid}" 2>/dev/null
}

# Launch Firefox in a firejail sandbox (private home, no real profile data)
# Passes an optional URL as first argument.
function _ff_launch_sandboxed() {
    if ! command -v firejail &>/dev/null; then
        notify-send --urgency=normal "Firefox" "firejail not found — install it first"
        return 1
    fi
    firejail --private "${FIREFOX_CMD}" --class sandboxed_browser "$@" &
}

# Show rofi profile picker and launch the selected profile.
#
# Display name precedence per profile:
#   1. Explicit entry in ~/bin/.firefox_profiles (path → label)
#   2. Default profile (Default=1 in profiles.ini) → "Personal"
#   3. Name= field from profiles.ini
#
# Profiles in ~/bin/.firefox_profiles whose path is not in profiles.ini
# are also shown, provided the directory exists on disk.
function _ff_profile_picker() {
    # Load user-managed name overrides (never overwritten by chezmoi)
    local -A FIREFOX_PROFILE_NAMES=()
    local profiles_file="${HOME}/bin/.firefox_profiles"
    if [[ -f "${profiles_file}" ]]; then
        # shellcheck source=/dev/null
        if ! source "${profiles_file}" 2>/dev/null; then
            notify-send --urgency=normal "Firefox" \
                "Error in ${profiles_file} — check variable names and paths"
        fi
    fi

    local -a display_names=() profile_paths=() profile_is_default=()
    local -A seen_paths=()

    local ini_file ini_dir
    ini_file="$(_ff_find_profiles_ini)"

    if [[ -n "${ini_file}" ]]; then
        ini_dir="${ini_file%/*}"
        while IFS='|' read -r path name is_default; do
            [[ "${path}" != /* ]] && path="${ini_dir}/${path}"

            local display
            if [[ -n "${FIREFOX_PROFILE_NAMES[${path}]:-}" ]]; then
                display="${FIREFOX_PROFILE_NAMES[${path}]} (${path##*/})"
            else
                display="${path}"
            fi

            _ff_profile_is_open "${path}" && display="> ${display}"
            display_names+=("${display}")
            profile_paths+=("${path}")
            profile_is_default+=("${is_default}")
            seen_paths["${path}"]=1
        done < <(_ff_parse_profiles_ini "${ini_file}")
    else
        # No profiles.ini found — scan known base directories directly.
        # A subdirectory is treated as a profile only if it contains prefs.js or places.sqlite.
        local -a _scan_bases=(
            "${HOME}/.cache/mozilla/firefox"
            "${HOME}/.mozilla/firefox"
        )
        for _base in "${_scan_bases[@]}"; do
            [[ -d "${_base}" ]] || continue
            while IFS= read -r -d '' _pdir; do
                [[ -f "${_pdir}/prefs.js" || -f "${_pdir}/places.sqlite" ]] || continue
                local _display
                if [[ -n "${FIREFOX_PROFILE_NAMES[${_pdir}]:-}" ]]; then
                    _display="${FIREFOX_PROFILE_NAMES[${_pdir}]} (${_pdir##*/})"
                else
                    _display="${_pdir}"
                fi
                _ff_profile_is_open "${_pdir}" && _display="> ${_display}"
                display_names+=("${_display}")
                profile_paths+=("${_pdir}")
                profile_is_default+=("0")
                seen_paths["${_pdir}"]=1
            done < <(find "${_base}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
        done
    fi

    # Add profiles from the mapping that are not in profiles.ini but exist on disk
    for extra_path in "${!FIREFOX_PROFILE_NAMES[@]}"; do
        [[ -n "${seen_paths[${extra_path}]:-}" ]] && continue
        [[ -d "${extra_path}" ]] || continue
        local extra_display="${FIREFOX_PROFILE_NAMES[${extra_path}]}"
        _ff_profile_is_open "${extra_path}" && extra_display="> ${extra_display}"
        extra_display="${extra_display} (${extra_path##*/})"
        display_names+=("${extra_display}")
        profile_paths+=("${extra_path}")
        profile_is_default+=("0")
    done

    if [[ "${#display_names[@]}" -eq 0 ]]; then
        notify-send --urgency=normal "Firefox" "No profiles found"
        return 1
    fi

    # Deduplicate: same name + same path → keep first occurrence, drop the rest
    local -a _final_display=() _final_paths=() _final_defaults=()
    local -A _seen_dup=()   # "name|path" → 1
    for i in "${!display_names[@]}"; do
        local _n="${display_names[$i]}" _p="${profile_paths[$i]}" _d="${profile_is_default[$i]}"
        local _key="${_n}|${_p}"
        [[ -n "${_seen_dup[${_key}]:-}" ]] && continue
        _seen_dup["${_key}"]=1
        _final_display+=("${_n}")
        _final_paths+=("${_p}")
        _final_defaults+=("${_d}")
    done
    display_names=("${_final_display[@]}")
    profile_paths=("${_final_paths[@]}")
    profile_is_default=("${_final_defaults[@]}")

    local -a menu_entries=("${display_names[@]}")
    command -v firejail &>/dev/null && menu_entries+=("⚠ Sandboxed (firejail)")

    local choice
    choice="$(printf '%s\n' "${menu_entries[@]}" | rofi -dmenu -i -p "Firefox profile:")" || return 0
    [[ -z "${choice}" ]] && return 0

    if [[ "${choice}" == "⚠ Sandboxed (firejail)" ]]; then
        _ff_launch_sandboxed
        return 0
    fi

    for i in "${!display_names[@]}"; do
        if [[ "${display_names[${i}]}" == "${choice}" ]]; then
            # Derive raw label (strip > prefix and (folder) suffix) for name-based class check
            local _raw_label="${display_names[${i}]#> }"
            _raw_label="${_raw_label% (*}"
            local _eff_default="${profile_is_default[${i}]}"
            [[ "${_raw_label}" == Work_* ]] && _eff_default="0"
            _ff_launch "${profile_paths[${i}]}" "${_eff_default}"
            return 0
        fi
    done
}

# Open a URL in an existing Firefox window chosen via rofi
function _ff_open_link() {
    local link="${1}"
    local -a WINDOWS CHOICES
    mapfile -t WINDOWS < <(wmctrl -lx | awk '/Navigator/ {print $1 " " substr($0, index($0,$5))}')

    CHOICES=()
    for window in "${WINDOWS[@]}"; do
        local WIN_ID TITLE
        WIN_ID=$(awk '{print $1}' <<<"${window}")
        TITLE=$(awk '{$1=""; print substr($0,2)}' <<<"${window}")
        CHOICES+=("${WIN_ID} ${TITLE}")
    done
    command -v firejail &>/dev/null && CHOICES+=("⚠ Sandboxed (firejail)")

    local SELECTION
    if [[ "${#CHOICES[@]}" -eq 1 ]]; then
        SELECTION="${CHOICES[0]}"
    else
        SELECTION=$(printf '%s\n' "${CHOICES[@]}" | rofi -dmenu -i -p "Open link with:")
    fi

    [[ -z "${SELECTION}" ]] && return 0

    if [[ "${SELECTION}" == "⚠ Sandboxed (firejail)" ]]; then
        _ff_launch_sandboxed "${link}"
        return 0
    fi

    local WIN_ID
    WIN_ID=$(awk '{print $1}' <<<"${SELECTION}")
    if [[ -n "${WIN_ID}" ]]; then
        # Clipboard paste is faster than xdotool type (~12 ms/char)
        local PREV_CLIP
        PREV_CLIP=$(xclip -selection clipboard -o 2>/dev/null || true)
        printf '%s' "${link}" | xclip -selection clipboard
        xdotool windowactivate --sync "${WIN_ID}"
        xdotool key --window "${WIN_ID}" ctrl+t
        sleep 0.1
        xdotool key --window "${WIN_ID}" ctrl+v
        xdotool key --window "${WIN_ID}" Return
        { sleep 1; printf '%s' "${PREV_CLIP}" | xclip -selection clipboard; } &
    fi
}
