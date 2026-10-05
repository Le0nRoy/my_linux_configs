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
# Right click : rofi context menu (volume bars, mute, set default, move
#               running streams here). Inside the menu ←/→ and the mouse
#               wheel change the selected device's volume, Alt+m toggles mute.
# Scroll     : ±5% volume on current default (capped at VOLUME_MAX)
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
    GET_VOLUME_CMD="get-source-volume"
    GET_MUTE_CMD="get-source-mute"
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
    GET_VOLUME_CMD="get-sink-volume"
    GET_MUTE_CMD="get-sink-mute"
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

# --- Volume control ---------------------------------------------------------

VOLUME_STEP=5                     # % per scroll tick / arrow press
VOLUME_MAX=150                    # hard cap, same ceiling as pavucontrol
VOLUME_BAR_WIDTH=20

# Current volume of a device as a bare integer (first channel).
get_volume() {
    pactl "${GET_VOLUME_CMD}" "${1}" 2>/dev/null \
        | grep -o -m1 '[0-9]\+%' | head -n1 | tr -d '%'
}

# Prints 1 when the device is muted, 0 otherwise.
get_mute() {
    if pactl "${GET_MUTE_CMD}" "${1}" 2>/dev/null | grep -q 'yes'; then
        echo 1
    else
        echo 0
    fi
}

# Pure: target volume for current + delta, clamped to [0, max].
clamp_volume() {
    local cur="${1}" delta="${2}" max="${3}" new
    new=$(( cur + delta ))
    (( new < 0 )) && new=0
    (( new > max )) && new="${max}"
    echo "${new}"
}

# Change a device's volume by a signed delta (e.g. 5 or -5) and unmute it,
# matching the widget's scroll behaviour. Relative steps keep the channel
# balance; only a step that would cross VOLUME_MAX is set absolutely.
change_volume() {
    local dev="${1}" delta="${2}" cur
    cur="$(get_volume "${dev}")"
    [[ -z "${cur}" ]] && return 0
    pactl "${SET_MUTE_CMD}" "${dev}" false
    if (( delta > 0 && cur + delta > VOLUME_MAX )); then
        pactl "${SET_VOLUME_CMD}" "${dev}" "$(clamp_volume "${cur}" "${delta}" "${VOLUME_MAX}")%"
    elif (( delta > 0 )); then
        pactl "${SET_VOLUME_CMD}" "${dev}" "+${delta}%"
    else
        pactl "${SET_VOLUME_CMD}" "${dev}" "${delta}%"
    fi
}

toggle_mute() {
    pactl "${SET_MUTE_CMD}" "${1}" toggle
}

# Pure: text progress bar for a volume percentage, e.g. "█████░░░░░  50%".
# The bar saturates at 100%; the number shows any boost above it.
volume_bar() {
    local pct="${1}" width="${2:-${VOLUME_BAR_WIDTH}}" filled i bar=""
    filled=$(( (pct > 100 ? 100 : pct) * width / 100 ))
    for (( i = 0; i < width; i++ )); do
        if (( i < filled )); then bar+="█"; else bar+="░"; fi
    done
    printf '%s %3d%%' "${bar}" "${pct}"
}

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
    local desc="${1}"
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
        label="$(format_dev_name "${desc}")"

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

# List running streams (sink-inputs or source-outputs) as
# "index<TAB>label<TAB>device-index". Label is "AppName — MediaName" pulled
# from properties; falls back to index.
list_streams() {
    pactl "list" "${STREAM_KIND_PLURAL}" | awk -v k="${STREAM_KIND}" '
        function flush() {
            if (idx != "") {
                label = app
                if (media != "") label = (app == "") ? media : (app " — " media)
                if (label == "") label = "(stream #" idx ")"
                print idx "\t" label "\t" dev
            }
        }
        /^Source Output #[0-9]+/ || /^Sink Input #[0-9]+/ {
            flush()
            idx = $NF; sub(/^#/, "", idx)
            app = ""; media = ""; dev = ""
            next
        }
        /^\t(Sink|Source): [0-9]+/ { dev = $2; next }
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

# PulseAudio index of a device name (streams refer to devices by index).
device_index() {
    local target="${1}" index name
    while IFS=$'\t' read -r index name _rest; do
        [[ "${name}" == "${target}" ]] && { echo "${index}"; return; }
    done < <(pactl ${LIST_SHORT_CMD})
}

# Human-readable label for a device name (used in the menu).
device_label() {
    local target="${1}"
    while IFS='|' read -r dev_name desc _v _m _c; do
        [[ "${dev_name}" == "${target}" ]] || continue
        echo "$(format_dev_name "${desc}") (${dev_name})"
        return
    done < <(get_devices "")
    echo "${target}"
}

# rofi returns 10 + (N - 1) when -kb-custom-N fires.
ROFI_RC_VOL_UP=10
ROFI_RC_VOL_DOWN=11
ROFI_RC_MUTE=12

# Shared rofi flags for the volume-aware menus. Left/Right and the mouse
# wheel are taken away from cursor movement / row scrolling and turned into
# volume keys; Alt+m toggles mute. Rows are returned by index (-format i)
# so labels can carry live volume bars without breaking the lookup.
ROFI_VOLUME_ARGS=(
    -dmenu -i -no-custom -format i
    -kb-move-char-forward "Control+f"
    -kb-move-char-back "Control+b"
    -ml-row-up ""
    -ml-row-down ""
    -kb-custom-1 "Right,ScrollUp"
    -kb-custom-2 "Left,ScrollDown"
    -kb-custom-3 "Alt+m"
)
# Usage hint (-mesg) goes below the list instead of under the prompt.
ROFI_MESG_BOTTOM=(-theme-str 'mainbox { children: [ inputbar, listview, message ]; }')
ROFI_VOLUME_HINT="←/→ or wheel: volume ±${VOLUME_STEP}%   ·   Alt+m: mute/unmute"

# Applies a volume/mute rofi exit code to a device. Returns 1 if rc is not
# one of the custom volume keys.
apply_volume_key() {
    local rc="${1}" dev="${2}"
    case "${rc}" in
        "${ROFI_RC_VOL_UP}")   change_volume "${dev}" "${VOLUME_STEP}" ;;
        "${ROFI_RC_VOL_DOWN}") change_volume "${dev}" "-${VOLUME_STEP}" ;;
        "${ROFI_RC_MUTE}")     toggle_mute "${dev}" ;;
        *) return 1 ;;
    esac
}

# Bar + mute marker shown next to a device in the menus.
volume_status() {
    local vol="${1}" muted="${2}"
    if [[ "${muted}" == "1" ]]; then
        echo "$(volume_bar "${vol}")  [muted]"
    else
        volume_bar "${vol}"
    fi
}

context_menu() {
    # Polybar's custom/script module has ONE right-click hook for the whole
    # widget — it cannot tell WHICH sub-label was clicked. So the menu asks
    # the user to pick a device first, then offers the per-device actions.
    # Esc at the action level returns to the device picker; Esc at the
    # device picker closes the flow. Mirrors bin/executable_asusctl_rofi.bash.
    #
    # Volume keys re-launch rofi with the same row selected, so holding an
    # arrow key steps the volume while the bar redraws.
    #
    # ponytail: menu is two-step (pick device → pick action). Upgrade path
    # for true per-sink click: split each device into its own polybar
    # sub-module and pass the sink name as $1 to the click handler.
    command -v rofi >/dev/null 2>&1 || {
        notify-send -u low "polybar-audio" "rofi not installed" 2>/dev/null || true
        return 1
    }

    local sel=0
    while true; do
        local chosen
        chosen="$(get_default_device)"

        # Enumerate devices for the menu.
        local -a menu=() dev_names=() muted_rows=()
        local active_row="" dev_name desc vol muted _c label mark
        while IFS='|' read -r dev_name desc vol muted _c; do
            [[ -z "${dev_name}" ]] && continue
            is_real_device "${dev_name}" || continue
            label="$(format_dev_name "${desc}")"
            mark="         "
            if [[ "${dev_name}" == "${chosen}" ]]; then
                mark="[default]"
                active_row="${#menu[@]}"
            fi
            [[ "${muted}" == "1" ]] && muted_rows+=("${#menu[@]}")
            menu+=("$(printf '%s %-8s %s  —  %s' "${mark}" "${label}" \
                "$(volume_status "${vol%\%}" "${muted}")" "${dev_name}")")
            dev_names+=("${dev_name}")
        done < <(get_devices "${chosen}")

        if [[ ${#menu[@]} -eq 0 ]]; then
            notify-send -u low -a "polybar-audio" "No ${KIND_PLURAL} available" "" 2>/dev/null || true
            return 0
        fi
        (( sel >= ${#menu[@]} )) && sel=0

        local -a marks=()
        [[ -n "${active_row}" ]] && marks+=(-a "${active_row}")
        [[ ${#muted_rows[@]} -gt 0 ]] && marks+=(-u "$(IFS=,; echo "${muted_rows[*]}")")

        local pick rc
        pick="$(printf '%s\n' "${menu[@]}" | rofi "${ROFI_VOLUME_ARGS[@]}" "${ROFI_MESG_BOTTOM[@]}" \
            "${marks[@]}" -selected-row "${sel}" \
            -mesg "${ROFI_VOLUME_HINT}   ·   Enter: actions   ·   Esc: close" \
            -p "${MENU_TITLE} — pick ${KIND}:")"
        rc=$?

        # Resolve the picked row index back to its device name.
        if [[ ! "${pick}" =~ ^[0-9]+$ ]] || (( pick >= ${#dev_names[@]} )); then
            return 0
        fi
        local target="${dev_names[$pick]}"
        sel="${pick}"

        apply_volume_key "${rc}" "${target}" && continue
        [[ "${rc}" == 0 ]] || return 0

        device_menu "${target}"
    done
}

# Per-device action menu. Every action keeps this menu open; Esc / "Back"
# returns to the device picker.
device_menu() {
    local target="${1}" target_label sel=0
    target_label="$(device_label "${target}")"

    while true; do
        local vol muted mute_action default_row
        vol="$(get_volume "${target}")"
        muted="$(get_mute "${target}")"
        [[ -z "${vol}" ]] && return 0   # device vanished (unplugged)
        if [[ "${muted}" == "1" ]]; then mute_action="Unmute"; else mute_action="Mute"; fi
        default_row="Set as default"
        [[ "$(get_default_device)" == "${target}" ]] && default_row="Set as default  (current default)"

        local -a rows=(
            "Volume  $(volume_status "${vol}" "${muted}")"
            "${mute_action}"
            "${default_row}"
            "Move running ${STREAM_KIND_PLURAL} here"
            "Back"
        )
        local -a marks=()
        [[ "${muted}" == "1" ]] && marks+=(-u 0)

        local pick rc
        pick="$(printf '%s\n' "${rows[@]}" | rofi "${ROFI_VOLUME_ARGS[@]}" "${ROFI_MESG_BOTTOM[@]}" \
            "${marks[@]}" -selected-row "${sel}" \
            -mesg "${ROFI_VOLUME_HINT}   ·   Esc: back" \
            -p "${target_label}:")"
        rc=$?
        [[ "${pick}" =~ ^[0-9]+$ ]] && sel="${pick}"

        apply_volume_key "${rc}" "${target}" && continue
        [[ "${rc}" == 0 ]] || return 0

        case "${pick}" in
            0)  continue ;;   # volume row: adjust with ←/→, Enter is a no-op
            1)  toggle_mute "${target}" ;;
            2)
                pactl "${SET_DEFAULT_CMD}" "${target}"
                notify-send -u low -a "polybar-audio" \
                    "Default ${KIND}" "${target_label}" 2>/dev/null || true
                ;;
            3)  move_streams_menu "${target}" "${target_label}" ;;
            *)  return 0 ;;
        esac
    done
}

# Stream picker. Stays open after moving (rows already on the target are
# marked "[here]") so more streams can be moved; Esc returns to the device
# menu. With no running streams it notifies and returns straight away.
move_streams_menu() {
    local target="${1}" target_label="${2}" sel=0
    while true; do
        local target_index
        target_index="$(device_index "${target}")"

        local -a rows=() stream_ids=() here_rows=()
        local idx label dev mark
        while IFS=$'\t' read -r idx label dev; do
            [[ -z "${idx}" ]] && continue
            mark="      "
            if [[ -n "${target_index}" && "${dev}" == "${target_index}" ]]; then
                mark="[here]"
                here_rows+=("${#rows[@]}")
            fi
            rows+=("${mark} ${label}")
            stream_ids+=("${idx}")
        done < <(list_streams)

        if [[ ${#rows[@]} -eq 0 ]]; then
            notify-send -u low -a "polybar-audio" \
                "No running ${STREAM_KIND_PLURAL}" "" 2>/dev/null || true
            return 0
        fi
        (( sel >= ${#rows[@]} )) && sel=0

        local -a marks=()
        [[ ${#here_rows[@]} -gt 0 ]] && marks+=(-a "$(IFS=,; echo "${here_rows[*]}")")

        # -multi-select: Shift+Enter marks rows, Enter moves the marked rows
        # (or the highlighted one when nothing is marked).
        local selected
        selected="$(printf '%s\n' "${rows[@]}" \
            | rofi -dmenu -i -no-custom -multi-select -format i \
                   "${ROFI_MESG_BOTTOM[@]}" "${marks[@]}" -selected-row "${sel}" \
                   -mesg "Shift+Enter: mark   ·   Enter: move here   ·   Esc: back" \
                   -p "Move to ${target_label}:")" \
            || return 0
        [[ -z "${selected}" ]] && return 0

        local line moved=0
        while IFS= read -r line; do
            [[ "${line}" =~ ^[0-9]+$ ]] && (( line < ${#stream_ids[@]} )) || continue
            sel="${line}"
            if pactl "${STREAM_MOVE_CMD}" "${stream_ids[$line]}" "${target}" 2>/dev/null; then
                moved=$((moved + 1))
            fi
        done <<< "${selected}"

        notify-send -u low -a "polybar-audio" \
            "Moved ${moved} ${STREAM_KIND_PLURAL}" "to ${target_label}" 2>/dev/null || true
    done
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
            change_volume "${chosen}" "${VOLUME_STEP}"
            ;;
        scroll_down)
            change_volume "${chosen}" "-${VOLUME_STEP}"
            ;;
    esac
}

# --- Self-check (ponytail: single runnable check) --------------------------

self_check() {
    local fail=0
    # format_dev_name pure-string cases
    [[ "$(format_dev_name 'HDMI 1 Output')" == "HDMI-1" ]] || { echo "FAIL HDMI"; fail=1; }
    [[ "$(format_dev_name 'Built-in Audio Analog Stereo')" == "Jack" ]] || { echo "FAIL Jack"; fail=1; }
    [[ "$(format_dev_name 'Some USB Mic')" == "USB" ]] || { echo "FAIL USB"; fail=1; }
    # is_real_device: monitor filter only active in source mode
    MODE=source is_real_device "foo.monitor" && { echo "FAIL monitor filter"; fail=1; } || true
    MODE=source is_real_device "real_mic"    || { echo "FAIL real mic"; fail=1; }
    MODE=sink   is_real_device "foo.monitor" || { echo "FAIL sink no-filter"; fail=1; }
    # clamp_volume bounds
    [[ "$(clamp_volume 50 5 150)"   == "55" ]]  || { echo "FAIL clamp step"; fail=1; }
    [[ "$(clamp_volume 148 5 150)"  == "150" ]] || { echo "FAIL clamp max"; fail=1; }
    [[ "$(clamp_volume 3 -5 150)"   == "0" ]]   || { echo "FAIL clamp min"; fail=1; }
    # volume_bar fill and saturation above 100%
    [[ "$(volume_bar 50 10)"  == "█████░░░░░  50%" ]] || { echo "FAIL bar 50"; fail=1; }
    [[ "$(volume_bar 0 4)"    == "░░░░   0%" ]]       || { echo "FAIL bar 0"; fail=1; }
    [[ "$(volume_bar 130 4)"  == "████ 130%" ]]       || { echo "FAIL bar 130"; fail=1; }
    if [[ "${fail}" == 0 ]]; then echo "self-check OK"; else return 1; fi
}

# --- Entry point -----------------------------------------------------------

case "${1:-}" in
    "")       render ;;
    self-check) self_check ;;
    *)        handle_click "${1}" ;;
esac
