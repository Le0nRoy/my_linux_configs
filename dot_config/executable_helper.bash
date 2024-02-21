#!/bin/bash

if [[ -e "$JOB_SETUP_FILE" ]]; then
    source $JOB_SETUP_FILE
fi

# Evaluate the path to the script even if it runs through the symlink
_SCRIPT_PATH="${BASH_SOURCE[0]}"
_REAL_SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")

JOB_MOUNT_DIR="/Job"
JOB_SETUP_FILE="/Job/add_exports.bash"
JOB_TEARDOWN_FILE="/Job/remove_exports.bash"
 
DESKTOP_BG="/home/lap/Pictures/png_files/St_Louis_Sciamano.png"

## Export section
# Suppress Python HTTP warnings when work with devenv
export PYTHONWARNINGS="ignore:Unverified HTTPS request"

## Autocompletion for this script
_helper_script() {
    local cur
    _init_completion || return

    COMPREPLY=($(compgen -W '$(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" $_REAL_SCRIPT_PATH)' -- "$cur"))
} &&
    complete -F _helper_script  "./$_SCRIPT_PATH" "$_REAL_SCRIPT_PATH"

show_error_and_usage() {
    if [[ -z $1 ]]; then
        echo "First parameter can't be empty"
        exit 1
    fi

    echo "Unknown command \"$1\""
    USAGE="Usage: $0 "

    for cmd in $(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" $_REAL_SCRIPT_PATH); do
        USAGE="${USAGE}${cmd}|"
    done

    USAGE="${USAGE::-1}"
    echo "$USAGE"
    exit 1
}

function set_us_ru_layout() {
    setxkbmap -layout us,ru -option grp:alt_shift_toggle
}

function send_notification_brightnes() {
    # Arbitrary but unique message tag
    msgTag="Brightness"

    # Query light for current brightness level
    bright="$(light -G)"

    # Show the light notification
    dunstify -a "changeBrightness" -u low -i audio-volume-high -h string:x-dunst-stack-tag:$msgTag \
            -h int:value:"$bright" "Brightness: ${bright}"
}

function send_notification_volume () {
    ## Send notification about current volume level using `dunstify`

    # Arbitrary but unique message tag
    msgTag="Volume"

    # Query pactl for the current volume and whether or not the speaker is muted
    volume="$(pactl get-sink-volume $SINK_NAME | awk '{print $5}' | head -n 1)"
    mute="$(pactl get-sink-mute $SINK_NAME | awk '{print $2}')"
    if [[ $volume == "0%" || "$mute" == "yes" ]]; then
        # Show the sound muted notification
        dunstify -a "changeVolume" -u low -i audio-volume-muted -h string:x-dunst-stack-tag:$msgTag "Volume is muted" 
    else
        # Show the volume notification
        dunstify -a "changeVolume" -u low -i audio-volume-high -h string:x-dunst-stack-tag:$msgTag \
            -h int:value:"$volume" "Volume: ${volume}"
    fi
}

function set_volume() {
    print_usage () {
      echo "Usage: $_SCRIPT_PATH volume [-s pulseaudio_sink_name] action"
      echo '    -s - to get available sinks execute "pactl list sinks | awk '/Name:/{print $2}'"'
      echo '         if not set, than "@DEFAULT_SINK is chosen@"'
      echo '    action - one of ['raise', 'low', 'mute']'
    }

    case "$ACTION" in
        "mute")
            pactl set-sink-mute $SINK_NAME toggle
            ;;
        "raise")
            pactl set-sink-mute $SINK_NAME false
            pactl set-sink-volume $SINK_NAME +5%
            ;;
        "low")
            pactl set-sink-mute $SINK_NAME false
            pactl set-sink-volume $SINK_NAME -5%
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
}

# Do not execute script if it was called with `source` command
if [[ ! "$0" == "$_SCRIPT_PATH" && ! "$0" == "$_REAL_SCRIPT_PATH" ]]; then
    return
fi

## Main body of script
case "$1" in
    "toggle_touchpad")
        declare -i ID
        ID=$(xinput list | grep -Eio '(touchpad|glidepoint)\s*id=[0-9]{1,2}' | grep -Eo '[0-9]{1,2}')
        declare -i STATE
        STATE=$(xinput list-props "$ID" | grep 'Device Enabled' | awk '{print $4}')
        if [ "$STATE" -eq 1 ]
        then
            xinput disable "$ID"
            MESSAGE='Touchpad Disabled'
        else
            xinput enable "$ID"
            MESSAGE='Touchpad Enabled'
        fi
        
        notify-send --urgency=low --app-name='Touchpad' "$MESSAGE" --icon=input-touchpad
        ;;
    "brightness_up")
        light -A 5
        send_notification_brightnes
        ;;
    "brightness_down")
        light -U 5
        send_notification_brightnes
        ;;
    "volume")
        shift
        while getopts "h:s:" arg; do
          case $arg in
            h)
            print_usage
              ;;
            s)
            shift
            SINK_NAME=$OPTARG
            shift
              ;;
          esac
        done

        ACTION=$1
        SINK_NAME=${SINK_NAME:-@DEFAULT_SINK@}

        set_volume
        send_notification_volume
        ;;
    "polybar_start")
        # Primary display
        if [[ -z "$(ps -C 'polybar' -o cmd | grep info | grep -v secondary)" ]]; then
            MONITOR=$(xrandr | awk '/connected primary/{print $1}') polybar info --reload > /dev/null 2>&1 &
        fi
        if [[ -z "$(ps -C 'polybar' -o cmd | grep primary)" ]]; then
            polybar primary --reload > /dev/null 2>&1 &
        fi

        # Secondary displays
        for monitor in $(xrandr | awk '/ connected [1-9]/{print $1}'); do
            if [[ -z "$(ps -C 'polybar' -o cmd | grep 'secondary$')" ]]; then
                    MONITOR=$monitor polybar --reload secondary > /dev/null 2>&1 &
            fi
            if [[ -z "$(ps -C 'polybar' -o cmd | grep 'secondary-info$')" ]]; then
                    MONITOR=$monitor polybar --log=warning --reload secondary-info > /dev/null 2>&1 &
            fi
        done
        ;;
    "set_us_ru_keymap")
        set_us_ru_layout
        ;;
    "set_us_ge_keymap")
        setxkbmap -layout ge,us -option grp:alt_shift_toggle
        ;;
    "lock_screen")
        setxkbmap us 
        i3lock --ignore-empty-password --show-failed-attempts --image=/home/lap/Pictures/png_files/maximum_beat.png 
        set_us_ru_layout
        ;;
    "i3_restart")
        i3-nagbar --type=warning --message='Do you really want to exit i3? This will logout your X session.' --button 'Yes, exit i3' 'i3-msg exit'
        #  TODO add start of the i3
        ;;
    "i3-reload")
        i3-msg reload
        ;;
    "run_compositor")
        picom --backend glx --daemon
        ;;
    "job_mount")
        sudo fscrypt unlock "$JOB_MOUNT_DIR" 
        source $JOB_SETUP_FILE
        $JOB_SETUP_FILE start
        ;;
    "job_umount")
        source $JOB_TEARDOWN_FILE
        sudo fscrypt lock "$JOB_MOUNT_DIR"
        ;;
    "set_background")
        feh --bg-fill $DESKTOP_BG
        ;;
    "mitmproxy")
        docker run --rm -it \
            -v ~/.mitmproxy:/home/mitmproxy/.mitmproxy \
            -p 8080:8080 \
            -p 127.0.0.1:8081:8081 \
            mitmproxy/mitmproxy \
            mitmweb --web-host 0.0.0.0
        ;;
    "swagger-ui")
        if [[ -z "$2" ]]; then
            echo "Usage: $_SCRIPT_PATH swagger </path/to/openapi.json>"
            exit 1
        fi
        SWAGGER=$2
        SWAGGER_NAME=${SWAGGER##*/}
        PATH_TO_SWAGGER=${SWAGGER%/*}
        docker run --rm --name "swagger-ui" -p $PORT_SWAGGER_UI:8080 -e SWAGGER_JSON="/foo/$SWAGGER_NAME" -v "$PATH_TO_SWAGGER:/foo" swaggerapi/swagger-ui
        ;;
    "swagger-editor")
        docker run --rm --name "swagger-editor" -p $PORT_SWAGGER_EDITOR:8080 swaggerapi/swagger-editor
        ;;
    *)
        show_error_and_usage "$@"
        ;;
esac

