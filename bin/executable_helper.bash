#!/bin/bash
# Main helper script - sources modular helper functions
# All function implementations are in helper/ subdirectory

# Evaluate the path to the script even if it runs through the symlink
HOME_HELPER_UNIQ_SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
HOME_HELPER_UNIQ_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
HOME_HELPER_UNIQ_SCRIPT_DIR="${HOME_HELPER_UNIQ_SCRIPT_PATH%/*}"

# Source all helper modules
HELPER_MODULE_DIR="${HOME_HELPER_UNIQ_SCRIPT_DIR}/helper"

# Load common variables first (other modules depend on it)
source "${HELPER_MODULE_DIR}/common.bash"

# Load all other modules (order doesn't matter after common)
source "${HELPER_MODULE_DIR}/tmux.bash"
source "${HELPER_MODULE_DIR}/git.bash"
source "${HELPER_MODULE_DIR}/system.bash"
source "${HELPER_MODULE_DIR}/storage.bash"
source "${HELPER_MODULE_DIR}/backup.bash"
source "${HELPER_MODULE_DIR}/utils.bash"

# Load environment variables if present
if [[ -f "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env" ]]; then
    source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env"
else
    source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env.template"
fi

## Autocompletion for this script
_helper_script() {
    local cur
    _init_completion || return

    COMPREPLY=($(compgen -W '$(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" "${HOME_HELPER_UNIQ_SCRIPT_PATH}")' -- "${cur}"))
} &&
    complete -F _helper_script "$HOME_HELPER_UNIQ_SCRIPT_NAME" 

show_error_and_usage() {
    if [[ -z "${1}" ]]; then
        echo "First parameter can't be empty"
        exit 1
    fi

    echo "Unknown command \"${1}\""
    local usage="Usage: ${0} "

    for cmd in $(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" "${HOME_HELPER_UNIQ_SCRIPT_PATH}"); do
        usage="${usage}${cmd}|"
    done

    usage="${usage::-1}"
    echo "${usage}"
    exit 1
}

# All function implementations have been moved to helper/ modules
# Functions are automatically available after sourcing modules above

# Do not execute script if it was called with `source` command, just do mandatory exports
EXEC_NAME=$0
EXEC_NAME="${EXEC_NAME[0]##*/}"
if [[ ! "$EXEC_NAME" == "$HOME_HELPER_UNIQ_SCRIPT_NAME"  ]]; then
    export PATH="$HOME/bin:$PATH"

    if [[ -e "$JOB_SETUP_FILE" ]]; then
        source $JOB_SETUP_FILE
    fi

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
    "kbd_brightness_up")
        light -s sysfs/leds/asus::kbd_backlight -A 5
        ;;
    "kbd_brightness_down")
        light -s sysfs/leds/asus::kbd_backlight -U 5
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
        polybar_start
        ;;
    "set_us_ru_keymap")
        set_us_ru_layout
        ;;
    "set_us_ge_keymap")
        setxkbmap -layout ge,us -option grp:alt_shift_toggle
        ;;
    "lock_screen")
        # Pause notifications
        dunstctl set-paused true

        setxkbmap us 
        i3lock \
            --ignore-empty-password \
            --show-failed-attempts \
            --image="${LOCK_SCREEN_IMAGE}" \
            --fill \
            --clock \
            --pass-screen-keys \
            --pass-volume-keys \
            --screen=1 \
            --time-pos="ix-450:iy-300" \
            --date-pos="tx:ty+30" \
            --date-str="%A, %d.%m.%Y" \
            --verif-text="Verifying..." \
            --wrong-text="Wrong!" \
            --noinput-text="No input"
        set_us_ru_layout

        # Resume notifications after unlock
        dunstctl set-paused false
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
    "set_background")
        set_background
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
            echo "Usage: $HOME_HELPER_UNIQ_SCRIPT_NAME swagger </path/to/openapi.json>"
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
    "firefox")
        shift
        LINK="${1}"
        if [ -n "${LINK}" ]; then
            # Format: "<win_id> <title>"
            mapfile -t WINDOWS < <(wmctrl -lx | awk '/Navigator/ {print $1 " " substr($0, index($0,$5))}')
            
            CHOICES=()
            
            for window in "${WINDOWS[@]}"; do
                WIN_ID=$(awk '{print $1}' <<<"${window}")
                TITLE=$(awk '{$1=""; print substr($0,2)}' <<<"${window}")
                CHOICES+=("${WIN_ID} ${TITLE}")
            done
            
            if [[ "${#CHOICES[@]}" -eq 1 ]]; then
                SELECTION="${CHOICES[0]}"
            else
                # Show selection menu 
                SELECTION=$(printf '%s\n' "${CHOICES[@]}" | rofi -dmenu -i -p "Open link with:")
            fi
            
            # Handle cancel 
            [ -z "${SELECTION}" ] && exit 0
            
            WIN_ID=$(awk '{print $1}' <<<"${SELECTION}")
            if [ -n "${WIN_ID}" ]; then
                # Focus the window and send URL (if provided)
                xdotool windowactivate "${WIN_ID}" 
                xdotool key --window "${WIN_ID}" ctrl+t 
                xdotool type --window "${WIN_ID}" --clearmodifiers "${LINK}"
                xdotool key --window "${WIN_ID}" Return
            fi
        else
            # Fallback to simple choose between profiles
            PROFILES=("personal")
            if [[ -f "${JOB_SETUP_FILE}" ]]; then
                PROFILES+=("work")
            fi

            CHOICE=$(printf '%s\n' "${PROFILES[@]}" | rofi -dmenu -p "Open in profile:")
            [ -z "$CHOICE" ] && exit 0

            if [[ "${CHOICE}" == "work" ]]; then
                "${JOB_SETUP_FILE}" firefox "$@"
            else
                /usr/bin/firefox "$@"
            fi
        fi
        ;;
    "firefox_personal")
        shift
        /usr/bin/firefox -P default-release "$@"
        ;;
    "firefox_docker")
        FIREFOX_CONTAINER_NAME="secure_firefox"
        echo "username: kasm_user"
        echo "password: password"
        docker run --rm -it --name="${FIREFOX_CONTAINER_NAME}" --shm-size=512m -p 6901:6901 -e VNC_PW=password kasmweb/firefox:1.14.0 | grep -A 1 'Paste this url in your browser:' 
        #URL_TO_CONNECT="$(docker logs ${FIREFOX_CONTAINER_NAME} | grep -A 1 'Paste this url in your browser:' | tail -n 1)"
        #echo "${URL_TO_CONNECT}"
        ;;
    "screens_settings")
        # Launch xrandr rofi menu for screen management
        bash "${HOME}/bin/xrandr_manager.bash" dmenu
        polybar_start
        ;;
    "vnc_over_ssh")
        shift
        SSH_ROUTE="$1"
        PORT="${2:-5900}"
        vncviewer -via "${SSH_ROUTE}" "localhost::${PORT}"
        ;;
    "rclone_bisync")
        shift
        rclone_systemd "$@"
        ;;
    "rclone_to_backup")
        shift
        rclone_to_backup "$@"
        ;;
    "tmux_session")
        tmux_main_session
        ;;
    "tmux_ide_session")
        tmux_ide_session
        ;;
    "todoist")
        EXECUTABLE="$(find "${HOME}/Applications/" -name "Todoist*")"
        "${EXECUTABLE}"
        ;;
    *)
        show_error_and_usage "$@"
        ;;
esac

