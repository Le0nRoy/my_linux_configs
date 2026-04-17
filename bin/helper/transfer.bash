#!/bin/bash
# Helper Transfer Module - File transfer utilities
# No dependencies

# ---------------------------------------------------------------------------
# rsync_ssh — transfer files to/from a remote host over SSH
# ---------------------------------------------------------------------------

function rsync_ssh() {
    # Send or receive files over SSH using rsync with a fast hardware-accelerated cipher.
    # Designed for high-throughput transfers on local networks (LAN / Wi-Fi).
    #
    # Usage: rsync_ssh [OPTIONS] <source> <user@host:/dest>
    #        rsync_ssh [OPTIONS] <user@host:/source> <dest>
    #
    # Options:
    #   -h          Show this help
    #   -n          Dry run: list what would be transferred without copying
    #   -z          Enable compression (useful for text/logs, skip for binaries)
    #   -p PORT     SSH port (default: 22)
    #   -c CIPHER   SSH cipher (default: aes128-gcm@openssh.com)
    #
    # Examples:
    #   rsync_ssh ./project/          alice@server:/home/alice/project/
    #   rsync_ssh -n ./docs/          bob@nas:/backup/docs/
    #   rsync_ssh -p 2222 ./logs/     user@host:/var/log/archive/
    #   rsync_ssh user@host:/data/    ./local-copy/

    local usage="Usage: rsync_ssh [OPTIONS] <source> <user@host:/dest>
       rsync_ssh [OPTIONS] <user@host:/source> <dest>

Options:
  -h          Show this help
  -n          Dry run (list files that would be transferred)
  -z          Enable compression (good for text, not for binaries)
  -p PORT     SSH port (default: 22)
  -c CIPHER   SSH cipher (default: aes128-gcm@openssh.com)

Ciphers (fastest first on modern hardware):
  aes128-gcm@openssh.com         (default — hardware AES-NI accelerated)
  chacha20-poly1305@openssh.com  (good on hardware without AES-NI)
  aes256-gcm@openssh.com
  aes128-ctr

Examples:
  rsync_ssh ./project/        alice@server:/home/alice/project/
  rsync_ssh -n ./docs/        bob@nas:/backup/docs/
  rsync_ssh -p 2222 -z ./src/ user@host:/backup/
  rsync_ssh user@host:/data/  ./local-copy/"

    local cipher="aes128-gcm@openssh.com"
    local port="22"
    local dry_run=0
    local compress=0

    local OPTIND opt
    while getopts ":hnzp:c:" opt; do
        case "${opt}" in
            h) echo "${usage}"; return 0 ;;
            n) dry_run=1 ;;
            z) compress=1 ;;
            p) port="${OPTARG}" ;;
            c) cipher="${OPTARG}" ;;
            :)
                echo "Error: option -${OPTARG} requires an argument" >&2
                echo "${usage}" >&2
                return 1
                ;;
            *)
                echo "Error: unknown option -${OPTARG}" >&2
                echo "${usage}" >&2
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ $# -lt 2 ]]; then
        echo "${usage}" >&2
        return 1
    fi

    local source="${1}"
    local dest="${2}"

    local -a flags=(-aH --info=progress2)
    [[ ${dry_run}  -eq 1 ]] && flags+=(--dry-run)
    [[ ${compress} -eq 1 ]] && flags+=(-z)

    rsync "${flags[@]}" -e "ssh -c ${cipher} -p ${port}" "${source}" "${dest}"
}

# ---------------------------------------------------------------------------
# rm_ssh — delete files/directories on a remote machine
# ---------------------------------------------------------------------------

function rm_ssh() {
    # Remove files or directories on a remote host via a single SSH connection.
    # All paths are deleted in one invocation — no per-file round-trips.
    #
    # Usage: rm_ssh [OPTIONS] <user@host> <remote-path> [path2 ...]
    #
    # Options:
    #   -h        Show this help
    #   -n        Dry run: list what would be deleted without removing
    #   -f        Force: skip the confirmation prompt
    #   -p PORT   SSH port (default: 22)
    #
    # Examples:
    #   rm_ssh alice@server /tmp/old-build
    #   rm_ssh -n bob@nas /data/cache /data/tmp
    #   rm_ssh -f -p 2222 user@host /var/log/old.log

    local usage="Usage: rm_ssh [OPTIONS] <user@host> <remote-path> [path2 ...]

Options:
  -h        Show this help
  -n        Dry run (list what would be deleted, no removal)
  -f        Force (skip confirmation prompt)
  -p PORT   SSH port (default: 22)

Examples:
  rm_ssh alice@server /tmp/old-build
  rm_ssh -n bob@nas /data/cache /data/tmp
  rm_ssh -f -p 2222 user@host /var/log/old.log"

    local port="22"
    local dry_run=0
    local force=0

    local OPTIND opt
    while getopts ":hnfp:" opt; do
        case "${opt}" in
            h) echo "${usage}"; return 0 ;;
            n) dry_run=1 ;;
            f) force=1 ;;
            p) port="${OPTARG}" ;;
            :)
                echo "Error: option -${OPTARG} requires an argument" >&2
                echo "${usage}" >&2
                return 1
                ;;
            *)
                echo "Error: unknown option -${OPTARG}" >&2
                echo "${usage}" >&2
                return 1
                ;;
        esac
    done
    shift $((OPTIND - 1))

    if [[ $# -lt 2 ]]; then
        echo "${usage}" >&2
        return 1
    fi

    local userhost="${1}"
    shift
    local -a paths=("$@")

    # Serialize paths safely for inclusion in a remote shell command.
    # printf '%q' produces shell-escaped tokens the remote bash will parse correctly.
    local serialized
    serialized=$(printf '%q ' "${paths[@]}")

    if [[ ${dry_run} -eq 1 ]]; then
        # Single SSH connection: list all matching paths with metadata
        ssh -p "${port}" "${userhost}" \
            "find ${serialized} -ls 2>/dev/null; \
             echo; \
             printf 'Total: '; find ${serialized} 2>/dev/null | wc -l; printf ' items\n'"
        return
    fi

    if [[ ${force} -eq 0 ]]; then
        echo "About to permanently delete on ${userhost}:"
        printf '  %s\n' "${paths[@]}"
        echo -n "Confirm? [y/N]: "
        read -r confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
            echo "Cancelled."
            return 0
        fi
    fi

    # Delete all paths in one SSH connection
    ssh -p "${port}" "${userhost}" "rm -rf -- ${serialized}"
}

alias cp_ssh='rsync_ssh'
