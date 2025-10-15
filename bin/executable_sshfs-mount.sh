#!/usr/bin/env bash
# sshfs-mount.sh — clean SSHFS wrapper for systemd template units

set -euo pipefail

ACTION="${1:-}"
INSTANCE="${2:-}"

if [[ -z "${ACTION}" || -z "${INSTANCE}" ]]; then
    echo "Usage: $0 <start|stop> <instance>"
    exit 1
fi

# Split only on the *last* colon
REMOTE="${INSTANCE%:*}"
LOCAL="${INSTANCE##*:}"

if [[ -z "${REMOTE}" || -z "${LOCAL}" ]]; then
    echo "Invalid instance format. Expected: user@host:/remote/path:/local/path"
    exit 1
fi

USERHOST="${REMOTE%:*}"
REMOTEPATH="/${REMOTE#*/}"

# Expand tilde in local path
LOCAL="${LOCAL/#\~/$HOME}"

case "${ACTION}" in
    start)
        # Ensure mount directory exists
        if [[ ! -d "${LOCAL}" ]]; then
            mkdir -p "${LOCAL}" || {
                echo "Failed to create mount directory: ${LOCAL}"
                exit 1
            }
        fi

        echo "Mounting ${USERHOST}:${REMOTEPATH} → ${LOCAL}"
        # Run SSHFS in background and capture PID
        sshfs -f -o reconnect,ServerAliveInterval=5,ServerAliveCountMax=1,ConnectTimeout=5 \
            "${USERHOST}:${REMOTEPATH}" "${LOCAL}" &
        SSHFS_PID=$!
        sleep 5

        echo "sshfs PID: ${SSHFS_PID}"

        while kill -0 "${SSHFS_PID}" 2>/dev/null; do
            # Check if mount is still alive
            if ! mountpoint -q "${LOCAL}"; then
                echo "Mount '${LOCAL}' disappeared, exiting monitor"
                break
            fi
            sleep 5
        done

        echo "Host disconnected or SSHFS process ended, unmounting ${LOCAL}"
        fusermount3 -u "${LOCAL}" 2>/dev/null || umount -f "${LOCAL}" || true

        exit 1
        ;;
    stop)
        echo "Unmounting ${LOCAL}"
        if mountpoint -q "${LOCAL}"; then
            fusermount3 -u "${LOCAL}" 2>/dev/null || umount -f "${LOCAL}" || {
                echo "Failed to unmount ${LOCAL}"
                exit 1
            }
        else
            echo "${LOCAL} is not mounted"
        fi
        ;;

    *)
        echo "Invalid action: ${ACTION}"
        exit 1
        ;;
esac

