#!/bin/bash
# asusctl rofi menu — interactive control for ASUS system settings
# Supports full back-navigation: any submenu returns to its parent on Escape or "Back"
# Dependencies: rofi, asusctl

set -euo pipefail

# =============================================================================
# Helpers
# =============================================================================

_rofi_menu() {
    local prompt="${1}"; shift
    local choice
    choice="$(printf '%s\n' "$@" | rofi -dmenu -i -p "${prompt}:")" || choice=""
    echo "${choice}"
}

_notify() {
    local msg="${1}"
    notify-send --urgency=low --expire-time=2500 "asusctl" "${msg}" 2>/dev/null || true
}

_current_profile() {
    asusctl profile get 2>/dev/null \
        | grep -oP '(?<=is )\S+' \
        || echo "unknown"
}

_list_profiles() {
    asusctl profile list 2>/dev/null \
        | grep -v -i 'available\|profiles\|^\s*$' \
        | awk '{print $1}'
}

_current_fan_preset() {
    asusctl fan-curve get-preset 2>/dev/null \
        | grep -oP '(?<=preset: )\S+' \
        || echo "unknown"
}

_battery_limit() {
    asusctl battery 2>/dev/null \
        | grep -oP '\d+(?=%)' | head -1 \
        || echo "unknown"
}

# =============================================================================
# Profile submenu
# =============================================================================

_menu_profile() {
    while true; do
        local current
        current="$(_current_profile)"

        local -a profiles=()
        while IFS= read -r p; do
            [[ -z "${p}" ]] && continue
            if [[ "${p}" == "${current}" ]]; then
                profiles+=("[active] ${p}")
            else
                profiles+=("${p}")
            fi
        done < <(_list_profiles)

        [[ ${#profiles[@]} -eq 0 ]] && profiles=("(no profiles found)")

        local choice
        choice="$(_rofi_menu "Profile (current: ${current})" "${profiles[@]}" "← Back")"

        case "${choice}" in
            "" | "← Back") return 0 ;;
            "(no profiles found)") return 0 ;;
            *)
                # Strip the "[active] " prefix if present
                local profile_name="${choice#\[active\] }"
                if asusctl profile set "${profile_name}" 2>/dev/null; then
                    _notify "Profile set to ${profile_name}"
                else
                    _notify "Failed to set profile ${profile_name}"
                fi
                ;;
        esac
    done
}

# =============================================================================
# Fan curve submenu
# =============================================================================

_menu_fan_curve() {
    while true; do
        local choice
        choice="$(_rofi_menu "Fan Curve" \
            "Next preset" \
            "Show current preset" \
            "← Back")"

        case "${choice}" in
            "" | "← Back") return 0 ;;
            "Next preset")
                if asusctl fan-curve set-preset next 2>/dev/null; then
                    _notify "Fan curve: switched to next preset"
                else
                    _notify "Fan curve: command failed"
                fi
                ;;
            "Show current preset")
                local preset
                preset="$(_current_fan_preset)"
                _notify "Fan curve preset: ${preset}"
                ;;
        esac
    done
}

# =============================================================================
# Battery submenu
# =============================================================================

_menu_battery() {
    while true; do
        local current_limit
        current_limit="$(_battery_limit)"

        local choice
        choice="$(_rofi_menu "Battery (charge limit: ${current_limit}%)" \
            "60% — storage / long plugged-in" \
            "80% — balanced" \
            "100% — full charge" \
            "← Back")"

        case "${choice}" in
            "" | "← Back") return 0 ;;
            "60%"*)
                asusctl battery --charge-control-end-threshold 60 2>/dev/null \
                    && _notify "Battery limit set to 60%" \
                    || _notify "Failed to set battery limit"
                ;;
            "80%"*)
                asusctl battery --charge-control-end-threshold 80 2>/dev/null \
                    && _notify "Battery limit set to 80%" \
                    || _notify "Failed to set battery limit"
                ;;
            "100%"*)
                asusctl battery --charge-control-end-threshold 100 2>/dev/null \
                    && _notify "Battery limit set to 100%" \
                    || _notify "Failed to set battery limit"
                ;;
        esac
    done
}

# =============================================================================
# Aura (keyboard LED) submenu
# =============================================================================

_menu_aura() {
    while true; do
        local choice
        choice="$(_rofi_menu "Keyboard LED (Aura)" \
            "Static" \
            "Breathe" \
            "Strobe" \
            "Rainbow" \
            "Star" \
            "Rain" \
            "Off" \
            "← Back")"

        case "${choice}" in
            "" | "← Back") return 0 ;;
            "Off")
                asusctl aura -e off 2>/dev/null \
                    && _notify "Aura LEDs off" \
                    || _notify "Aura command failed"
                ;;
            *)
                local mode
                mode="${choice,,}"  # lowercase
                asusctl aura -e "${mode}" 2>/dev/null \
                    && _notify "Aura mode: ${choice}" \
                    || _notify "Aura command failed"
                ;;
        esac
    done
}

# =============================================================================
# Main menu
# =============================================================================

_menu_main() {
    while true; do
        local current_profile
        current_profile="$(_current_profile)"

        local choice
        choice="$(_rofi_menu "asusctl  [profile: ${current_profile}]" \
            "Profile" \
            "Fan Curve" \
            "Battery" \
            "Aura (keyboard LED)" \
            "Exit")"

        case "${choice}" in
            "" | "Exit") return 0 ;;
            "Profile")        _menu_profile ;;
            "Fan Curve")      _menu_fan_curve ;;
            "Battery")        _menu_battery ;;
            "Aura (keyboard LED)") _menu_aura ;;
        esac
    done
}

_menu_main
