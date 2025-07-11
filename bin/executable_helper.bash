#!/bin/bash

# Evaluate the path to the script even if it runs through the symlink
HOME_HELPER_UNIQ_SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
HOME_HELPER_UNIQ_SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
HOME_HELPER_UNIQ_SCRIPT_DIR=${HOME_HELPER_UNIQ_SCRIPT_PATH%/*}

# Export job-related variables and functions
JOB_MOUNT_DIR="/Data/Job"
JOB_SETUP_FILE="/Data/Job/add_exports.bash"
JOB_TEARDOWN_FILE="/Data/Job/remove_exports.bash"
 
if [[ -f "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env" ]]; then
    source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env"
else
    source "${HOME_HELPER_UNIQ_SCRIPT_DIR}/.env.template"
fi

PORT_SWAGGER_UI=8081
PORT_SWAGGER_EDITOR=8082

DESKTOP_BG="${DESKTOP_BG:-"${HOME}/Pictures/png_files/St_Louis_Sciamano.png"}"
LOCK_SCREEN_IMAGE="${LOCK_SCREEN_IMAGE:-"${HOME}/Pictures/png_files/maximum_beat.png"}"

## Autocompletion for this script
_helper_script() {
    local cur
    _init_completion || return

    COMPREPLY=($(compgen -W '$(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" $HOME_HELPER_UNIQ_SCRIPT_PATH)' -- "$cur"))
} &&
    complete -F _helper_script "$HOME_HELPER_UNIQ_SCRIPT_NAME" 

show_error_and_usage() {
    if [[ -z $1 ]]; then
        echo "First parameter can't be empty"
        exit 1
    fi

    echo "Unknown command \"$1\""
    USAGE="Usage: $0 "

    for cmd in $(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" $HOME_HELPER_UNIQ_SCRIPT_PATH); do
        USAGE="${USAGE}${cmd}|"
    done

    USAGE="${USAGE::-1}"
    echo "$USAGE"
    exit 1
}

function get_display() {
    echo $DISPLAY
}

function chezmoi_add() {
    chezmoi add "$@"
    chezmoi update
}
function git_cleanout() {
    git gc 
    git fetch --prune --all
    git pull
    git remote prune origin
    git branch --merged | grep -E -v 'master|main' | grep -E -v '^\*' | xargs git branch -d
}

function adb_pull_music() {
    adb pull /sdcard/Vk/Vkontakte/ /Data/vkDownloads/Music/
}

function rclone_systemd() {
    for remote in $(rclone listremotes); do
        if ! rclone about "${remote}" > /dev/null 2>&1; then
            echo "Remote '${remote}' is not accessible. Aborting..."
            exit 1
        fi
    done
    rclone --log-systemd --log-level INFO --auto-confirm --human-readable --modify-window 24h bisync "$@"
}

function rclone_to_backup() {
    FILTERS_FILE="$1"
    SOURCE="$2"
    DESTINATION="$3"
    if [[ ! -f "${FILTERS_FILE}" ]]; then
        echo "Usage: rclone_to_backup <filters_file> <source_directory> <dest_directorry>"
        exit 1
    fi
    if [[ ! -d "${SOURCE}" || ! -d "${DESTINATION}" ]]; then
        echo "Usage: rclone_to_backup <filters_file> <source_directory> <dest_directorry>"
        exit 1
    fi
    # In order to do resync use flag:
    # --resync-mode newer
    rclone --log-level INFO --auto-confirm --human-readable --modify-window 24h bisync --filters-file "${FILTERS_FILE}" "${SOURCE}" "${DESTINATION}"
}

function unzip_books() {
    for file in *.fb2.zip; do 
        unzip $file
        rm $file
    done
    for book in $(ls | grep -E ".*\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2"); do
        new_name=$(echo $book | sed -E 's/(.*)\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2/\1.fb2/')
        mv $book $new_name
    done
}

function cut_video() {
    INPUT="$1"
    CUT_START="$2"
    CUT_DURATION="$3"
    OUTPUT="$4"
    ffmpeg -ss ${CUT_START} -i ${INPUT} -t ${CUT_DURATION} -vcodec copy -acodec copy ${OUTPUT}
}

function gpg_decrypt() {
    shift
    gpg --decrypt $1 | tee $2 | gpg --verify
}

function gpg_encrypt() {
    shift
    gpg --local-user Vadim_signature --sign --encrypt --armor --recipient $1
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

function polybar_start () {
    kill $(ps aux | awk '/polybar-supervisor.bash/{print $2}')
    /bin/bash "${HOME}/bin/polybar-supervisor.bash"
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
      echo "Usage: $HOME_HELPER_UNIQ_SCRIPT_NAME volume [-s pulseaudio_sink_name] action"
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

function gio_mount() {
    PHONE_PATH=$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')
    if ! gio info ${PHONE_PATH} > /dev/null 2>&1; then
        gio mount ${PHONE_PATH}
    fi
    MOUNT_POINT=$(gio info ${PHONE_PATH} | awk '/local path/{print $3}')
    cd ${MOUNT_POINT}
}

function gio_umount() {
    PHONE_PATH=$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')
    if ! gio info ${PHONE_PATH} > /dev/null 2>&1; then
        MOUNT_POINT=$(gio info ${PHONE_PATH} | awk '/local path/{print $3}')
        if [[ "${PWD}" == "${MOUNT_POINT}" ]]; then
            cd ${HOME}
        fi
        gio mount -u ${PHONE_PATH}
    fi
}

function job_mount() {
    if [[ ! -f ${JOB_SETUP_FILE} ]]; then
        fscrypt unlock "$JOB_MOUNT_DIR" 
        source $JOB_SETUP_FILE
        $JOB_SETUP_FILE start
    else
        echo "$JOB_MOUNT_DIR is already mounted"
    fi
}

function job_umount() {
    source $JOB_TEARDOWN_FILE
    fscrypt lock "$JOB_MOUNT_DIR"
}

function set_background() {
    feh --bg-fill $DESKTOP_BG
}

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
        if [[ -f "${JOB_SETUP_FILE}" ]]; then
            "${JOB_SETUP_FILE}" firefox "$@"
        else
            /usr/bin/firefox "$@"
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
        nvidia-settings
        polybar_start
        set_us_ru_layout
        set_background
        source "${HOME}/.xsessionrc"
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
        tmux new-session -s "${TMUX_SESSION}" -n "WorkSpace" -A -D
        ;;
    "todoist")
        EXECUTABLE="$(find "${HOME}/Applications/" -name "Todoist*")"
        "${EXECUTABLE}"
        ;;
    *)
        show_error_and_usage "$@"
        ;;
esac

