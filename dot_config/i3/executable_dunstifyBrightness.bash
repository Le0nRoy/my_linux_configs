#!/bin/bash
## Send notification about current volume level using `dunstify`
# Arbitrary but unique message tag
msgTag="Brightness"
# Query light for current brightness level
bright="$(light -G)"
# Show the light notification
dunstify -a "changeBrightness" -u low -i audio-volume-high -h string:x-dunst-stack-tag:$msgTag \
    -h int:value:"$bright" "Brightness: ${bright}"

