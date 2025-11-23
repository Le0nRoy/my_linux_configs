#!/bin/bash
# Helper System Module - System, display, and notification functions
# Depends on: common.bash (for DESKTOP_BG, LOCK_SCREEN_IMAGE, SINK_NAME)

function get_display() {
    # Get current DISPLAY environment variable
    echo "${DISPLAY}"
}

function set_us_ru_layout() {
    # Set US/RU keyboard layout with Alt+Shift toggle
    setxkbmap -layout us,ru -option grp:alt_shift_toggle
    kbdd
}

function set_background() {
    # Set desktop background using feh
    feh --bg-fill "${DESKTOP_BG}"
}

function polybar_start() {
    # Restart polybar by killing supervisor and restarting
    kill $(ps aux | awk '/polybar-supervisor.bash/{print $2}')
    /bin/bash "${HOME}/bin/polybar-supervisor.bash"
}

function send_notification_brightnes() {
    # Send desktop notification for current brightness level
    # Arbitrary but unique message tag
    local msg_tag="Brightness"

    # Query light for current brightness level
    local bright
    bright="$(light -G)"

    # Show the light notification
    dunstify -a "changeBrightness" -u low -i audio-volume-high -h string:x-dunst-stack-tag:"${msg_tag}" \
            -h int:value:"${bright}" "Brightness: ${bright}"
}

function send_notification_volume() {
    # Send desktop notification for current volume level
    # Arbitrary but unique message tag
    local msg_tag="Volume"

    # Query pactl for the current volume and whether or not the speaker is muted
    local volume
    local mute
    volume="$(pactl get-sink-volume "${SINK_NAME}" | awk '{print $5}' | head -n 1)"
    mute="$(pactl get-sink-mute "${SINK_NAME}" | awk '{print $2}')"
    if [[ "${volume}" == "0%" || "${mute}" == "yes" ]]; then
        # Show the sound muted notification
        dunstify -a "changeVolume" -u low -i audio-volume-muted -h string:x-dunst-stack-tag:"${msg_tag}" "Volume is muted"
    else
        # Show the volume notification
        dunstify -a "changeVolume" -u low -i audio-volume-high -h string:x-dunst-stack-tag:"${msg_tag}" \
            -h int:value:"${volume}" "Volume: ${volume}"
    fi
}

function set_volume() {
    # Control audio volume (raise/lower/mute)
    # Uses ACTION and SINK_NAME variables set by caller
    print_usage() {
        echo "Usage: ${HOME_HELPER_UNIQ_SCRIPT_NAME} volume [-s pulseaudio_sink_name] action"
        echo '    -s - to get available sinks execute "pactl list sinks | awk '\''/Name:/{print $2}'\''"'
        echo '         if not set, than "@DEFAULT_SINK is chosen@"'
        echo '    action - one of ['\'raise\'', '\''low\'', '\''mute\'']'
    }

    case "${ACTION}" in
        "mute")
            pactl set-sink-mute "${SINK_NAME}" toggle
            ;;
        "raise")
            pactl set-sink-mute "${SINK_NAME}" false
            pactl set-sink-volume "${SINK_NAME}" +5%
            ;;
        "low")
            pactl set-sink-mute "${SINK_NAME}" false
            pactl set-sink-volume "${SINK_NAME}" -5%
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
}
