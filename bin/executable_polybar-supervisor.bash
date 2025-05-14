#!/bin/bash

# === Configuration ===
LAUNCH_DELAY=1

# === Globals ===
declare -A PIDS
LAST_PRIMARY=""

function launch_mon_bars() {
    monitor="$1"

    if [[ "${monitor}" == "${LAST_PRIMARY}" ]]; then
        BAR_NAME_BOTTOM="primary"
        BAR_NAME_TOP="info"
    else
        BAR_NAME_BOTTOM="secondary"
        BAR_NAME_TOP="secondary-info"
    fi

    MONITOR="${monitor}" polybar --reload "${BAR_NAME_BOTTOM}" &
    pid_key="${monitor}:${BAR_NAME_BOTTOM}"
    PIDS["${pid_key}"]=$!
    echo "  ➤ Launched '${BAR_NAME_BOTTOM}' bar on '${monitor}' (pid ${PIDS["${pid_key}"]})"

    MONITOR="${monitor}" polybar  --reload "${BAR_NAME_TOP}" &
    pid_key="${monitor}:${BAR_NAME_TOP}"
    PIDS["${pid_key}"]=$!
    echo "  ➤ Launched '${BAR_NAME_TOP}' bar on '${monitor}' (pid ${PIDS["${pid_key}"]})"
}

function launch_bars() {
    local pid_key
    echo "[polybar-supervisor] Launching Polybar on all monitors..."

    # Kill existing Polybar instances
    killall -q polybar
    sleep "${LAUNCH_DELAY}"

    # Get current primary monitor
    LAST_PRIMARY=$(polybar --list-monitors | awk -F ':' '/primary/{print $1}')

    # Launch appropriate bar on each monitor
    while IFS= read -r monitor; do
        launch_mon_bars "${monitor}"
    done < <(polybar --list-monitors | cut -d: -f1)
}

function restart_if_primary_changed() {
    local current_primary

    current_primary=$(polybar --list-monitors | awk -F ':' '/primary/{print $1}')

    if [[ "${current_primary}" != "${LAST_PRIMARY}" ]]; then
        echo "[polybar-supervisor] Primary monitor changed (${LAST_PRIMARY} → ${current_primary}), restarting..."
        launch_bars
    fi
}

function monitor_bars() {
    while true; do
        restart_if_primary_changed

        for key in "${!PIDS[@]}"; do
            monitor="${key%%:*}"
            bar="${key##*:}"
            pid="${PIDS[$key]}"

            if ! kill -0 "${pid}" 2>/dev/null; then
                echo "[polybar-supervisor] Bar '${bar}' on '${monitor}' crashed, restarting..."

                MONITOR="${monitor}" polybar --reload "${bar}" &
                new_pid=$!
                PIDS["${monitor}:${bar}"]=${new_pid}
                echo "  ➤ Relaunched '${bar}' on '${monitor}' (pid '${new_pid}')"
            fi
        done

        sleep 2
    done
}

# === Start ===
launch_bars
monitor_bars

# === Cleanup ===
killall -q polybar

