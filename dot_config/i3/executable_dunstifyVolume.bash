#!/bin/bash
## Send notification about current volume level using `dunstify`
# Arbitrary but unique message tag
msgTag="Volume"
# Query pactl for the current volume and whether or not the speaker is muted
volume="$(pactl get-sink-volume @DEFAULT_SINK@ | awk '{print $5}' | head -n 1)"
mute="$(pactl get-sink-mute @DEFAULT_SINK@ | awk '{print $2}')"
if [[ $volume == "0%" || "$mute" == "yes" ]]; then
    # Show the sound muted notification
    dunstify -a "changeVolume" -u low -i audio-volume-muted -h string:x-dunst-stack-tag:$msgTag "Volume is muted" 
else
    # Show the volume notification
    dunstify -a "changeVolume" -u low -i audio-volume-high -h string:x-dunst-stack-tag:$msgTag \
    -h int:value:"$volume" "Volume: ${volume}"
fi

