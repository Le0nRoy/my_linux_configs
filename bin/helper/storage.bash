#!/bin/bash
# Helper Storage Module - Mount and unmount operations
# No dependencies

function hh_sshfsctl() {
    # Control SSHFS mounts via systemd
    # Usage: hh_sshfsctl [-h] [-r user@host] <start|stop|status|journal> <remote_path> <local_path>
    set -euo pipefail

    local usage="Usage: hh_sshfsctl [-h] [-r user@host] <start|stop|status|journal> <remote_path> <local_path>
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

function hh_gio_mount() {
    # Mount phone/device via GIO and change to mount point
    local phone_path
    phone_path="$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')"
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        gio mount "${phone_path}"
    fi
    local mount_point
    mount_point="$(gio info "${phone_path}" | awk '/local path/{print $3}')"
    cd "${mount_point}" || exit 1
}

function hh_gio_umount() {
    # Unmount phone/device via GIO
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
