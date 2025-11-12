#!/bin/bash
# X Screen Manager - automatic display configuration with xrandr
# Handles screen connections/disconnections and saves/restores configurations

set -euo pipefail

# Configuration directory
CONFIG_DIR="${HOME}/.config/xrandr-manager"
STATE_FILE="${CONFIG_DIR}/current_state"
SAVED_CONFIG="${CONFIG_DIR}/saved_config"
DEFAULT_PRIMARY="DP-2"

# Ensure config directory exists
mkdir -p "${CONFIG_DIR}"

# Get list of all connected outputs
get_connected_outputs() {
    xrandr --query | awk '/^[^ ]+ connected/ {print $1}'
}

# Get list of all disconnected outputs that were previously connected
get_disconnected_outputs() {
    xrandr --query | awk '/^[^ ]+ disconnected/ {print $1}'
}

# Get current primary output
get_primary_output() {
    xrandr --query | awk '/^[^ ]+ connected primary/ {print $1; exit}'
}

# Save current xrandr configuration
save_configuration() {
    local config_file="${1:-${SAVED_CONFIG}}"

    echo "# Saved xrandr configuration - $(date)" > "${config_file}"
    echo "# Format: OUTPUT|MODE|POSITION|PRIMARY|ENABLED" >> "${config_file}"

    # Get all outputs (connected and disconnected)
    while IFS= read -r line; do
        local output
        output="$(echo "${line}" | awk '{print $1}')"

        if echo "${line}" | grep -q " connected"; then
            # Connected output
            local mode position primary="no" enabled="yes"

            # Check if primary
            if echo "${line}" | grep -q "primary"; then
                primary="yes"
            fi

            # Get mode and position
            mode="$(xrandr --query | grep -A1 "^${output} " | tail -1 | awk '{print $1}')"
            position="$(echo "${line}" | grep -oP '\d+x\d+\+\d+\+\d+' | head -1)"

            # If no position, get it from detailed info
            if [[ -z "${position}" ]]; then
                position="$(xrandr --query | awk -v out="${output}" '
                    $0 ~ "^"out" connected" {found=1; next}
                    found && /^[^ ]/ {exit}
                    found && /\*/ {
                        for(i=1; i<=NF; i++) {
                            if($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
                                print $i
                                exit
                            }
                        }
                    }
                ')"
            fi

            # If still no position, output is connected but disabled
            if [[ -z "${position}" ]]; then
                enabled="no"
                position="0x0+0+0"
                mode="auto"
            fi

            echo "${output}|${mode}|${position}|${primary}|${enabled}" >> "${config_file}"
        else
            # Disconnected output - save as disabled
            echo "${output}|auto|0x0+0+0|no|no" >> "${config_file}"
        fi
    done < <(xrandr --query | grep -E "^[^ ]+ (dis)?connected")

    echo "Configuration saved to ${config_file}"
}

# Load and apply saved configuration
load_configuration() {
    local config_file="${1:-${SAVED_CONFIG}}"

    if [[ ! -f "${config_file}" ]]; then
        echo "No saved configuration found at ${config_file}" >&2
        return 1
    fi

    local -a xrandr_args=()
    local connected_outputs
    connected_outputs="$(get_connected_outputs)"

    # Read configuration
    while IFS='|' read -r output mode position primary enabled; do
        # Skip comments
        [[ "${output}" =~ ^# ]] && continue

        # Check if output is currently connected
        if echo "${connected_outputs}" | grep -q "^${output}$"; then
            if [[ "${enabled}" == "yes" ]]; then
                xrandr_args+=("--output" "${output}")

                # Set mode
                if [[ "${mode}" != "auto" ]]; then
                    xrandr_args+=("--mode" "${mode}")
                else
                    xrandr_args+=("--auto")
                fi

                # Set position
                if [[ "${position}" =~ \+([0-9]+)\+([0-9]+)$ ]]; then
                    xrandr_args+=("--pos" "${BASH_REMATCH[1]}x${BASH_REMATCH[2]}")
                fi

                # Set primary
                if [[ "${primary}" == "yes" ]]; then
                    xrandr_args+=("--primary")
                fi
            else
                xrandr_args+=("--output" "${output}" "--off")
            fi
        else
            # Output not connected - disable it
            xrandr_args+=("--output" "${output}" "--off")
        fi
    done < <(grep -v '^#' "${config_file}")

    # Apply configuration
    if [[ ${#xrandr_args[@]} -gt 0 ]]; then
        echo "Applying configuration: xrandr ${xrandr_args[*]}"
        xrandr "${xrandr_args[@]}"
    fi
}

# Detect changes and auto-configure
auto_configure() {
    local current_primary
    current_primary="$(get_primary_output)"

    # Get current connected outputs
    local connected
    connected="$(get_connected_outputs | sort)"

    # Check if state has changed
    local saved_state=""
    if [[ -f "${STATE_FILE}" ]]; then
        saved_state="$(cat "${STATE_FILE}")"
    fi

    local current_state="${connected}"

    # If state changed, handle disconnections
    if [[ "${current_state}" != "${saved_state}" ]]; then
        echo "Display configuration changed"

        # Check if primary display was disconnected
        if [[ -n "${saved_state}" ]]; then
            # Get previously connected outputs
            local previously_connected="${saved_state}"

            # Find disconnected outputs
            while IFS= read -r prev_output; do
                if ! echo "${connected}" | grep -q "^${prev_output}$"; then
                    echo "Output ${prev_output} disconnected"

                    # Disable the output
                    xrandr --output "${prev_output}" --off

                    # If it was primary, set default as primary
                    if [[ "${prev_output}" == "${current_primary}" ]] || [[ -z "${current_primary}" ]]; then
                        if echo "${connected}" | grep -q "^${DEFAULT_PRIMARY}$"; then
                            echo "Setting ${DEFAULT_PRIMARY} as primary"
                            xrandr --output "${DEFAULT_PRIMARY}" --primary
                        else
                            # Set first connected output as primary
                            local first_output
                            first_output="$(echo "${connected}" | head -1)"
                            if [[ -n "${first_output}" ]]; then
                                echo "Setting ${first_output} as primary"
                                xrandr --output "${first_output}" --primary
                            fi
                        fi
                    fi
                fi
            done < <(echo "${previously_connected}")
        fi

        # Save new state
        echo "${current_state}" > "${STATE_FILE}"
    fi
}

# List all outputs with their status
list_outputs() {
    echo "=== Connected Outputs ==="
    while IFS= read -r line; do
        local output
        output="$(echo "${line}" | awk '{print $1}')"
        local is_primary=""

        if echo "${line}" | grep -q "primary"; then
            is_primary=" (PRIMARY)"
        fi

        # Get resolution
        local resolution
        resolution="$(echo "${line}" | grep -oP '\d+x\d+\+\d+\+\d+' | head -1)"

        if [[ -n "${resolution}" ]]; then
            echo "  ${output}${is_primary}: ${resolution} [ENABLED]"
        else
            echo "  ${output}${is_primary}: [DISABLED]"
        fi
    done < <(xrandr --query | grep " connected")

    echo ""
    echo "=== Disconnected Outputs ==="
    local disconnected
    disconnected="$(get_disconnected_outputs)"

    if [[ -n "${disconnected}" ]]; then
        echo "${disconnected}" | while IFS= read -r output; do
            echo "  ${output}: [DISCONNECTED]"
        done
    else
        echo "  None"
    fi
}

# Interactive dmenu interface
dmenu_interface() {
    # Get all connected outputs
    local -a outputs=()
    while IFS= read -r output; do
        outputs+=("${output}")
    done < <(get_connected_outputs)

    if [[ ${#outputs[@]} -eq 0 ]]; then
        echo "No outputs available" | dmenu -p "Error:"
        return 1
    fi

    # Main menu
    local choice
    choice="$(cat <<EOF | dmenu -i -p "Screen Manager:"
Auto-configure (restore saved)
Save current configuration
Enable output
Disable output
Set as primary
List outputs
EOF
)"

    case "${choice}" in
        "Auto-configure (restore saved)")
            load_configuration
            ;;
        "Save current configuration")
            save_configuration
            echo "Configuration saved" | dmenu -p "Info:"
            ;;
        "Enable output")
            # Select output to enable
            local output
            output="$(printf "%s\n" "${outputs[@]}" | dmenu -p "Enable output:")"

            if [[ -n "${output}" ]]; then
                xrandr --output "${output}" --auto
            fi
            ;;
        "Disable output")
            # Select output to disable
            local output
            output="$(printf "%s\n" "${outputs[@]}" | dmenu -p "Disable output:")"

            if [[ -n "${output}" ]]; then
                xrandr --output "${output}" --off
            fi
            ;;
        "Set as primary")
            # Select output to set as primary
            local output
            output="$(printf "%s\n" "${outputs[@]}" | dmenu -p "Set primary:")"

            if [[ -n "${output}" ]]; then
                xrandr --output "${output}" --primary
            fi
            ;;
        "List outputs")
            list_outputs | dmenu -l 20 -p "Outputs:"
            ;;
    esac
}

# Main command handler
main() {
    local command="${1:-}"

    case "${command}" in
        save)
            save_configuration "${2:-}"
            ;;
        load)
            load_configuration "${2:-}"
            ;;
        auto)
            auto_configure
            ;;
        list)
            list_outputs
            ;;
        dmenu)
            dmenu_interface
            ;;
        monitor)
            # Monitor mode - continuously check for changes
            echo "Monitoring display changes (press Ctrl+C to stop)..."
            while true; do
                auto_configure
                sleep 2
            done
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
    save [file]     Save current xrandr configuration
    load [file]     Load and apply saved configuration
    auto            Auto-configure (handle disconnections)
    list            List all outputs and their status
    dmenu           Show dmenu interface for screen management
    monitor         Continuously monitor for display changes

Default configuration file: ${SAVED_CONFIG}
EOF
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
