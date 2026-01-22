#!/bin/bash
# Polybar script to display system stats: power consumption, max temp, max fan speed
# Usage: polybar_system_stats.bash [power|temp|fan]

set -euo pipefail

# Get total system power consumption in watts
# Tries multiple methods: battery discharge rate, nvidia-smi for GPU
get_power() {
    local total_power=0
    local found_source=0

    # Method 1: Battery power (if on battery)
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -d "${bat}" ]]; then
            local status power_now voltage_now current_now
            status="$(cat "${bat}/status" 2>/dev/null || echo "Unknown")"

            # power_now is in microwatts on some systems
            if [[ -f "${bat}/power_now" ]]; then
                power_now="$(cat "${bat}/power_now" 2>/dev/null || echo 0)"
                # Convert from microwatts to watts
                total_power=$(awk "BEGIN {printf \"%.1f\", ${power_now}/1000000}")
                found_source=1
            elif [[ -f "${bat}/current_now" ]] && [[ -f "${bat}/voltage_now" ]]; then
                # Some systems report current and voltage instead
                current_now="$(cat "${bat}/current_now" 2>/dev/null || echo 0)"
                voltage_now="$(cat "${bat}/voltage_now" 2>/dev/null || echo 0)"
                # current in microamps, voltage in microvolts
                total_power=$(awk "BEGIN {printf \"%.1f\", (${current_now} * ${voltage_now})/1000000000000}")
                found_source=1
            fi

            # If charging, show as negative (power in)
            if [[ "${status}" == "Charging" ]] && [[ "${total_power}" != "0" ]]; then
                total_power="-${total_power}"
            fi
        fi
    done

    # Method 2: Try to get GPU power and add it (for desktop or when on AC)
    if command -v nvidia-smi &>/dev/null; then
        local gpu_power
        gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        if [[ "${gpu_power}" =~ ^[0-9.]+$ ]]; then
            if [[ "${found_source}" -eq 1 ]]; then
                # Battery + GPU
                total_power=$(awk "BEGIN {printf \"%.1f\", ${total_power} + ${gpu_power}}")
            else
                # Just GPU (likely on AC power)
                total_power="${gpu_power}"
                found_source=1
            fi
        fi
    fi

    if [[ "${found_source}" -eq 1 ]]; then
        echo "${total_power}W"
    else
        echo "N/A"
    fi
}

# Get the highest temperature from all sensors
get_max_temp() {
    local max_temp=0
    local found=0

    # Try hwmon sensors first (direct kernel interface)
    for hwmon in /sys/class/hwmon/hwmon*/temp*_input; do
        if [[ -f "${hwmon}" ]]; then
            local temp
            temp="$(cat "${hwmon}" 2>/dev/null || echo 0)"
            # Convert from millidegrees to degrees
            temp=$((temp / 1000))
            if [[ "${temp}" -gt "${max_temp}" ]]; then
                max_temp="${temp}"
                found=1
            fi
        fi
    done

    # Also check thermal zones
    for tz in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -f "${tz}" ]]; then
            local temp
            temp="$(cat "${tz}" 2>/dev/null || echo 0)"
            # Convert from millidegrees to degrees
            temp=$((temp / 1000))
            if [[ "${temp}" -gt "${max_temp}" ]]; then
                max_temp="${temp}"
                found=1
            fi
        fi
    done

    # Try nvidia-smi for GPU temp
    if command -v nvidia-smi &>/dev/null; then
        local gpu_temp
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        if [[ "${gpu_temp}" =~ ^[0-9]+$ ]] && [[ "${gpu_temp}" -gt "${max_temp}" ]]; then
            max_temp="${gpu_temp}"
            found=1
        fi
    fi

    if [[ "${found}" -eq 1 ]] && [[ "${max_temp}" -gt 0 ]]; then
        echo "${max_temp}°C"
    else
        echo "N/A"
    fi
}

# Get the maximum fan speed in RPM
get_max_fan() {
    local max_fan=0
    local found=0

    # Check hwmon fan sensors
    for hwmon in /sys/class/hwmon/hwmon*/fan*_input; do
        if [[ -f "${hwmon}" ]]; then
            local fan
            fan="$(cat "${hwmon}" 2>/dev/null || echo 0)"
            if [[ "${fan}" -gt "${max_fan}" ]]; then
                max_fan="${fan}"
                found=1
            fi
        fi
    done

    # Try nvidia-smi for GPU fan (percentage, convert to indication)
    if command -v nvidia-smi &>/dev/null; then
        local gpu_fan
        gpu_fan=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
        if [[ "${gpu_fan}" =~ ^[0-9]+$ ]]; then
            # If we have RPM from CPU fans, show that
            # If no CPU fans, show GPU fan percentage
            if [[ "${found}" -eq 0 ]]; then
                echo "${gpu_fan}%"
                return
            fi
        fi
    fi

    if [[ "${found}" -eq 1 ]] && [[ "${max_fan}" -gt 0 ]]; then
        echo "${max_fan}"
    else
        echo "N/A"
    fi
}

# Main
case "${1:-}" in
    power)
        get_power
        ;;
    temp)
        get_max_temp
        ;;
    fan)
        get_max_fan
        ;;
    *)
        echo "Usage: ${0} [power|temp|fan]" >&2
        exit 1
        ;;
esac
