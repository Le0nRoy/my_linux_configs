#!/bin/bash
# Helper Backup Module - Backup and sync operations using rclone
# No dependencies

function rclone_systemd() {
    # Run rclone bisync with systemd logging
    # Validates all remotes are accessible before syncing
    for remote in $(rclone listremotes); do
        if ! rclone about "${remote}" > /dev/null 2>&1; then
            echo "Remote '${remote}' is not accessible. Aborting..."
            exit 1
        fi
    done

    echo "Executing rclone command:"
    printf 'rclone --log-systemd --log-level INFO --auto-confirm --human-readable --modify-window 24h bisync'
    printf ' %q' "$@"
    printf '\n'
    rclone --log-systemd --log-level INFO --auto-confirm --human-readable --modify-window 24h bisync "$@"
}

function rclone_to_backup() {
    # Backup source to destination with filters
    # Usage: rclone_to_backup <filters_file> <source_directory> <dest_directory>
    local filters_file="$1"
    local source="$2"
    local destination="$3"

    if [[ ! -f "${filters_file}" ]]; then
        echo "Usage: rclone_to_backup <filters_file> <source_directory> <dest_directory>"
        exit 1
    fi
    if [[ ! -d "${source}" || ! -d "${destination}" ]]; then
        echo "Usage: rclone_to_backup <filters_file> <source_directory> <dest_directory>"
        exit 1
    fi

    # In order to do resync use flag:
    # --resync-mode newer
    rclone --log-level INFO --auto-confirm --human-readable --modify-window 24h bisync --filters-file "${filters_file}" "${source}" "${destination}"
}
