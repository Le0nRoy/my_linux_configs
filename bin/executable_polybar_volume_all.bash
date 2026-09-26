#!/bin/bash
# Polybar script to display volume for all audio sinks or sources with selection
# Shows: Jack: 50% | HDMI-1: muted | HDMI-2: 100% | BT-1: 20%
# The current PulseAudio default is highlighted (like focused i3 workspace).
#
# Usage:
#   polybar_volume_all.bash [--source] [event]
#     --source  operate on sources (mic) instead of sinks (output)
#     event     one of: left | right | scroll_up | scroll_down (omit to render)
#
# Left  click : cycle default to next device
# Right click : rofi context menu (set default / move running streams here)
# Scroll     : ±5% volume on current default
#
# The chosen device is always PulseAudio's live @DEFAULT_SINK@/@DEFAULT_SOURCE@
# (queried via `pactl get-default-{sink,source}`). This means when the current
# default disappears (HDMI unplugged, BT disconnected), PulseAudio's automatic
# fallback picks a new one and the widget follows it — no stale state file.

set -u

# --- Mode -------------------------------------------------------------------

MODE="sink"
if [[ "${1:-}" == "--source" ]]; then
    MODE="source"
    shift
fi

if [[ "${MODE}" == "source" ]]; then
    KIND="source"          # pactl object noun singular
    KIND_PLURAL="sources"
    STREAM_KIND="source-output"
    STREAM_KIND_PLURAL="source-outputs"
    STREAM_MOVE_CMD="move-source-output"
    GET_DEFAULT_CMD="get-default-source"
    SET_DEFAULT_CMD="set-default-source"
    SET_MUTE_CMD="set-source-mute"
    SET_VOLUME_CMD="set-source-volume"
    LIST_SHORT_CMD="list sources short"
    LIST_LONG_CMD="list sources"
    HEADER_RE="^Source #[0-9]+"
    MENU_TITLE="Microphone"
else
    KIND="sink"
    KIND_PLURAL="sinks"
    STREAM_KIND="sink-input"
    STREAM_KIND_PLURAL="sink-inputs"
    STREAM_MOVE_CMD="move-sink-input"
    GET_DEFAULT_CMD="get-default-sink"
    SET_DEFAULT_CMD="set-default-sink"
    SET_MUTE_CMD="set-sink-mute"
    SET_VOLUME_CMD="set-sink-volume"
    LIST_SHORT_CMD="list sinks short"
    LIST_LONG_CMD="list sinks"
    HEADER_RE="^Sink #[0-9]+"
    MENU_TITLE="Audio Output"
fi

# --- Colors (polybar formatting tags) --------------------------------------

COLOR_PREFIX="#FFF700"            # Yellow for device names (like backlight prefix)
COLOR_VALUE="#C5C8C6"             # Normal text for values
COLOR_MUTED="#707880"             # Muted device (gray)
COLOR_CHOSEN_FG="#000000"         # Chosen device foreground (black)
COLOR_CHOSEN_BG="#BD5E02"         # Chosen device background (orange)

# --- Default-device queries ------------------------------------------------

# Filter out sources ending in .monitor (they are per-sink loopbacks, not real
# input devices — polluting the mic widget with them is noise).
is_real_device() {
    [[ "${MODE}" != "source" ]] && return 0
    [[ "${1}" != *.monitor ]]
}

get_default_device() {
    # PulseAudio-managed default. Survives sink/source loss because pactl
    # automatically re-elects a new default when the current one goes away.
    pactl "${GET_DEFAULT_CMD}" 2>/dev/null
}

get_next_device() {
    local current="${1}"
    local -a devs=()
    local name
    while IFS=$'\t' read -r _index name _driver _sample _state; do
        is_real_device "${name}" || continue
        devs+=("${name}")
    done < <(pactl ${LIST_SHORT_CMD})

    [[ ${#devs[@]} -eq 0 ]] && return 0

    local i=-1 idx
    for idx in "${!devs[@]}"; do
        [[ "${devs[$idx]}" == "${current}" ]] && { i="${idx}"; break; }
    done
    echo "${devs[$(( (i + 1) % ${#devs[@]} ))]}"
}

# --- Enumeration + formatting ----------------------------------------------

get_devices() {
    # Emits: name|desc|volume%|muted(0/1)|is_default(0/1)
    local chosen="${1}"
    pactl ${LIST_LONG_CMD} | awk \
        -v chosen="${chosen}" \
        -v header_re="${HEADER_RE}" '
        function flush() {
            if (name != "" && desc != "") {
                is_chosen = (name == chosen) ? 1 : 0
                print name "|" desc "|" volume "|" muted "|" is_chosen
            }
        }
        $0 ~ header_re {
            flush()
            name = ""; desc = ""; volume = 0; muted = 0; in_dev = 1
            next
        }
        in_dev && /^\tName:/         { name = $2; next }
        in_dev && /^\tDescription:/  {
            desc = $0
            sub(/^[[:space:]]*Description:[[:space:]]*/, "", desc)
            next
        }
        in_dev && /^\tVolume:/ {
            for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+%$/) { volume = $i; break }
            next
        }
        in_dev && /^\tMute:/         { muted = ($2 == "yes") ? 1 : 0; next }
        END { flush() }
    '
}

format_dev_name() {
    local desc="${1}" name="${2}"
    case "${desc}" in
        *"Built-in Audio Analog Stereo"*) echo "Jack" ;;
        *"HDMI"*|*"DisplayPort"*)
            if [[ "${desc}" =~ HDMI.*([0-9]+) ]]; then
                echo "HDMI-${BASH_REMATCH[1]}"
            elif [[ "${desc}" =~ DisplayPort.*([0-9]+) ]]; then
                echo "DP-${BASH_REMATCH[1]}"
            else
                echo "HDMI"
            fi
            ;;
        *"Bluetooth"*|*"BT"*)
            if [[ "${desc}" =~ ([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
                echo "BT-${BASH_REMATCH[1]:0:8}"
            else
                echo "BT"
            fi
            ;;
        *"USB"*)     echo "USB" ;;
        *"Webcam"*)  echo "Cam" ;;
        *)
            echo "${desc}" | awk '{print $1}' | cut -c1-10
            ;;
    esac
}

build_output() {
    local output="" separator=" | "
    while IFS='|' read -r dev_name desc volume muted is_chosen; do
        [[ -z "${dev_name}" ]] && continue
        is_real_device "${dev_name}" || continue

        local label entry
        label="$(format_dev_name "${desc}" "${dev_name}")"

        if [[ "${is_chosen}" == "1" ]]; then
            if [[ "${muted}" == "1" ]]; then
                entry="%{F${COLOR_CHOSEN_FG}}%{B${COLOR_CHOSEN_BG}} ${label}: muted %{B-}%{F-}"
            else
                entry="%{F${COLOR_CHOSEN_FG}}%{B${COLOR_CHOSEN_BG}} ${label}: ${volume} %{B-}%{F-}"
            fi
        else
            if [[ "${muted}" == "1" ]]; then
                entry="%{F${COLOR_PREFIX}}${label}:%{F-} %{F${COLOR_MUTED}}muted%{F-}"
            else
                entry="%{F${COLOR_PREFIX}}${label}:%{F-} %{F${COLOR_VALUE}}${volume}%{F-}"
            fi
        fi

        [[ -n "${output}" ]] && output+="${separator}"
        output+="${entry}"
    done
    echo "${output}"
}

# --- Render ---------------------------------------------------------------

render() {
    local chosen dev_data output
    chosen="$(get_default_device)"
    dev_data="$(get_devices "${chosen}")"
    output="$(echo "${dev_data}" | build_output)"
    if [[ -n "${output}" ]]; then
        echo "${output}"
    else
        [[ "${MODE}" == "source" ]] && echo "No microphones" || echo "No audio devices"
    fi
}

# --- Context menu (right click) -------------------------------------------

# List running streams (sink-inputs or source-outputs) as "index<TAB>label".
# Label is "AppName — MediaName" pulled from properties; falls back to index.
list_streams() {
    pactl "list" "${STREAM_KIND_PLURAL}" | awk -v k="${STREAM_KIND}" '
        function flush() {
            if (idx != "") {
                label = app
                if (media != "") label = (app == "") ? media : (app " — " media)
                if (label == "") label = "(stream #" idx ")"
                print idx "\t" label
            }
        }
        /^Source Output #[0-9]+/ || /^Sink Input #[0-9]+/ {
            flush()
            idx = $NF; sub(/^#/, "", idx)
            app = ""; media = ""
            next
        }
        /application\.name = / {
            v = $0; sub(/^[^=]*= "/, "", v); sub(/"[[:space:]]*$/, "", v)
            app = v; next
        }
        /media\.name = / {
            v = $0; sub(/^[^=]*= "/, "", v); sub(/"[[:space:]]*$/, "", v)
            media = v; next
        }
        END { flush() }
    '
}

# Human-readable label for a device name (used in the menu).
device_label() {
    local target="${1}"
    while IFS='|' read -r dev_name desc _v _m _c; do
        [[ "${dev_name}" == "${target}" ]] || continue
        echo "$(format_dev_name "${desc}" "${dev_name}") (${dev_name})"
        return
    done < <(get_devices "")
    echo "${target}"
}

context_menu() {
    # Polybar's custom/script module has ONE right-click hook for the whole
    # widget — it cannot tell WHICH sub-label was clicked. So the menu asks
    # the user to pick a device first, then offers the per-device actions.
    # Esc at the action level returns to the device picker; Esc at the
    # device picker closes the flow. Mirrors bin/executable_asusctl_rofi.bash.
    #
    # ponytail: menu is two-step (pick device → pick action). Upgrade path
    # for true per-sink click: split each device into its own polybar
    # sub-module and pass the sink name as $1 to the click handler.
    command -v rofi >/dev/null 2>&1 || {
        notify-send -u low "polybar-audio" "rofi not installed" 2>/dev/null || true
        return 1
    }

    while true; do
        local chosen
        chosen="$(get_default_device)"

        # Enumerate devices for the menu.
        local -a menu=()
        local -a dev_names=()
        local dev_name desc _v _m _c label
        while IFS='|' read -r dev_name desc _v _m _c; do
            [[ -z "${dev_name}" ]] && continue
            is_real_device "${dev_name}" || continue
            label="$(format_dev_name "${desc}" "${dev_name}")"
            if [[ "${dev_name}" == "${chosen}" ]]; then
                menu+=("[default] ${label}  —  ${dev_name}")
            else
                menu+=("          ${label}  —  ${dev_name}")
            fi
            dev_names+=("${dev_name}")
        done < <(get_devices "${chosen}")

        if [[ ${#menu[@]} -eq 0 ]]; then
            notify-send -u low -a "polybar-audio" "No ${KIND_PLURAL} available" "" 2>/dev/null || true
            return 0
        fi

        local pick
        pick="$(printf '%s\n' "${menu[@]}" | rofi -dmenu -i -p "${MENU_TITLE} — pick ${KIND}:")" \
            || return 0
        [[ -z "${pick}" ]] && return 0

        # Resolve pick back to its device name.
        local target="" i
        for i in "${!menu[@]}"; do
            if [[ "${menu[$i]}" == "${pick}" ]]; then
                target="${dev_names[$i]}"
                break
            fi
        done
        [[ -z "${target}" ]] && return 0

        local target_label
        target_label="$(device_label "${target}")"

        local action
        # Esc here (rofi exit 1) → continue outer loop, back to device picker.
        action="$(printf '%s\n' \
            "Set as default" \
            "Move running ${STREAM_KIND_PLURAL} here" \
            "Cancel" \
            | rofi -dmenu -i -p "${target_label}:")" || continue

        case "${action}" in
            "Set as default")
                pactl "${SET_DEFAULT_CMD}" "${target}"
                notify-send -u low -a "polybar-audio" \
                    "Default ${KIND}" "${target_label}" 2>/dev/null || true
                return 0
                ;;
            "Move running "*)
                move_streams_menu "${target}" "${target_label}"
                return 0
                ;;
            "Cancel"|"")
                continue
                ;;
        esac
    done
}

move_streams_menu() {
    local target="${1}" target_label="${2}"
    local streams
    streams="$(list_streams)"
    if [[ -z "${streams}" ]]; then
        notify-send -u low -a "polybar-audio" \
            "No running ${STREAM_KIND_PLURAL}" "" 2>/dev/null || true
        return 0
    fi

    # rofi -multi-select for multi-select; user confirms with Enter.
    local selected
    selected="$(printf '%s\n' "${streams}" \
        | rofi -dmenu -i -multi-select \
               -p "Move to ${target_label} (Shift+Enter to mark, Enter to apply):")" \
        || return 0

    [[ -z "${selected}" ]] && return 0

    local line idx moved=0
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        idx="${line%%$'\t'*}"
        if pactl "${STREAM_MOVE_CMD}" "${idx}" "${target}" 2>/dev/null; then
            moved=$((moved + 1))
        fi
    done <<< "${selected}"

    notify-send -u low -a "polybar-audio" \
        "Moved ${moved} ${STREAM_KIND_PLURAL}" "to ${target_label}" 2>/dev/null || true
}

# --- Click dispatch --------------------------------------------------------

handle_click() {
    local chosen
    chosen="$(get_default_device)"
    [[ -z "${chosen}" ]] && return 0

    case "${1}" in
        left)
            # Left click - cycle default to next device
            local next
            next="$(get_next_device "${chosen}")"
            [[ -n "${next}" ]] && pactl "${SET_DEFAULT_CMD}" "${next}"
            ;;
        right)
            context_menu
            ;;
        scroll_up)
            pactl "${SET_MUTE_CMD}" "${chosen}" false
            pactl "${SET_VOLUME_CMD}" "${chosen}" +5%
            ;;
        scroll_down)
            pactl "${SET_MUTE_CMD}" "${chosen}" false
            pactl "${SET_VOLUME_CMD}" "${chosen}" -5%
            ;;
        mute)
            pactl "${SET_MUTE_CMD}" "${chosen}" toggle
            ;;
    esac
}

# --- Self-check (ponytail: single runnable check) --------------------------

self_check() {
    local fail=0
    # format_dev_name pure-string cases
    [[ "$(format_dev_name 'HDMI 1 Output' 'x')" == "HDMI-1" ]] || { echo "FAIL HDMI"; fail=1; }
    [[ "$(format_dev_name 'Built-in Audio Analog Stereo' 'x')" == "Jack" ]] || { echo "FAIL Jack"; fail=1; }
    [[ "$(format_dev_name 'Some USB Mic' 'x')" == "USB" ]] || { echo "FAIL USB"; fail=1; }
    # is_real_device: monitor filter only active in source mode
    MODE=source is_real_device "foo.monitor" && { echo "FAIL monitor filter"; fail=1; } || true
    MODE=source is_real_device "real_mic"    || { echo "FAIL real mic"; fail=1; }
    MODE=sink   is_real_device "foo.monitor" || { echo "FAIL sink no-filter"; fail=1; }
    if [[ "${fail}" == 0 ]]; then echo "self-check OK"; else return 1; fi
}

# --- Entry point -----------------------------------------------------------

case "${1:-}" in
    "")       render ;;
    self-check) self_check ;;
    *)        handle_click "${1}" ;;
esac
