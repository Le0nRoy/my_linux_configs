#!/bin/bash
# X Screen Manager - automatic display configuration with xrandr
# Handles screen connections/disconnections and saves/restores configurations
# Supports multiple named configurations with descriptions

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

CONFIG_DIR="${HOME}/.config/xrandr-manager"
CONFIGS_DIR="${CONFIG_DIR}/configs"
STATE_FILE="${CONFIG_DIR}/current_state"
DEFAULT_CONFIG_FILE="${CONFIG_DIR}/default_config"
DEFAULT_PRIMARY="DP-2"

# Ensure directories exist
mkdir -p "${CONFIG_DIR}" "${CONFIGS_DIR}"

# =============================================================================
# Utility Functions - Parsing xrandr output
# =============================================================================

# Get list of all connected outputs
get_connected_outputs() {
    xrandr --query | awk '/^[^ ]+ connected/ {print $1}'
}

# Get list of all disconnected outputs
get_disconnected_outputs() {
    xrandr --query | awk '/^[^ ]+ disconnected/ {print $1}'
}

# Get current primary output
get_primary_output() {
    xrandr --query | awk '/^[^ ]+ connected primary/ {print $1; exit}'
}

# Get mode (resolution) for an output from xrandr line
extract_mode() {
    local output="${1}"
    xrandr --query | awk -v out="${output}" '
        $0 ~ "^"out" connected" {found=1; next}
        found && /^[^ ]/ {exit}
        found && /\*/ {print $1; exit}
    '
}

# Get position string (WxH+X+Y) for an output
extract_position() {
    local output="${1}"
    xrandr --query | grep "^${output} connected" | grep -oP '\d+x\d+\+\d+\+\d+' | head -1
}

# Get display dimensions (width and height) from position string
get_display_dimensions() {
    local position="${1}"
    if [[ "${position}" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    fi
}

# Get display offset (X and Y) from position string
get_display_offset() {
    local position="${1}"
    if [[ "${position}" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
    fi
}

# Check if output is primary
is_primary_output() {
    local output="${1}"
    xrandr --query | grep "^${output} connected primary" &>/dev/null
}

# Check if output is enabled (has a mode set)
is_output_enabled() {
    local output="${1}"
    local position
    position="$(extract_position "${output}")"
    [[ -n "${position}" ]]
}

# =============================================================================
# Configuration Management - Multiple Named Configs
# =============================================================================

# List all saved configurations
list_configs() {
    local -a configs=()
    if [[ -d "${CONFIGS_DIR}" ]]; then
        while IFS= read -r config_file; do
            [[ -f "${config_file}" ]] || continue
            local name
            name="$(basename "${config_file}" .conf)"
            local description
            description="$(grep "^# Description:" "${config_file}" 2>/dev/null | sed 's/^# Description: //' || echo "No description")"
            configs+=("${name}|${description}")
        done < <(find "${CONFIGS_DIR}" -name "*.conf" -type f | sort)
    fi
    printf '%s\n' "${configs[@]}"
}

# Get default configuration name
get_default_config() {
    if [[ -f "${DEFAULT_CONFIG_FILE}" ]]; then
        cat "${DEFAULT_CONFIG_FILE}"
    fi
}

# Set default configuration
set_default_config() {
    local name="${1}"
    echo "${name}" > "${DEFAULT_CONFIG_FILE}"
}

# Generate visual description of display layout
generate_layout_description() {
    local -a displays=()

    while IFS= read -r output; do
        local position
        position="$(extract_position "${output}")"
        if [[ -n "${position}" ]]; then
            local dims offsets
            read -r width height <<< "$(get_display_dimensions "${position}")"
            read -r x_off y_off <<< "$(get_display_offset "${position}")"
            local primary_mark=""
            is_primary_output "${output}" && primary_mark="*"
            displays+=("${output}${primary_mark}@${x_off},${y_off}")
        fi
    done < <(get_connected_outputs)

    # Sort by X position and format
    printf '%s\n' "${displays[@]}" | sort -t@ -k2 -n | tr '\n' ' '
    echo ""
}

# Save configuration with name and description
save_config() {
    local name="${1}"
    local description="${2:-}"
    local config_file="${CONFIGS_DIR}/${name}.conf"

    {
        echo "# Xrandr configuration: ${name}"
        echo "# Description: ${description}"
        echo "# Saved: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Layout: $(generate_layout_description)"
        echo "# Format: OUTPUT|MODE|POSITION|PRIMARY|ENABLED"
        echo ""

        while IFS= read -r output; do
            save_output_config "${output}"
        done < <(get_connected_outputs)

        # Also save disconnected outputs as disabled
        while IFS= read -r output; do
            echo "${output}|auto|0x0+0+0|no|no"
        done < <(get_disconnected_outputs)
    } > "${config_file}"

    echo "Configuration '${name}' saved to ${config_file}"
}

# Save single output configuration line
save_output_config() {
    local output="${1}"
    local mode position primary="no" enabled="yes"

    mode="$(extract_mode "${output}")"
    position="$(extract_position "${output}")"
    is_primary_output "${output}" && primary="yes"

    if [[ -z "${position}" ]]; then
        enabled="no"
        position="0x0+0+0"
        mode="${mode:-auto}"
    fi

    echo "${output}|${mode:-auto}|${position}|${primary}|${enabled}"
}

# Load configuration by name
load_config() {
    local name="${1}"
    local config_file="${CONFIGS_DIR}/${name}.conf"

    if [[ ! -f "${config_file}" ]]; then
        echo "Configuration '${name}' not found" >&2
        return 1
    fi

    apply_config_file "${config_file}"
}

# Delete configuration by name
delete_config() {
    local name="${1}"
    local config_file="${CONFIGS_DIR}/${name}.conf"

    if [[ -f "${config_file}" ]]; then
        rm "${config_file}"
        echo "Configuration '${name}' deleted"

        # Clear default if it was this config
        if [[ "$(get_default_config)" == "${name}" ]]; then
            rm -f "${DEFAULT_CONFIG_FILE}"
        fi
    else
        echo "Configuration '${name}' not found" >&2
        return 1
    fi
}

# =============================================================================
# Configuration Application
# =============================================================================

# Apply configuration from file
apply_config_file() {
    local config_file="${1}"
    local -a xrandr_args=()
    local connected_outputs
    connected_outputs="$(get_connected_outputs)"

    while IFS='|' read -r output mode position primary enabled; do
        [[ "${output}" =~ ^# ]] && continue
        [[ -z "${output}" ]] && continue

        build_output_args xrandr_args "${output}" "${mode}" "${position}" "${primary}" "${enabled}" "${connected_outputs}"
    done < "${config_file}"

    execute_xrandr_command "${xrandr_args[@]}"
}

# Build xrandr arguments for a single output
build_output_args() {
    local -n args_ref="${1}"
    local output="${2}" mode="${3}" position="${4}" primary="${5}" enabled="${6}" connected="${7}"

    if echo "${connected}" | grep -q "^${output}$"; then
        if [[ "${enabled}" == "yes" ]]; then
            args_ref+=("--output" "${output}")
            add_mode_args args_ref "${mode}"
            add_position_args args_ref "${position}"
            [[ "${primary}" == "yes" ]] && args_ref+=("--primary")
        else
            args_ref+=("--output" "${output}" "--off")
        fi
    else
        args_ref+=("--output" "${output}" "--off")
    fi
}

# Add mode arguments to xrandr command
add_mode_args() {
    local -n args_ref="${1}"
    local mode="${2}"

    if [[ "${mode}" != "auto" && -n "${mode}" ]]; then
        args_ref+=("--mode" "${mode}")
    else
        args_ref+=("--auto")
    fi
}

# Add position arguments to xrandr command
add_position_args() {
    local -n args_ref="${1}"
    local position="${2}"

    if [[ "${position}" =~ \+([0-9]+)\+([0-9]+)$ ]]; then
        args_ref+=("--pos" "${BASH_REMATCH[1]}x${BASH_REMATCH[2]}")
    fi
}

# Execute xrandr command
execute_xrandr_command() {
    local -a args=("$@")

    if [[ ${#args[@]} -gt 0 ]]; then
        echo "Executing: xrandr ${args[*]}"
        xrandr "${args[@]}"
    fi
}

# =============================================================================
# Display Geometry - Gap Removal and Alignment
# =============================================================================

# Calculate middle axis (center Y position) of a display
calculate_middle_axis() {
    local position="${1}"
    local height y_offset
    read -r _ height <<< "$(get_display_dimensions "${position}")"
    read -r _ y_offset <<< "$(get_display_offset "${position}")"
    echo $(( y_offset + height / 2 ))
}

# Find displays sorted by X position (left to right)
get_displays_left_to_right() {
    local -a display_data=()

    while IFS= read -r output; do
        local position
        position="$(extract_position "${output}")"
        [[ -z "${position}" ]] && continue

        local x_offset
        read -r x_offset _ <<< "$(get_display_offset "${position}")"
        display_data+=("${x_offset}|${output}|${position}")
    done < <(get_connected_outputs)

    printf '%s\n' "${display_data[@]}" | sort -t'|' -k1 -n
}

# Find next display clockwise from current primary
find_next_clockwise() {
    local current_primary="${1}"
    local -a sorted_displays=()

    while IFS='|' read -r _ output _; do
        sorted_displays+=("${output}")
    done < <(get_displays_left_to_right)

    local count="${#sorted_displays[@]}"
    [[ "${count}" -eq 0 ]] && return 1

    # Find current position and return next
    for i in "${!sorted_displays[@]}"; do
        if [[ "${sorted_displays[${i}]}" == "${current_primary}" ]]; then
            local next_idx=$(( (i + 1) % count ))
            echo "${sorted_displays[${next_idx}]}"
            return 0
        fi
    done

    # Current not found, return first
    echo "${sorted_displays[0]}"
}

# Remove gaps between displays and align middle axes
rearrange_displays() {
    local -a display_info=()
    local target_middle_axis=0
    local total_displays=0

    # Collect display info and calculate average middle axis
    while IFS='|' read -r x_pos output position; do
        [[ -z "${output}" ]] && continue
        local middle
        middle="$(calculate_middle_axis "${position}")"
        target_middle_axis=$(( target_middle_axis + middle ))
        total_displays=$(( total_displays + 1 ))
        display_info+=("${output}|${position}")
    done < <(get_displays_left_to_right)

    [[ "${total_displays}" -eq 0 ]] && return

    target_middle_axis=$(( target_middle_axis / total_displays ))

    # Build xrandr command with adjusted positions
    local -a xrandr_args=()
    local current_x=0

    for info in "${display_info[@]}"; do
        IFS='|' read -r output position <<< "${info}"
        local width height
        read -r width height <<< "$(get_display_dimensions "${position}")"

        # Calculate Y to align middle axis
        local new_y=$(( target_middle_axis - height / 2 ))
        [[ "${new_y}" -lt 0 ]] && new_y=0

        xrandr_args+=("--output" "${output}" "--pos" "${current_x}x${new_y}")
        current_x=$(( current_x + width ))
    done

    execute_xrandr_command "${xrandr_args[@]}"
}

# =============================================================================
# Auto-Configuration and Event Handling
# =============================================================================

# Get current state hash (sorted connected outputs)
get_current_state() {
    get_connected_outputs | sort | tr '\n' ','
}

# Save current state to file
save_state() {
    get_current_state > "${STATE_FILE}"
}

# Load previous state from file
load_previous_state() {
    [[ -f "${STATE_FILE}" ]] && cat "${STATE_FILE}"
}

# Handle display disconnection
handle_disconnection() {
    local disconnected_output="${1}"
    local current_primary
    current_primary="$(get_primary_output)"

    echo "Output ${disconnected_output} disconnected"
    xrandr --output "${disconnected_output}" --off

    # If disconnected was primary, select new primary
    if [[ "${disconnected_output}" == "${current_primary}" ]]; then
        select_new_primary "${disconnected_output}"
    fi
}

# Select new primary display after disconnection
select_new_primary() {
    local old_primary="${1}"
    local connected
    connected="$(get_connected_outputs)"

    # Try default primary first
    if echo "${connected}" | grep -q "^${DEFAULT_PRIMARY}$"; then
        echo "Setting ${DEFAULT_PRIMARY} as primary"
        xrandr --output "${DEFAULT_PRIMARY}" --primary
        return
    fi

    # Otherwise, find next clockwise
    local next_primary
    next_primary="$(find_next_clockwise "${old_primary}")"

    if [[ -n "${next_primary}" ]]; then
        echo "Setting ${next_primary} as primary (next clockwise)"
        xrandr --output "${next_primary}" --primary
    fi
}

# Handle display connection
handle_connection() {
    local connected_output="${1}"
    echo "Output ${connected_output} connected"

    # Try to apply default configuration if set
    local default_config
    default_config="$(get_default_config)"

    if [[ -n "${default_config}" ]] && [[ -f "${CONFIGS_DIR}/${default_config}.conf" ]]; then
        echo "Applying default configuration: ${default_config}"
        load_config "${default_config}"
    else
        # Auto-enable with best mode
        xrandr --output "${connected_output}" --auto
    fi
}

# Auto-configure based on state changes
auto_configure() {
    local previous_state current_state
    previous_state="$(load_previous_state)"
    current_state="$(get_current_state)"

    [[ "${current_state}" == "${previous_state}" ]] && return

    echo "Display configuration changed"

    # Find disconnected outputs
    detect_disconnections "${previous_state}" "${current_state}"

    # Find newly connected outputs
    detect_connections "${previous_state}" "${current_state}"

    # Rearrange to remove gaps
    rearrange_displays

    # Save new state
    save_state
}

# Detect and handle disconnections
detect_disconnections() {
    local previous="${1}" current="${2}"

    for prev_output in ${previous//,/ }; do
        [[ -z "${prev_output}" ]] && continue
        if ! echo ",${current}" | grep -q ",${prev_output},"; then
            handle_disconnection "${prev_output}"
        fi
    done
}

# Detect and handle connections
detect_connections() {
    local previous="${1}" current="${2}"

    for curr_output in ${current//,/ }; do
        [[ -z "${curr_output}" ]] && continue
        if ! echo ",${previous}" | grep -q ",${curr_output},"; then
            handle_connection "${curr_output}"
        fi
    done
}

# =============================================================================
# Display Information
# =============================================================================

# List all outputs with their status
list_outputs() {
    echo "=== Connected Outputs ==="
    while IFS= read -r output; do
        format_output_info "${output}" "connected"
    done < <(get_connected_outputs)

    echo ""
    echo "=== Disconnected Outputs ==="
    local disconnected
    disconnected="$(get_disconnected_outputs)"

    if [[ -n "${disconnected}" ]]; then
        while IFS= read -r output; do
            echo "  ${output}: [DISCONNECTED]"
        done <<< "${disconnected}"
    else
        echo "  None"
    fi
}

# Format output information for display
format_output_info() {
    local output="${1}"
    local primary_mark=""
    local status_mark="[DISABLED]"

    is_primary_output "${output}" && primary_mark=" (PRIMARY)"

    local position
    position="$(extract_position "${output}")"
    [[ -n "${position}" ]] && status_mark="${position} [ENABLED]"

    echo "  ${output}${primary_mark}: ${status_mark}"
}

# =============================================================================
# dmenu Interface
# =============================================================================

# Main dmenu menu
dmenu_main_menu() {
    while true; do
        local choice
        choice="$(printf '%s\n' \
            "Load configuration" \
            "Save configuration" \
            "Per-display settings" \
            "Rearrange displays (remove gaps)" \
            "Open nvidia-settings" \
            "List outputs" \
            "Exit" \
            | dmenu -i -p "Screen Manager:")" || return

        case "${choice}" in
            "Load configuration")
                dmenu_load_config_menu
                ;;
            "Save configuration")
                dmenu_save_config_menu
                ;;
            "Per-display settings")
                dmenu_display_settings_menu
                ;;
            "Rearrange displays (remove gaps)")
                rearrange_displays
                ;;
            "Open nvidia-settings")
                nvidia-settings &
                ;;
            "List outputs")
                list_outputs | dmenu -l 20 -p "Outputs:"
                ;;
            "Exit"|"")
                return
                ;;
        esac
    done
}

# Load configuration submenu
dmenu_load_config_menu() {
    local -a menu_items=()
    local default_config
    default_config="$(get_default_config)"

    while IFS='|' read -r name description; do
        [[ -z "${name}" ]] && continue
        local default_mark=""
        [[ "${name}" == "${default_config}" ]] && default_mark=" [DEFAULT]"
        menu_items+=("${name}${default_mark} - ${description}")
    done < <(list_configs)

    menu_items+=("Back")

    local choice
    choice="$(printf '%s\n' "${menu_items[@]}" | dmenu -i -l 10 -p "Load config:")" || return

    [[ "${choice}" == "Back" || -z "${choice}" ]] && return

    # Extract config name (before " - " or " [DEFAULT]")
    local config_name
    config_name="$(echo "${choice}" | sed 's/ \[DEFAULT\]//' | sed 's/ - .*//')"

    if [[ -n "${config_name}" ]]; then
        load_config "${config_name}"
    fi
}

# Save configuration submenu
dmenu_save_config_menu() {
    local name description

    # Get configuration name
    name="$(echo "" | dmenu -p "Config name:")" || return
    [[ -z "${name}" ]] && return

    # Sanitize name (remove special characters)
    name="$(echo "${name}" | tr -cd 'a-zA-Z0-9_-')"

    # Get description
    description="$(echo "" | dmenu -p "Description (optional):")" || description=""

    # Ask if this should be default
    local make_default
    make_default="$(printf '%s\n' "Yes" "No" | dmenu -i -p "Set as default?")" || make_default="No"

    save_config "${name}" "${description}"

    if [[ "${make_default}" == "Yes" ]]; then
        set_default_config "${name}"
        echo "Set '${name}' as default configuration"
    fi
}

# Per-display settings submenu
dmenu_display_settings_menu() {
    while true; do
        local -a outputs=()
        while IFS= read -r output; do
            local status="[ENABLED]"
            is_output_enabled "${output}" || status="[DISABLED]"
            local primary=""
            is_primary_output "${output}" && primary=" (PRIMARY)"
            outputs+=("${output}${primary} ${status}")
        done < <(get_connected_outputs)

        outputs+=("Back")

        local choice
        choice="$(printf '%s\n' "${outputs[@]}" | dmenu -i -p "Select display:")" || return

        [[ "${choice}" == "Back" || -z "${choice}" ]] && return

        # Extract output name
        local selected_output
        selected_output="$(echo "${choice}" | awk '{print $1}')"

        dmenu_single_display_menu "${selected_output}"
    done
}

# Single display settings menu
dmenu_single_display_menu() {
    local output="${1}"

    while true; do
        local choice
        choice="$(printf '%s\n' \
            "Enable (auto mode)" \
            "Disable" \
            "Set as primary" \
            "Back" \
            | dmenu -i -p "${output}:")" || return

        case "${choice}" in
            "Enable (auto mode)")
                xrandr --output "${output}" --auto
                ;;
            "Disable")
                xrandr --output "${output}" --off
                ;;
            "Set as primary")
                xrandr --output "${output}" --primary
                ;;
            "Back"|"")
                return
                ;;
        esac
    done
}

# =============================================================================
# Main Command Handler
# =============================================================================

show_usage() {
    cat <<EOF
Usage: ${0##*/} <command> [options]

Commands:
    save <name> [description]   Save current configuration with name
    load <name>                 Load and apply saved configuration
    delete <name>               Delete saved configuration
    list-configs                List all saved configurations
    set-default <name>          Set default configuration
    auto                        Auto-configure (handle connections/disconnections)
    rearrange                   Remove gaps and align displays
    list                        List all outputs and their status
    dmenu                       Show dmenu interface for screen management
    monitor                     Continuously monitor for display changes

Configuration directory: ${CONFIG_DIR}
EOF
}

main() {
    local command="${1:-}"

    case "${command}" in
        save)
            save_config "${2:-unnamed}" "${3:-}"
            ;;
        load)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 load <name>" >&2; exit 1; }
            load_config "${2}"
            ;;
        delete)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 delete <name>" >&2; exit 1; }
            delete_config "${2}"
            ;;
        list-configs)
            echo "Saved configurations:"
            list_configs | while IFS='|' read -r name desc; do
                local default_mark=""
                [[ "$(get_default_config)" == "${name}" ]] && default_mark=" [DEFAULT]"
                echo "  ${name}${default_mark}: ${desc}"
            done
            ;;
        set-default)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 set-default <name>" >&2; exit 1; }
            set_default_config "${2}"
            echo "Default configuration set to '${2}'"
            ;;
        auto)
            auto_configure
            ;;
        rearrange)
            rearrange_displays
            ;;
        list)
            list_outputs
            ;;
        dmenu)
            dmenu_main_menu
            ;;
        monitor)
            echo "Monitoring display changes (press Ctrl+C to stop)..."
            save_state
            while true; do
                auto_configure
                sleep 2
            done
            ;;
        *)
            show_usage
            [[ -n "${command}" ]] && exit 1
            ;;
    esac
}

main "$@"
