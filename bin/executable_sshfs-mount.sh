#!/usr/bin/env bash
# sshfs-mount.sh — SSHFS backend for the sshfs@.service systemd template unit.
#
# This script is NOT meant to be called directly by the user.
# Use ~/bin/sshfs.bash for interactive mount management.
#
# Usage:
#   sshfs-mount.sh start  <instance>    Mount the SSHFS share and monitor it.
#   sshfs-mount.sh stop   <instance>    Unmount the SSHFS share.
#
# Instance format: user@host:/remote/path:/local/path
#   user@host     — SSH connection target (alias from ~/.ssh/config works)
#   /remote/path  — Directory on the remote host to mount
#   /local/path   — Local mountpoint (must exist or be created beforehand)
#
# Network failure behaviour:
#   SSH keepalive (ServerAliveInterval=5 / ServerAliveCountMax=1) terminates
#   the connection within ~10 s of a network outage.  A background health
#   check additionally detects unresponsive (zombie) mounts and forces
#   unmounting.  systemd then restarts the unit (RestartSec=30).
#
# Example (manual test, not typical usage):
#   sshfs-mount.sh start  "alice@server.example.com:/home/alice:/mnt/alice"
#   sshfs-mount.sh stop   "alice@server.example.com:/home/alice:/mnt/alice"

set -euo pipefail

ACTION="${1:-}"
INSTANCE="${2:-}"

if [[ -z "${ACTION}" || -z "${INSTANCE}" ]]; then
    echo "Usage: $(basename "${0}") <start|stop> <user@host:/remote/path:/local/path>" >&2
    echo "See file header for full documentation." >&2
    exit 1
fi

# ===== PARSE INSTANCE =====
# Instance: user@host:/remote/path:/local/path
# Split on the LAST colon to extract local path, then on the NEXT-TO-LAST colon
# to split user@host from /remote/path.

REMOTE="${INSTANCE%:*}"          # user@host:/remote/path
LOCAL="${INSTANCE##*:}"          # /local/path

if [[ -z "${REMOTE}" || -z "${LOCAL}" ]]; then
    echo "ERROR: Invalid instance format." >&2
    echo "Expected: user@host:/remote/path:/local/path" >&2
    exit 1
fi

USERHOST="${REMOTE%:*}"          # user@host
REMOTEPATH="/${REMOTE#*/}"       # /remote/path

# Expand a leading tilde in the local path (systemd %h does not expand ~)
LOCAL="${LOCAL/#\~/$HOME}"

# ===== HEALTH CHECK FUNCTION =====
# Returns non-zero if the mountpoint is unresponsive (I/O hangs).
# Uses a generous timeout to avoid false positives on slow links.
check_mount_health() {
    local mountpoint="${1}"
    timeout 15 ls "${mountpoint}" &>/dev/null
}

# ===== ACTIONS =====

case "${ACTION}" in

    start)
        # Ensure mount directory exists
        if [[ ! -d "${LOCAL}" ]]; then
            mkdir -p "${LOCAL}" || {
                echo "ERROR: Failed to create mountpoint: ${LOCAL}" >&2
                exit 1
            }
        fi

        echo "Mounting ${USERHOST}:${REMOTEPATH} → ${LOCAL}"

        # Run SSHFS in foreground so systemd can track the process.
        # No 'reconnect': when the SSH connection drops, sshfs exits immediately
        # rather than blocking I/O.  systemd restarts the unit after RestartSec.
        sshfs -f \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=1 \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=no \
            -o idmap=user \
            "${USERHOST}:${REMOTEPATH}" "${LOCAL}" &
        SSHFS_PID=$!

        # Give sshfs a moment to establish the connection before monitoring.
        sleep 3

        if ! kill -0 "${SSHFS_PID}" 2>/dev/null; then
            echo "ERROR: sshfs failed to start (PID ${SSHFS_PID} already gone)" >&2
            exit 1
        fi

        echo "sshfs PID: ${SSHFS_PID}"

        # ===== MONITOR LOOP =====
        # Exit conditions (any will trigger unmount + exit 1 → systemd restart):
        #   1. sshfs process dies (SSH keepalive detected network loss)
        #   2. Mountpoint disappears from kernel
        #   3. Health check: mount is unresponsive for >15 s
        HEALTH_CHECK_INTERVAL=30   # run ls check every N seconds
        LOOP_SLEEP=5
        health_counter=0

        while kill -0 "${SSHFS_PID}" 2>/dev/null; do
            if ! mountpoint -q "${LOCAL}"; then
                echo "Mountpoint '${LOCAL}' disappeared — exiting monitor"
                break
            fi

            health_counter=$((health_counter + LOOP_SLEEP))
            if [[ ${health_counter} -ge ${HEALTH_CHECK_INTERVAL} ]]; then
                health_counter=0
                if ! check_mount_health "${LOCAL}"; then
                    echo "Mount '${LOCAL}' is unresponsive — forcing unmount"
                    kill "${SSHFS_PID}" 2>/dev/null || true
                    break
                fi
            fi

            sleep "${LOOP_SLEEP}"
        done

        echo "SSHFS process ended or mount lost — unmounting ${LOCAL}"
        fusermount3 -u "${LOCAL}" 2>/dev/null \
            || umount -f "${LOCAL}" 2>/dev/null \
            || true

        # Exit 1 so systemd treats this as a failure and restarts the unit.
        exit 1
        ;;

    stop)
        echo "Unmounting ${LOCAL}"
        if mountpoint -q "${LOCAL}"; then
            fusermount3 -u "${LOCAL}" 2>/dev/null \
                || umount -f "${LOCAL}" \
                || {
                    echo "ERROR: Failed to unmount ${LOCAL}" >&2
                    exit 1
                }
        else
            echo "${LOCAL} is not currently mounted"
        fi
        ;;

    *)
        echo "ERROR: Unknown action '${ACTION}'" >&2
        echo "Usage: $(basename "${0}") <start|stop> <user@host:/remote/path:/local/path>" >&2
        exit 1
        ;;
esac
