#!/bin/bash
# Polybar script to display volume for all audio sinks with sink selection
# Shows: Jack: 50% | HDMI-1: muted | HDMI-2: 100% | BT-1: 20%
# Chosen sink is highlighted (like focused i3 workspace)

# State file to track chosen sink
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/polybar_volume_chosen_sink"

# Color codes for polybar (matching backlight style)
COLOR_PREFIX="#FFF700"            # Yellow for "Light:" and sink names (like backlight prefix)
COLOR_VALUE="#C5C8C6"             # Normal text for values
COLOR_MUTED="#707880"             # Muted sink (gray)
COLOR_CHOSEN_FG="#000000"         # Chosen sink foreground (black)
COLOR_CHOSEN_BG="#BD5E02"         # Chosen sink background (orange, like focused workspace)

# Get or initialize chosen sink
get_chosen_sink() {
    if [[ -f "${STATE_FILE}" ]]; then
        cat "${STATE_FILE}"
    else
        # Default: choose first available sink
        local first_sink
        first_sink="$(pactl list sinks short | head -1 | awk '{print $2}')"
        if [[ -n "${first_sink}" ]]; then
            echo "${first_sink}" > "${STATE_FILE}"
            echo "${first_sink}"
        fi
    fi
}

# Set chosen sink
set_chosen_sink() {
    local sink="${1}"
    echo "${sink}" > "${STATE_FILE}"
}

# Get next sink in the list (cycle through)
get_next_sink() {
    local current_sink="${1}"
    local -a sinks=()

    # Get all sink names
    while IFS=$'\t' read -r index name driver sample_spec state; do
        sinks+=("${name}")
    done < <(pactl list sinks short)

    # Find current sink index
    local current_index=-1
    for i in "${!sinks[@]}"; do
        if [[ "${sinks[$i]}" == "${current_sink}" ]]; then
            current_index=$i
            break
        fi
    done

    # Get next sink (cycle)
    local next_index=$(( (current_index + 1) % ${#sinks[@]} ))
    echo "${sinks[$next_index]}"
}

# Get all PulseAudio sinks with their volumes (optimized - single pactl call)
get_audio_sinks() {
    local chosen_sink="${1}"

    # Get all sinks info in one call for performance
    pactl list sinks | awk -v chosen="${chosen_sink}" '
        BEGIN {
            name = ""
            desc = ""
            volume = 0
            muted = 0
            in_sink = 0
        }

        /^Sink #[0-9]+/ {
            # Output previous sink if we have data
            if (name != "" && desc != "") {
                is_chosen = (name == chosen) ? 1 : 0
                print name "|" desc "|" volume "|" muted "|" is_chosen
            }
            # Reset for new sink
            name = ""
            desc = ""
            volume = 0
            muted = 0
            in_sink = 1
            next
        }

        in_sink && /Name:/ {
            name = $2
            next
        }

        in_sink && /Description:/ {
            desc = $0
            sub(/^[[:space:]]*Description:[[:space:]]*/, "", desc)
            next
        }

        in_sink && /^\tVolume:/ {
            # Extract percentage from actual Volume line (not Base Volume)
            # Format: Volume: front-left: 32768 /  50% / -18.06 dB
            # Extract all numbers followed by % and get the first one
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+%$/) {
                    volume = $i
                    break
                }
            }
            next
        }

        in_sink && /Mute:/ {
            muted = ($2 == "yes") ? 1 : 0
            next
        }

        END {
            # Output last sink
            if (name != "" && desc != "") {
                is_chosen = (name == chosen) ? 1 : 0
                print name "|" desc "|" volume "|" muted "|" is_chosen
            }
        }
    '
}

# Format sink name for display
format_sink_name() {
    local desc="${1}"

    # Shorten common descriptions
    case "${desc}" in
        *"Built-in Audio Analog Stereo"*)
            echo "Jack"
            ;;
        *"HDMI"*|*"DisplayPort"*)
            # Extract HDMI/DP number
            if [[ "${desc}" =~ HDMI.*([0-9]+) ]]; then
                echo "HDMI-${BASH_REMATCH[1]}"
            elif [[ "${desc}" =~ DisplayPort.*([0-9]+) ]]; then
                echo "DP-${BASH_REMATCH[1]}"
            else
                echo "HDMI"
            fi
            ;;
        *"Bluetooth"*|*"BT"*)
            # Try to extract device identifier
            if [[ "${desc}" =~ ([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
                echo "BT-${BASH_REMATCH[1]:0:8}"
            else
                echo "BT"
            fi
            ;;
        *"USB"*)
            echo "USB"
            ;;
        *)
            # Generic: take first word and limit length
            local short_name
            short_name="$(echo "${desc}" | awk '{print $1}' | cut -c1-10)"
            echo "${short_name}"
            ;;
    esac
}

# Build output from sink data
build_output() {
    local output=""
    local separator=" | "

    while IFS='|' read -r sink_name desc volume muted is_chosen; do
        [[ -z "${sink_name}" ]] && continue

        local name
        name="$(format_sink_name "${desc}")"

        local entry

        # Format entry based on state
        if [[ "${is_chosen}" == "1" ]]; then
            # Chosen sink - highlighted like focused i3 workspace
            if [[ "${muted}" == "1" ]]; then
                entry="%{F${COLOR_CHOSEN_FG}}%{B${COLOR_CHOSEN_BG}} ${name}: muted %{B-}%{F-}"
            else
                entry="%{F${COLOR_CHOSEN_FG}}%{B${COLOR_CHOSEN_BG}} ${name}: ${volume} %{B-}%{F-}"
            fi
        else
            # Normal sink - yellow name like backlight "Light:", normal value
            if [[ "${muted}" == "1" ]]; then
                entry="%{F${COLOR_PREFIX}}${name}:%{F-} %{F${COLOR_MUTED}}muted%{F-}"
            else
                entry="%{F${COLOR_PREFIX}}${name}:%{F-} %{F${COLOR_VALUE}}${volume}%{F-}"
            fi
        fi

        if [[ -n "${output}" ]]; then
            output="${output}${separator}${entry}"
        else
            output="${entry}"
        fi
    done

    echo "${output}"
}

# Main function
main() {
    local chosen_sink
    chosen_sink="$(get_chosen_sink)"

    # Fetch fresh data
    local sink_data
    sink_data="$(get_audio_sinks "${chosen_sink}")"

    # Build output
    local output
    output="$(echo "${sink_data}" | build_output)"

    # Output result
    if [[ -n "${output}" ]]; then
        echo "${output}"
    else
        echo "No audio devices"
    fi
}

# Handle click events for volume control
handle_click() {
    local chosen_sink
    chosen_sink="$(get_chosen_sink)"

    case "${1}" in
        left)
            # Left click - toggle mute on CHOSEN sink (not default)
            pactl set-sink-mute "${chosen_sink}" toggle
            ;;
        right)
            # Right click - cycle to next sink (default sink remains unchanged)
            local next_sink
            next_sink="$(get_next_sink "${chosen_sink}")"
            set_chosen_sink "${next_sink}"
            ;;
        scroll_up)
            # Scroll up - increase volume on CHOSEN sink
            pactl set-sink-volume "${chosen_sink}" +5%
            ;;
        scroll_down)
            # Scroll down - decrease volume on CHOSEN sink
            pactl set-sink-volume "${chosen_sink}" -5%
            ;;
    esac
}

# Check if this is a click event
if [[ $# -gt 0 ]]; then
    handle_click "${1}"
else
    main
fi
