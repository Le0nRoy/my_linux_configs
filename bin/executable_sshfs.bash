#!/bin/bash
# sshfs.bash - Interactive SSHFS mount manager
#
# Usage: sshfs.bash [mount|umount|status|help]
#
# Discovers SSH hosts from ~/.ssh/config and manages SSHFS mounts
# via systemd user template units (sshfs@.service).
#
# Subcommands:
#   mount    - Interactive mount wizard (default in a terminal)
#   umount   - Interactive unmount of active mounts
#   status   - List all active SSHFS mounts
#   help     - Show this help text
#
# Systemd unit: sshfs@.service
# Backend:      ~/bin/sshfs-mount.sh
# Default mountpoint base: ~/ssh_mount/<user>_<host>

set -euo pipefail

# ===== CONSTANTS =====

SSH_CONFIG="${HOME}/.ssh/config"
SSH_MOUNT_BASE="${HOME}/ssh_mount"
SYSTEMD_UNIT_TEMPLATE="sshfs"

# ===== DISPLAY =====

show_header() {
    clear >/dev/tty
    echo "======================================" >/dev/tty
    echo "       SSHFS Mount Manager           " >/dev/tty
    echo "======================================" >/dev/tty
    echo "" >/dev/tty
}

# ===== SSH CONFIG PARSING =====

# Parse ~/.ssh/config and output "user@host" pairs (one per line).
# Skips wildcard Host patterns (containing * or ?).
# Prefers per-host User; falls back to a global User defined before any Host block.
parse_ssh_hosts() {
    local config_file="${SSH_CONFIG}"

    if [[ ! -f "${config_file}" ]]; then
        return 0
    fi

    local current_host="" current_user="" global_user=""
    local -a pairs=()

    _flush_host() {
        if [[ -z "${current_host}" ]]; then
            return
        fi
        # Skip wildcard patterns
        if [[ "${current_host}" == *"*"* || "${current_host}" == *"?"* ]]; then
            return
        fi
        local u="${current_user:-${global_user}}"
        if [[ -n "${u}" ]]; then
            pairs+=("${u}@${current_host}")
        fi
    }

    while IFS= read -r raw_line; do
        # Strip leading whitespace and inline comments
        local line="${raw_line#"${raw_line%%[![:space:]]*}"}"
        [[ "${line}" == "#"* || -z "${line}" ]] && continue

        # Case-insensitive keyword matching via lowercased keyword
        local keyword="${line%% *}"
        local value="${line#* }"
        local kw_lower
        kw_lower=$(echo "${keyword}" | tr '[:upper:]' '[:lower:]')

        case "${kw_lower}" in
            host)
                _flush_host
                # Host line may contain multiple space-separated patterns; take first
                current_host="${value%% *}"
                current_user=""
                ;;
            hostname)
                # Prefer the actual hostname for display when it differs from alias
                : # We intentionally use the Host alias for sshfs (ssh resolves it)
                ;;
            user)
                if [[ -z "${current_host}" ]]; then
                    global_user="${value%% *}"
                else
                    current_user="${value%% *}"
                fi
                ;;
            match)
                # Match blocks are complex; skip
                _flush_host
                current_host=""
                current_user=""
                ;;
        esac
    done < "${config_file}"

    _flush_host

    # Output unique sorted pairs
    if [[ ${#pairs[@]} -gt 0 ]]; then
        printf '%s\n' "${pairs[@]}" | sort -u
    fi
}

# ===== SYSTEMD HELPERS =====

# Encode an instance string for use in a systemd unit name.
# systemd-escape turns special chars (including @, :, /) into \xNN sequences.
escape_instance() {
    systemd-escape "${1}"
}

# Decode a systemd-escaped instance back to a human-readable string.
unescape_instance() {
    systemd-escape --unescape "${1}"
}

# Start an SSHFS systemd unit for the given instance string.
# Instance format: user@host:/remote/path:/local/path
do_mount() {
    local instance="${1}"
    local escaped
    escaped=$(escape_instance "${instance}")
    echo "Starting ${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service ..." >/dev/tty
    systemctl --user start "${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service"
}

# Stop an SSHFS systemd unit.
do_umount() {
    local instance="${1}"
    local escaped
    escaped=$(escape_instance "${instance}")
    echo "Stopping ${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service ..." >/dev/tty
    systemctl --user stop "${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service"
}

# Enable an SSHFS unit so it starts automatically on login.
do_enable() {
    local instance="${1}"
    local escaped
    escaped=$(escape_instance "${instance}")
    echo "Enabling ${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service ..." >/dev/tty
    systemctl --user enable "${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service"
}

# Return 0 if the given instance's unit is currently active.
is_mounted() {
    local instance="${1}"
    local escaped
    escaped=$(escape_instance "${instance}")
    systemctl --user is-active --quiet \
        "${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service" 2>/dev/null
}

# Print unescaped instance strings for every active sshfs@ unit.
list_active_instances() {
    systemctl --user list-units "${SYSTEMD_UNIT_TEMPLATE}@*.service" \
        --no-legend --no-pager 2>/dev/null \
        | awk '{print $1}' \
        | while read -r unit; do
            local raw="${unit#${SYSTEMD_UNIT_TEMPLATE}@}"
            raw="${raw%.service}"
            unescape_instance "${raw}"
        done
}

# ===== INTERACTIVE MENUS =====

# Present a numbered list of user@host pairs discovered from ~/.ssh/config,
# plus a "custom entry" option.  Returns the chosen "user@host" string via stdout.
select_host() {
    local -a pairs=()
    mapfile -t pairs < <(parse_ssh_hosts)

    show_header
    echo "Select SSH Host" >/dev/tty
    echo "----------------------------------------" >/dev/tty
    echo "" >/dev/tty

    local i=1
    if [[ ${#pairs[@]} -gt 0 ]]; then
        echo "Hosts found in ~/.ssh/config:" >/dev/tty
        for pair in "${pairs[@]}"; do
            printf "  %d) %s\n" "${i}" "${pair}" >/dev/tty
            i=$((i + 1))
        done
    else
        echo "  (no User entries found in ~/.ssh/config)" >/dev/tty
    fi

    local custom_idx="${i}"
    echo "" >/dev/tty
    printf "  %d) Enter custom user@host\n" "${custom_idx}" >/dev/tty
    echo "" >/dev/tty
    echo -n "Choose [1-${custom_idx}]: " >/dev/tty
    read -r choice </dev/tty

    if [[ "${choice}" == "${custom_idx}" ]]; then
        echo -n "Enter user@host: " >/dev/tty
        read -r custom </dev/tty
        if [[ -z "${custom}" ]]; then
            echo "No host entered." >/dev/tty
            return 1
        fi
        echo "${custom}"
    elif [[ "${choice}" =~ ^[0-9]+$ && \
           "${choice}" -ge 1 && "${choice}" -lt "${custom_idx}" ]]; then
        echo "${pairs[$((choice - 1))]}"
    else
        echo "Invalid choice." >/dev/tty
        return 1
    fi
}

# Prompt for the remote directory to mount.  Defaults to /home/<user>.
select_remote_dir() {
    local userhost="${1}"
    local remote_user="${userhost%%@*}"
    local default_remote="/home/${remote_user}"
    echo "" >/dev/tty
    echo "Remote directory on ${userhost}:" >/dev/tty
    echo -n "  Remote path [${default_remote}]: " >/dev/tty
    read -r remote </dev/tty
    echo "${remote:-${default_remote}}"
}

# Prompt for the local mountpoint.
# Default is ~/ssh_mount/<user>_<host> (dots replaced by underscores).
select_mountpoint() {
    local userhost="${1}"
    local safe_name
    safe_name="${userhost//@/_at_}"
    safe_name="${safe_name//./_}"
    local default_mount="${SSH_MOUNT_BASE}/${safe_name}"

    echo "" >/dev/tty
    echo "Local mountpoint:" >/dev/tty
    echo "  Default: ${default_mount}" >/dev/tty
    echo -n "  Mountpoint [${default_mount}]: " >/dev/tty
    read -r local_path </dev/tty

    local_path="${local_path:-${default_mount}}"
    # Expand leading tilde
    local_path="${local_path/#\~/$HOME}"
    echo "${local_path}"
}

# Full interactive mount wizard.
run_mount_wizard() {
    # Step 1: pick host
    local userhost
    if ! userhost=$(select_host); then
        return 0
    fi
    [[ -z "${userhost}" ]] && return 0

    # Step 2: remote dir
    local remote_dir
    remote_dir=$(select_remote_dir "${userhost}")

    # Step 3: local mountpoint
    local local_path
    local_path=$(select_mountpoint "${userhost}")

    # Step 4: confirm
    show_header
    echo "Mount Configuration" >/dev/tty
    echo "----------------------------------------" >/dev/tty
    echo "  Host:       ${userhost}" >/dev/tty
    echo "  Remote dir: ${remote_dir}" >/dev/tty
    echo "  Mountpoint: ${local_path}" >/dev/tty
    echo "" >/dev/tty
    echo -n "Proceed? [Y/n]: " >/dev/tty
    read -r confirm </dev/tty
    if [[ "${confirm}" == "n" || "${confirm}" == "N" ]]; then
        echo "Cancelled." >/dev/tty
        return 0
    fi

    # Step 5: create mountpoint directory
    if [[ ! -d "${local_path}" ]]; then
        echo "Creating mountpoint: ${local_path}" >/dev/tty
        mkdir -p "${local_path}"
    fi

    # Step 6: start systemd unit
    local instance="${userhost}:${remote_dir}:${local_path}"
    do_mount "${instance}"

    # Step 7: verify
    sleep 2
    if is_mounted "${instance}"; then
        echo "" >/dev/tty
        echo "✓ Mounted: ${userhost}:${remote_dir} → ${local_path}" >/dev/tty
        echo "" >/dev/tty
        # Step 8: offer to enable for autostart
        echo -n "Enable for automatic mount on login? [y/N]: " >/dev/tty
        read -r enable_choice </dev/tty
        if [[ "${enable_choice}" == "y" || "${enable_choice}" == "Y" ]]; then
            do_enable "${instance}"
            echo "✓ Unit enabled for autostart on login." >/dev/tty
        fi
    else
        local escaped
        escaped=$(escape_instance "${instance}")
        echo "" >/dev/tty
        echo "✗ Mount may have failed. Check the service log:" >/dev/tty
        echo "    journalctl --user -u ${SYSTEMD_UNIT_TEMPLATE}@${escaped}.service" >/dev/tty
    fi

    echo "" >/dev/tty
    echo "Press Enter to continue..." >/dev/tty
    read -r </dev/tty
}

# Interactive unmount: list active mounts and let the user pick one (or all).
run_umount_wizard() {
    local -a active=()
    mapfile -t active < <(list_active_instances)

    if [[ ${#active[@]} -eq 0 ]]; then
        show_header
        echo "No active SSHFS mounts." >/dev/tty
        echo "" >/dev/tty
        echo "Press Enter to continue..." >/dev/tty
        read -r </dev/tty
        return 0
    fi

    show_header
    echo "Active SSHFS Mounts" >/dev/tty
    echo "----------------------------------------" >/dev/tty
    echo "" >/dev/tty

    local i=1
    for instance in "${active[@]}"; do
        printf "  %d) %s\n" "${i}" "${instance}" >/dev/tty
        i=$((i + 1))
    done

    echo "" >/dev/tty
    echo -n "Stop which mount? [1-$((i-1))], [a]ll, or [b]ack: " >/dev/tty
    read -r choice </dev/tty

    case "${choice}" in
        b|back|B|Back)
            return 0
            ;;
        a|all|A)
            for instance in "${active[@]}"; do
                do_umount "${instance}" || true
            done
            ;;
        [0-9]*)
            local idx=$((choice - 1))
            if [[ ${idx} -ge 0 && ${idx} -lt ${#active[@]} ]]; then
                do_umount "${active[${idx}]}"
            else
                echo "Invalid choice." >/dev/tty
                sleep 0.5
            fi
            ;;
        *)
            echo "Invalid choice." >/dev/tty
            sleep 0.5
            ;;
    esac

    echo "" >/dev/tty
    echo "Press Enter to continue..." >/dev/tty
    read -r </dev/tty
}

# Display current SSHFS unit status via systemctl.
show_status() {
    show_header
    echo "SSHFS Mounts Status" >/dev/tty
    echo "----------------------------------------" >/dev/tty
    echo "" >/dev/tty
    systemctl --user list-units "${SYSTEMD_UNIT_TEMPLATE}@*.service" \
        --no-pager >/dev/tty 2>&1 || true
    echo "" >/dev/tty
    echo "Press Enter to continue..." >/dev/tty
    read -r </dev/tty
}

# ===== MAIN MENU =====

run_menu() {
    while true; do
        show_header
        echo "Options:" >/dev/tty
        echo "  1) Mount new SSHFS" >/dev/tty
        echo "  2) Unmount" >/dev/tty
        echo "  3) Status" >/dev/tty
        echo "  q) Quit" >/dev/tty
        echo "" >/dev/tty
        echo -n "Choose [1-3, q]: " >/dev/tty
        read -r choice </dev/tty

        case "${choice}" in
            1) run_mount_wizard ;;
            2) run_umount_wizard ;;
            3) show_status ;;
            q|Q|quit|exit) return 0 ;;
            *)
                echo "Invalid choice." >/dev/tty
                sleep 0.5
                ;;
        esac
    done
}

# ===== USAGE =====

show_help() {
    cat >&2 <<'EOF'
Usage: sshfs.bash [COMMAND]

Interactive SSHFS mount manager using systemd user template units.

COMMANDS:
  mount    Start the mount wizard (discover hosts, pick paths, start unit)
  umount   Stop one or all active SSHFS mounts
  status   Show all active sshfs@ systemd units
  help     Show this help

With no arguments in a terminal, opens the interactive menu.

SYSTEMD UNIT:
  sshfs@<escaped-instance>.service  (template: sshfs@.service)
  Instance format: user@host:/remote/path:/local/path

NETWORK FAILURE:
  sshfs-mount.sh monitors the mount.  If the SSH connection drops
  (ServerAliveInterval=5, ServerAliveCountMax=1 → ~10 s timeout)
  or the mount becomes unresponsive, the mount is unmounted and the
  unit exits.  systemd will attempt to restart it (RestartSec=30).

AUTOSTART:
  After a successful mount you will be prompted to enable the unit,
  which adds it to the default.target and remounts on next login.

DEFAULT MOUNTPOINT BASE:
  ~/ssh_mount/<user>_at_<host>
EOF
}

# ===== ENTRY POINT =====

case "${1:-}" in
    mount)
        run_mount_wizard
        ;;
    umount|unmount|stop)
        run_umount_wizard
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        if [[ -t 0 && -t 1 ]]; then
            run_menu
        else
            show_help
            exit 1
        fi
        ;;
    *)
        echo "Unknown command: ${1}" >&2
        show_help
        exit 1
        ;;
esac
