#!/bin/bash

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

