#!/bin/bash
# Input device handler - called by inputplug when devices connect/disconnect
# Usage: input_device_handler.bash <event> <device_id> <device_type> <device_name>
#
# Events: XIDeviceEnabled, XIDeviceDisabled, XISlaveAdded, XISlaveRemoved
# Device types: XISlavePointer, XISlaveKeyboard, XIFloatingSlave, XIMasterPointer, XIMasterKeyboard

EVENT="${1}"
DEVICE_ID="${2}"
DEVICE_TYPE="${3}"
DEVICE_NAME="${4:-}"

# Only handle keyboard additions
if [[ "${EVENT}" == "XISlaveAdded" && "${DEVICE_TYPE}" == "XISlaveKeyboard" ]]; then
    # Small delay to let the device fully initialize
    sleep 0.5

    # Re-apply keyboard layout using helper (which sources xsessionrc for input settings)
    "${HOME}/bin/helper.bash" set_us_ru_keymap

    notify-send --urgency=low --expire-time=2000 "Keyboard Connected" \
        "${DEVICE_NAME:-New keyboard} - layout applied" --icon=input-keyboard
fi
