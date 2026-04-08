#!/bin/bash
# Polybar script to display system stats: power consumption, max temp, max fan speed
# Usage: polybar_system_stats.bash [power|power-detail|temp|fan]
#
# Power monitoring for ASUS ROG Zephyrus and similar AMD+NVIDIA laptops:
# - APU power (CPU + iGPU): amdgpu PPT, amd_energy, zenpower, k10temp, or RAPL
# - Discrete GPU power: nvidia-smi
# - Battery: discharge rate when on battery (if available)
#
# On GA503RS: amdgpu PPT (~60W under load) + nvidia RTX 3080 (~80W max) = ~140W typical max
#
# Color coding (polybar format):
# - Normal: white/default
# - Yellow: >100W (exceeds USB-C PD limit)
# - Red: >150W (high power, needs 240W adapter)

set -euo pipefail

# Power threshold for USB-C PD (100W)
POWER_THRESHOLD_WARN=100

# Polybar color codes
COLOR_NORMAL=""
COLOR_WARN="%{F#FFF700}"    # Yellow
COLOR_ALERT="%{F#FF0000}"   # Red
COLOR_RESET="%{F-}"

# Get CPU/APU package power
# For AMD APUs (like Ryzen 6000 series), amdgpu reports PPT (Package Power Tracking)
# which includes CPU cores + integrated GPU - this is the total APU power
# Returns power in watts or empty string if unavailable
get_cpu_power() {
    local cpu_power=""

    # Method 1: AMD APU via amdgpu driver (PPT = Package Power Tracking)
    # This is the most accurate for AMD APUs as it includes CPU + iGPU
    # power1_input is in microwatts
    for hwmon in /sys/class/hwmon/hwmon*/; do
        local name
        name="$(cat "${hwmon}/name" 2>/dev/null || echo "")"
        if [[ "${name}" == "amdgpu" ]]; then
            if [[ -f "${hwmon}/power1_input" ]]; then
                local power_uw
                power_uw="$(cat "${hwmon}/power1_input" 2>/dev/null || echo 0)"
                if [[ "${power_uw}" -gt 0 ]]; then
                    cpu_power=$(awk "BEGIN {printf \"%.1f\", ${power_uw}/1000000}")
                    break
                fi
            fi
        fi
    done

    # Method 2: AMD Energy driver (amd_energy module)
    if [[ -z "${cpu_power}" ]]; then
        for hwmon in /sys/class/hwmon/hwmon*/; do
            local name
            name="$(cat "${hwmon}/name" 2>/dev/null || echo "")"
            if [[ "${name}" == "amd_energy" ]]; then
                if [[ -f "${hwmon}/power1_input" ]]; then
                    local power_uw
                    power_uw="$(cat "${hwmon}/power1_input" 2>/dev/null || echo 0)"
                    if [[ "${power_uw}" -gt 0 ]]; then
                        cpu_power=$(awk "BEGIN {printf \"%.1f\", ${power_uw}/1000000}")
                        break
                    fi
                fi
            fi
        done
    fi

    # Method 3: zenpower or k10temp (AMD) - some expose power via SVI2
    if [[ -z "${cpu_power}" ]]; then
        for hwmon in /sys/class/hwmon/hwmon*/; do
            local name
            name="$(cat "${hwmon}/name" 2>/dev/null || echo "")"
            if [[ "${name}" == "zenpower" ]] || [[ "${name}" == "k10temp" ]]; then
                if [[ -f "${hwmon}/power1_input" ]]; then
                    local power_uw
                    power_uw="$(cat "${hwmon}/power1_input" 2>/dev/null || echo 0)"
                    if [[ "${power_uw}" -gt 0 ]]; then
                        cpu_power=$(awk "BEGIN {printf \"%.1f\", ${power_uw}/1000000}")
                        break
                    fi
                fi
            fi
        done
    fi

    # Method 4: Intel RAPL via powercap (requires root for energy_uj on some systems)
    # Try constraint_0_power_limit_uw which might be readable
    if [[ -z "${cpu_power}" ]]; then
        for rapl_dir in /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl/intel-rapl:0; do
            if [[ -f "${rapl_dir}/constraint_0_power_limit_uw" ]]; then
                local power_uw
                power_uw="$(cat "${rapl_dir}/constraint_0_power_limit_uw" 2>/dev/null || echo 0)"
                if [[ "${power_uw}" -gt 0 ]]; then
                    cpu_power=$(awk "BEGIN {printf \"%.1f\", ${power_uw}/1000000}")
                    break
                fi
            fi
        done
    fi

    # Method 5: ASUS WMI sensors (asus-wmi-sensors or asus-nb-wmi)
    if [[ -z "${cpu_power}" ]]; then
        for hwmon in /sys/class/hwmon/hwmon*/; do
            local name
            name="$(cat "${hwmon}/name" 2>/dev/null || echo "")"
            if [[ "${name}" == "asus_wmi_sensors" ]]; then
                if [[ -f "${hwmon}/power1_input" ]]; then
                    local power_uw
                    power_uw="$(cat "${hwmon}/power1_input" 2>/dev/null || echo 0)"
                    if [[ "${power_uw}" -gt 0 ]]; then
                        cpu_power=$(awk "BEGIN {printf \"%.1f\", ${power_uw}/1000000}")
                        break
                    fi
                fi
            fi
        done
    fi

    echo "${cpu_power}"
}

# Get GPU power from nvidia-smi
# Returns power in watts or empty string if unavailable
get_gpu_power() {
    local gpu_power=""

    if command -v nvidia-smi &>/dev/null; then
        gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
        # Validate it's a number
        if ! [[ "${gpu_power}" =~ ^[0-9.]+$ ]]; then
            gpu_power=""
        fi
    fi

    echo "${gpu_power}"
}

# Get battery power (discharge rate)
# Returns power in watts or empty string if unavailable
# Negative value means charging (power flowing in)
get_battery_power() {
    local battery_power=""

    for bat in /sys/class/power_supply/BAT*; do
        if [[ -d "${bat}" ]]; then
            local status power_now voltage_now current_now
            status="$(cat "${bat}/status" 2>/dev/null || echo "Unknown")"

            # power_now is in microwatts on some systems
            if [[ -f "${bat}/power_now" ]]; then
                power_now="$(cat "${bat}/power_now" 2>/dev/null || echo 0)"
                if [[ "${power_now}" -gt 0 ]]; then
                    battery_power=$(awk "BEGIN {printf \"%.1f\", ${power_now}/1000000}")
                fi
            elif [[ -f "${bat}/current_now" ]] && [[ -f "${bat}/voltage_now" ]]; then
                # Some systems report current and voltage instead
                current_now="$(cat "${bat}/current_now" 2>/dev/null || echo 0)"
                voltage_now="$(cat "${bat}/voltage_now" 2>/dev/null || echo 0)"
                if [[ "${current_now}" -gt 0 ]] && [[ "${voltage_now}" -gt 0 ]]; then
                    # current in microamps, voltage in microvolts
                    battery_power=$(awk "BEGIN {printf \"%.1f\", (${current_now} * ${voltage_now})/1000000000000}")
                fi
            fi

            # If charging, make negative (power flowing into system via charger, not battery drain)
            if [[ "${status}" == "Charging" ]] && [[ -n "${battery_power}" ]]; then
                battery_power="-${battery_power}"
            fi

            # Only process first battery
            break
        fi
    done

    echo "${battery_power}"
}

# Get total system power consumption in watts
# Sums: CPU package + GPU + Battery discharge (when on battery)
# When on AC: CPU + GPU gives approximate system load
# When on battery: Battery discharge rate is most accurate
get_power() {
    local total_power=0
    local found_source=0
    local cpu_power gpu_power battery_power
    local is_on_battery=0
    local power_breakdown=""

    # Check if on battery
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -d "${bat}" ]]; then
            local status
            status="$(cat "${bat}/status" 2>/dev/null || echo "Unknown")"
            if [[ "${status}" == "Discharging" ]]; then
                is_on_battery=1
            fi
            break
        fi
    done

    # Get individual power readings
    cpu_power="$(get_cpu_power)"
    gpu_power="$(get_gpu_power)"
    battery_power="$(get_battery_power)"

    # Calculate total power
    if [[ "${is_on_battery}" -eq 1 ]] && [[ -n "${battery_power}" ]]; then
        # On battery: battery discharge rate is total system power
        # But we can still add GPU if it has dedicated power path
        total_power="${battery_power}"
        found_source=1

        # Some laptops have GPU power included in battery drain, some don't
        # For accuracy, we could add GPU power but risk double counting
        # Conservative approach: use battery power as total when discharging
    else
        # On AC power: sum available readings
        if [[ -n "${cpu_power}" ]] && [[ "${cpu_power}" != "0" ]]; then
            total_power=$(awk "BEGIN {printf \"%.1f\", ${total_power} + ${cpu_power}}")
            found_source=1
        fi

        if [[ -n "${gpu_power}" ]] && [[ "${gpu_power}" != "0" ]]; then
            total_power=$(awk "BEGIN {printf \"%.1f\", ${total_power} + ${gpu_power}}")
            found_source=1
        fi

        # If we couldn't get CPU/GPU power but have battery with charging info
        # Show the charging power as negative (power being supplied)
        if [[ "${found_source}" -eq 0 ]] && [[ -n "${battery_power}" ]]; then
            total_power="${battery_power}"
            found_source=1
        fi
    fi

    if [[ "${found_source}" -eq 1 ]]; then
        # Apply color coding based on power threshold
        local color="${COLOR_NORMAL}"
        local power_float

        # Handle negative values (charging) for comparison
        power_float="${total_power#-}"

        # Only apply warning colors for positive power draw (not charging)
        if [[ "${total_power}" != -* ]]; then
            if awk "BEGIN {exit !(${power_float} >= 150)}"; then
                color="${COLOR_ALERT}"  # Red: very high power, needs 240W adapter
            elif awk "BEGIN {exit !(${power_float} >= ${POWER_THRESHOLD_WARN})}"; then
                color="${COLOR_WARN}"   # Yellow: exceeds USB-C PD limit
            fi
        fi

        echo "${color}${total_power}W${COLOR_RESET}"
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

# Show detailed power breakdown (for debugging/testing)
get_power_detail() {
    local cpu_power gpu_power battery_power
    local is_on_battery=0
    local battery_status="Unknown"

    # Check battery status
    for bat in /sys/class/power_supply/BAT*; do
        if [[ -d "${bat}" ]]; then
            battery_status="$(cat "${bat}/status" 2>/dev/null || echo "Unknown")"
            if [[ "${battery_status}" == "Discharging" ]]; then
                is_on_battery=1
            fi
            break
        fi
    done

    cpu_power="$(get_cpu_power)"
    gpu_power="$(get_gpu_power)"
    battery_power="$(get_battery_power)"

    echo "=== Power Summary ==="
    echo "Battery status: ${battery_status}"
    echo "On battery: ${is_on_battery}"
    echo ""
    echo "APU power (CPU+iGPU): ${cpu_power:-N/A} W"
    echo "Discrete GPU power:   ${gpu_power:-N/A} W"
    echo "Battery power:        ${battery_power:-N/A} W"
    if [[ -n "${cpu_power}" ]] && [[ -n "${gpu_power}" ]]; then
        local total
        total=$(awk "BEGIN {printf \"%.1f\", ${cpu_power:-0} + ${gpu_power:-0}}")
        echo "----------------------------"
        echo "Total (APU + dGPU):   ${total} W"
        if awk "BEGIN {exit !(${total} >= 100)}"; then
            echo "WARNING: Exceeds 100W USB-C PD limit!"
        fi
    fi
    echo ""

    # Show amdgpu details specifically
    echo "=== amdgpu hwmon (APU PPT) ==="
    for hwmon in /sys/class/hwmon/hwmon*/; do
        local name
        name="$(cat "${hwmon}/name" 2>/dev/null || echo "")"
        if [[ "${name}" == "amdgpu" ]]; then
            echo "Found: ${hwmon}"
            for f in "${hwmon}"/power*; do
                if [[ -f "${f}" ]]; then
                    local val label
                    val="$(cat "${f}" 2>/dev/null || echo "N/A")"
                    # Try to get label if exists
                    label_file="${f%_input}_label"
                    label_file="${label_file%_average}_label"
                    if [[ -f "${label_file}" ]]; then
                        label="$(cat "${label_file}" 2>/dev/null)"
                        echo "  $(basename "${f}"): ${val} (${label})"
                    else
                        echo "  $(basename "${f}"): ${val}"
                    fi
                fi
            done
        fi
    done

    # Show available hwmon sensors
    echo ""
    echo "=== All hwmon sensors ==="
    for hwmon in /sys/class/hwmon/hwmon*/; do
        if [[ -d "${hwmon}" ]]; then
            local name
            name="$(cat "${hwmon}/name" 2>/dev/null || echo "unknown")"
            echo -n "${hwmon##*/}: ${name}"
            # Check for power inputs
            if ls "${hwmon}"/power*_input &>/dev/null 2>&1; then
                echo -n " [has power]"
            fi
            if ls "${hwmon}"/energy*_input &>/dev/null 2>&1; then
                echo -n " [has energy]"
            fi
            echo ""
        fi
    done

    # Show RAPL if available
    echo ""
    echo "=== RAPL (powercap) ==="
    if [[ -d /sys/class/powercap ]]; then
        ls -la /sys/class/powercap/ 2>/dev/null || echo "Not accessible"
    else
        echo "Not available"
    fi
}

# Main
case "${1:-}" in
    power)
        get_power
        ;;
    power-detail)
        get_power_detail
        ;;
    temp)
        get_max_temp
        ;;
    fan)
        get_max_fan
        ;;
    *)
        echo "Usage: ${0} [power|power-detail|temp|fan]" >&2
        exit 1
        ;;
esac
