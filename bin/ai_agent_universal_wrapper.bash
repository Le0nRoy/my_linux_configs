#!/bin/bash
# Universal bubblewrap + prlimit wrapper for AI agents
# This function provides sandboxing with minimal privileges and resource limits.
#
# Required environment variables (set by caller):
#   RLIMIT_AS      - Address space limit in bytes
#   RLIMIT_CPU     - CPU time limit in seconds
#   RLIMIT_NOFILE  - File descriptor limit
#   RLIMIT_NPROC   - Process limit
#
# Optional environment variables:
#   BWRAP_STRICT   - If set to 1, fail on missing bind paths (default: warn only)
#
# Usage:
#   run_sandboxed_agent COMMAND -- [BWRAP_FLAGS...] -- [CMD_ARGS...]
#
# Example:
#   RLIMIT_AS=$((4*1024*1024*1024)) RLIMIT_CPU=60 RLIMIT_NOFILE=1024 RLIMIT_NPROC=60 \
#   run_sandboxed_agent "codex" -- --bind "${HOME}/.codex" "${HOME}/.codex" -- "$@"

function echo_log() {
    local log_level="${1}"
    shift
    local message="$*"
    echo -e "[$(date "+%F %T")] ${log_level}: ${message}" >&2
}

run_sandboxed_agent() {
    local agent_name="${1}"
    local command="${1}"
    shift

    # ===== PRE-FLIGHT VALIDATION =====

    # Check required commands exist
    local missing_commands=()
    for cmd in bwrap prlimit setpriv sysctl; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing_commands+=("${cmd}")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        echo_log "ERROR" "[$agent_name] Required commands not found: ${missing_commands[*]}"
        echo_log "ERROR" "Please install: bubblewrap, util-linux, util-linux-core (or equivalent)"
        exit 127
    fi

    # Validate required environment variables
    if [[ -z "${RLIMIT_AS}" || -z "${RLIMIT_CPU}" || -z "${RLIMIT_NOFILE}" || -z "${RLIMIT_NPROC}" ]]; then
        echo_log "ERROR" "[$agent_name] Required environment variables not set."
        echo_log "ERROR" "Please set: RLIMIT_AS, RLIMIT_CPU, RLIMIT_NOFILE, RLIMIT_NPROC"
        exit 1
    fi

    # Check if user namespaces are enabled
    UNPRIVILEGED_USERNS_CLONE="$(sysctl kernel.unprivileged_userns_clone 2>/dev/null | awk -F ' = ' '{print $2}')"
    if [[ -z "${UNPRIVILEGED_USERNS_CLONE}" ]]; then
        echo_log "ERROR" "[$agent_name] Failed to check user namespace support."
        echo_log "ERROR" "Cannot read 'sysctl kernel.unprivileged_userns_clone'."
        exit 1
    elif [[ "${UNPRIVILEGED_USERNS_CLONE}" -ne 1 ]]; then
        echo_log "ERROR" "[$agent_name] User namespaces are not enabled."
        echo_log "ERROR" "Please set 'kernel.unprivileged_userns_clone = 1' in '/etc/sysctl.d/00-unpriv-ns.conf'"
        echo_log "ERROR" "and run 'sudo sysctl --system' to fix it."
        exit 1
    fi

    # Validate command specified
    if [[ -z "${command}" ]]; then
        echo_log "ERROR" "[$agent_name] No command specified."
        echo_log "ERROR" "Usage: run_sandboxed_agent COMMAND -- [BWRAP_FLAGS...] -- [CMD_ARGS...]"
        exit 1
    fi

    # Verify command exists
    if ! command -v "${command}" &>/dev/null; then
        echo_log "ERROR" "[${agent_name}] Command not found: ${command}"
        echo_log "ERROR" "Please ensure '${command}' is installed and in PATH."
        exit 127
    fi

    # Skip the separator "--" between command and bwrap flags
    if [[ "${1}" == "--" ]]; then
        shift
    fi

    # Parse extra bwrap flags (until next --)
    local -a extra_bwrap_flags=()
    while [[ $# -gt 0 && "${1}" != "--" ]]; do
        extra_bwrap_flags+=("${1}")
        shift
    done

    # Skip the separator "--" between bwrap flags and command args
    if [[ "${1}" == "--" ]]; then
        shift
    fi

    # Remaining args are command arguments
    local -a cmd_args=("$@")

    # Setup paths
    WORKDIR="$(pwd)"
    HOME_DIR="${HOME}"

    # Validate critical paths
    if [[ ! -d "${HOME_DIR}" ]]; then
        echo_log "ERROR" "[$agent_name] HOME directory does not exist: ${HOME_DIR}"
        exit 1
    fi

    if [[ ! -d "${WORKDIR}" ]]; then
        echo_log "ERROR" "[$agent_name] Working directory does not exist: ${WORKDIR}"
        exit 1
    fi

    # ===== PATH VALIDATION FOR BIND MOUNTS =====

    # Validate and filter paths in extra_bwrap_flags
    local strict_mode="${BWRAP_STRICT:-0}"
    local -a validated_bwrap_flags=()
    local i=0
    local bind_errors=0

    while [[ ${i} -lt ${#extra_bwrap_flags[@]} ]]; do
        local flag="${extra_bwrap_flags[$i]}"

        # Check if this is a bind flag that requires path validation
        if [[ "${flag}" =~ ^--(ro-)?bind$ ]]; then
            local src_path="${extra_bwrap_flags[$((i+1))]}"
            local dst_path="${extra_bwrap_flags[$((i+2))]}"

            if [[ -n "${src_path}" && ! "${src_path}" =~ ^-- ]]; then
                if [[ ! -e "${src_path}" ]]; then
                    if [[ "${strict_mode}" == "1" ]]; then
                        echo_log "ERROR" "[$agent_name] Bind source path does not exist: ${src_path}"
                        bind_errors=$((bind_errors + 1))
                        # Skip this bind in strict mode (will exit after loop)
                        i=$((i + 3))
                        continue
                    else
                        echo_log "WARNING" "[$agent_name] Bind source path does not exist (skipping): ${src_path}"
                        # Skip this bind mount entirely
                        i=$((i + 3))
                        continue
                    fi
                fi
            fi

            # Path exists or is special, add all three arguments
            validated_bwrap_flags+=("${flag}" "${src_path}" "${dst_path}")
            i=$((i + 3))
        else
            # Not a bind flag, just add it
            validated_bwrap_flags+=("${flag}")
            i=$((i + 1))
        fi
    done

    if [[ ${bind_errors} -gt 0 ]]; then
        echo_log "ERROR" "[$agent_name] ${bind_errors} bind path(s) missing. Set BWRAP_STRICT=0 to continue with warnings."
        exit 1
    fi

    # Build bwrap arguments
    local -a bwrap_args=(
        --die-with-parent
        --unshare-all
        --share-net
        # Common read-only system binds
        --ro-bind /usr /usr
        --ro-bind /bin /bin
        --ro-bind /lib /lib
        --ro-bind /lib64 /lib64
        --ro-bind /etc /etc
        --ro-bind /etc/ssl /etc/ssl
        --ro-bind /etc/hosts /etc/hosts
        --ro-bind /etc/resolv.conf /etc/resolv.conf
        --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf
        # Virtual filesystems
        --tmpfs /tmp
        --proc /proc
        --dev /dev
        # Working directory (read-write)
        --bind "${WORKDIR}" "${WORKDIR}"
    )

    # Add default Android directory if it exists
    if [[ -d "${HOME_DIR}/Android" ]]; then
        bwrap_args+=(--bind "${HOME_DIR}/Android" "${HOME_DIR}/Android")
    fi

    # Add /run for network services and systemd-resolved (for localhost connectivity)
    if [[ -d /run ]]; then
        bwrap_args+=(--ro-bind /run /run)
    elif [[ -d /var/run ]]; then
        bwrap_args+=(--ro-bind /var/run /var/run)
    fi

    # Add extra bwrap flags (user-specified binds, etc.) - using validated flags
    bwrap_args+=("${validated_bwrap_flags[@]}")

    # Environment and working directory
    bwrap_args+=(
        --clearenv
        --setenv HOME "${HOME_DIR}"
        --setenv USER "${USER}"
        --setenv PATH "/usr/bin:/usr/sbin:/bin:/sbin"
        --setenv LANG "${LANG:-en_US.UTF-8}"
        --setenv TERM "${TERM:-xterm-256color}"
        --chdir "${WORKDIR}"
    )

    # Pass through additional terminal-related variables if set (for better terminal support)
    [[ -n "${COLORTERM}" ]] && bwrap_args+=(--setenv COLORTERM "${COLORTERM}")
    [[ -n "${TERM_PROGRAM}" ]] && bwrap_args+=(--setenv TERM_PROGRAM "${TERM_PROGRAM}")

    # ===== EXECUTE WITH EXIT CODE TRANSLATION =====

    # Execute with reduced privileges and resource limits
    setpriv --no-new-privs --inh-caps=-all \
        bwrap "${bwrap_args[@]}" \
        /usr/bin/env prlimit \
            --as="${RLIMIT_AS}" \
            --cpu="${RLIMIT_CPU}" \
            --nofile="${RLIMIT_NOFILE}" \
            --nproc="${RLIMIT_NPROC}" \
            "${command}" "${cmd_args[@]}"

    local exit_code=$?

    # ===== EXIT CODE TRANSLATION & FEEDBACK =====

    if [[ ${exit_code} -eq 0 ]]; then
        return 0
    fi

    # Translate common prlimit/signal exit codes
    case ${exit_code} in
        137)
            echo_log "ERROR" "[$agent_name] Process killed (exit code 137)"
            echo_log "ERROR" "Possible causes:"
            echo_log "ERROR" "  - CPU time limit exceeded (RLIMIT_CPU=${RLIMIT_CPU}s)"
            echo_log "ERROR" "  - Process limit exceeded (RLIMIT_NPROC=${RLIMIT_NPROC})"
            echo_log "ERROR" "  - Out of memory or address space (RLIMIT_AS=$((RLIMIT_AS / 1024 / 1024))MB)"
            echo_log "ERROR" "Consider increasing resource limits if legitimate usage."
            ;;
        139)
            echo_log "ERROR" "[$agent_name] Segmentation fault (exit code 139)"
            echo_log "ERROR" "The process crashed. This may indicate:"
            echo_log "ERROR" "  - A bug in ${command}"
            echo_log "ERROR" "  - Incompatible sandbox environment"
            echo_log "ERROR" "  - Missing required files or libraries"
            ;;
        143)
            echo_log "ERROR" "[$agent_name] Process terminated (SIGTERM, exit code 143)"
            echo_log "ERROR" "The process was terminated, possibly due to:"
            echo_log "ERROR" "  - Resource limits (RLIMIT_CPU=${RLIMIT_CPU}s)"
            echo_log "ERROR" "  - External termination signal"
            ;;
        127)
            echo_log "ERROR" "[$agent_name] Command not found inside sandbox (exit code 127)"
            echo_log "ERROR" "The command '${command}' could not be executed in the sandbox."
            echo_log "ERROR" "This usually means required binaries or libraries are missing from bind mounts."
            ;;
        126)
            echo_log "ERROR" "[$agent_name] Command not executable (exit code 126)"
            echo_log "ERROR" "The command '${command}' exists but cannot be executed."
            echo_log "ERROR" "Check file permissions and executable bit."
            ;;
        *)
            # For other non-zero exits, just report the code
            if [[ ${exit_code} -gt 128 ]]; then
                local signal=$((exit_code - 128))
                echo_log "ERROR" "[$agent_name] Process terminated by signal ${signal} (exit code ${exit_code})"
            else
                echo_log "ERROR" "[$agent_name] Process exited with code ${exit_code}"
            fi
            ;;
    esac

    return ${exit_code}
}

# If script is executed directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo_log "ERROR" "This script is meant to be sourced, not executed directly."
    echo_log "ERROR" ""
    echo_log "ERROR" "Usage example:"
    echo_log "ERROR" "  source ai_agent_universal_wrapper.bash"
    echo_log "ERROR" "  RLIMIT_AS=\$((4*1024*1024*1024)) RLIMIT_CPU=60 RLIMIT_NOFILE=1024 RLIMIT_NPROC=60 \\"
    echo_log "ERROR" "    run_sandboxed_agent \"mycommand\" -- --bind \"\${HOME}/.config\" \"\${HOME}/.config\" -- arg1 arg2"
    exit 1
fi
