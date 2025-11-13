#!/bin/bash

# Evaluate the path to the script even if it runs through the symlink
HOME_HELPER_UNIQ_SCRIPT_NAME="${BASH_SOURCE[0]##*/}"
HOME_HELPER_UNIQ_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
HOME_HELPER_UNIQ_SCRIPT_DIR="${HOME_HELPER_UNIQ_SCRIPT_PATH%/*}"

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

function sshfsctl() {
    set -euo pipefail

    local usage="Usage: sshfsctl [-h] [-r user@host] <start|stop|status|journal> <remote_path> <local_path>
Options:
  -h          Show this help message
  -r ADDRESS  Remote host in format user@host (default: caveman@192.168.3.31)"

    # Default values
    local remote_host="caveman@192.168.3.31"

    # Parse options
    local OPTIND opt
    while getopts ":hr:" opt; do
        case "$opt" in
            h)
                echo "${usage}"
                return 0
                ;;
            r)
                remote_host="${OPTARG}"
                ;;
            *)
                echo "${usage}"
                return 1
                ;;
        esac
    done
    shift $((OPTIND -1))

    # Positional arguments
    local action="${1:-}"
    local remote_path="${2:-}"
    local local_path="${3:-}"

    if [[ -z "${action}" || -z "${remote_path}" || -z "${local_path}" ]]; then
        echo "${usage}"
        return 1
    fi

    local remote="${remote_host}:${remote_path}"
    local instance="${remote}:${local_path}"
    local escaped
    escaped="$(systemd-escape "${instance}")"

    case "${action}" in
        start|stop|status)
            echo "Running: systemctl --user ${action} sshfs@${escaped}"
            systemctl --user "${action}" "sshfs@${escaped}"
            ;;
        journal)
            echo "Running: journalctl -f --user-unit=sshfs@${escaped}"
            journalctl -f --user-unit=sshfs@${escaped}
            ;;
        *)
            echo "Invalid action: ${action}"
            echo "${usage}"
            return 1
            ;;
    esac
}

function upgrade_system () {
    yay -Syu
    sudo paccache -r
    sudo npm install -g @openai/codex@latest
    sudo npm install -g @anthropic-ai/claude-code@latest
    sudo npm cache clean
    npm outdated -g --depth=0
}

function get_display() {
    echo $DISPLAY
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
        unzip "${file}"
        rm "${file}"
    done
    for book in $(ls | grep -E ".*\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2"); do
        local new_name
        new_name="$(echo "${book}" | sed -E 's/(.*)\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2/\1.fb2/')"
        mv "${book}" "${new_name}"
    done
}

function cut_video() {
    local input="${1}"
    local cut_start="${2}"
    local cut_duration="${3}"
    local output="${4}"
    ffmpeg -ss "${cut_start}" -i "${input}" -t "${cut_duration}" -vcodec copy -acodec copy "${output}"
}

function gpg_decrypt() {
    shift
    gpg --decrypt "${1}" | tee "${2}" | gpg --verify
}

function gpg_encrypt() {
    shift
    gpg --local-user Vadim_signature --sign --encrypt --armor --recipient "${1}"
}

function set_us_ru_layout() {
    setxkbmap -layout us,ru -option grp:alt_shift_toggle
    kbdd
}

function send_notification_brightnes() {
    # Arbitrary but unique message tag
    local msg_tag="Brightness"

    # Query light for current brightness level
    local bright
    bright="$(light -G)"

    # Show the light notification
    dunstify -a "changeBrightness" -u low -i audio-volume-high -h string:x-dunst-stack-tag:"${msg_tag}" \
            -h int:value:"${bright}" "Brightness: ${bright}"
}

function polybar_start () {
    kill $(ps aux | awk '/polybar-supervisor.bash/{print $2}')
    /bin/bash "${HOME}/bin/polybar-supervisor.bash"
}

function send_notification_volume () {
    ## Send notification about current volume level using `dunstify`

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
    print_usage () {
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

function gio_mount() {
    local phone_path
    phone_path="$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')"
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        gio mount "${phone_path}"
    fi
    local mount_point
    mount_point="$(gio info "${phone_path}" | awk '/local path/{print $3}')"
    cd "${mount_point}" || exit 1
}

function gio_umount() {
    local phone_path
    phone_path="$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')"
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        local mount_point
        mount_point="$(gio info "${phone_path}" | awk '/local path/{print $3}')"
        if [[ "${PWD}" == "${mount_point}" ]]; then
            cd "${HOME}" || exit 1
        fi
        gio mount -u "${phone_path}"
    fi
}

function job_mount() {
    if [[ ! -f "${JOB_SETUP_FILE}" ]]; then
        fscrypt unlock "${JOB_MOUNT_DIR}"
        source "${JOB_SETUP_FILE}"
        "${JOB_SETUP_FILE}" start
    else
        echo "${JOB_MOUNT_DIR} is already mounted"
    fi
}

function job_umount() {
    source "${JOB_TEARDOWN_FILE}"
    fscrypt lock "${JOB_MOUNT_DIR}"
}

function set_background() {
    feh --bg-fill "${DESKTOP_BG}"
}

function tmux_ide_session() {
    # Create or attach to IDE-focused tmux session
    # Session name is based on current working directory
    local session_name
    session_name="$(basename "${PWD}")"

    # Check if session already exists
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        # Attach to existing session
        tmux attach-session -t "${session_name}"
        return 0
    fi

    # Create new session with first window "ai-agents"
    tmux new-session -d -s "${session_name}" -n "ai-agents"

    # Split first window vertically (two panes side by side)
    tmux split-window -h -t "${session_name}:ai-agents"

    # Set pane titles and prepare commands
    tmux select-pane -t "${session_name}:ai-agents.0" -T "claude"
    tmux send-keys -t "${session_name}:ai-agents.0" "${HOME}/bin/claude_wrapper.bash" C-m

    tmux select-pane -t "${session_name}:ai-agents.1" -T "cursor"
    tmux send-keys -t "${session_name}:ai-agents.1" "${HOME}/bin/cursor_agent_wrapper.bash" C-m

    # Create second window "dev"
    tmux new-window -t "${session_name}" -n "dev"

    # Split second window vertically
    tmux split-window -h -t "${session_name}:dev"

    # Set pane titles for second window
    tmux select-pane -t "${session_name}:dev.0" -T "bash"
    tmux select-pane -t "${session_name}:dev.1" -T "git"

    # Select first window and first pane
    tmux select-window -t "${session_name}:ai-agents"
    tmux select-pane -t "${session_name}:ai-agents.0"

    # Attach to the session
    tmux attach-session -t "${session_name}"
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

