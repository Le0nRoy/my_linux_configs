#!/bin/basj
print_usage () {
      echo "Usage: dunstifyVolume.sh [-s pulseaudio_sink_name] action"
      echo '    -s - to get available sinks execute "pactl list sinks | awk '/Name:/{print $2}'"'
      echo '         if not set, than "@DEFAULT_SINK is chosen@"'
      echo '    action - one of ['raise', 'low', 'mute']'
}

trap print_usage ERR 

function change_volume () {
    if [[ "$ACTION" == "mute" ]]; then
        pactl set-sink-mute $SINK_NAME toggle
    elif [[ "$ACTION" == "raise" ]]; then
        pactl set-sink-mute $SINK_NAME false
        pactl set-sink-volume $SINK_NAME +5%
    elif [[ "$ACTION" == "low" ]]; then
        pactl set-sink-mute $SINK_NAME false
        pactl set-sink-volume $SINK_NAME -5%
    else
        exit 1
    fi
}

function send_notification () {
    ## Send notification about current volume level using `dunstify`

    # Arbitrary but unique message tag
    msgTag="Volume"

    echo $SINK_NAME
    echo $ACTION
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

change_volume
send_notification
