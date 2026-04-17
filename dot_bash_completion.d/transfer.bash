# Bash completion for transfer functions: rsync_ssh, cp_ssh, rm_ssh

# ---------------------------------------------------------------------------
# Internal: populate an array with SSH host entries from ~/.ssh/config.
# Emits "user@host" when User is set for a Host block, plain "host" otherwise.
# Skips wildcard patterns (* ?).
#
# Usage: _ssh_config_hosts <array_name>
# ---------------------------------------------------------------------------
_ssh_config_hosts() {
    local -n _out_array="${1}"
    [[ -f "${HOME}/.ssh/config" ]] || return 0

    local cur_host="" cur_user=""

    _flush() {
        [[ -z "${cur_host}" ]] && return
        [[ "${cur_host}" == *"*"* || "${cur_host}" == *"?"* ]] && return
        if [[ -n "${cur_user}" ]]; then
            _out_array+=("${cur_user}@${cur_host}")
        else
            _out_array+=("${cur_host}")
        fi
    }

    while IFS= read -r raw; do
        local line="${raw#"${raw%%[![:space:]]*}"}"   # strip leading whitespace
        [[ "${line}" == "#"* || -z "${line}" ]] && continue

        local kw="${line%% *}"
        local val="${line#* }"
        val="${val%% *}"   # first token only

        case "${kw,,}" in
            host) _flush; cur_host="${val}"; cur_user="" ;;
            user) cur_user="${val}" ;;
        esac
    done < "${HOME}/.ssh/config"
    _flush
}

# ---------------------------------------------------------------------------
# Bash completion for rsync_ssh / cp_ssh
# ---------------------------------------------------------------------------

_rsync_ssh_complete() {
    local cur prev
    _init_completion || return

    case "${prev}" in
        -c)
            COMPREPLY=($(compgen -W \
                "aes128-gcm@openssh.com chacha20-poly1305@openssh.com \
                 aes256-gcm@openssh.com aes128-ctr aes256-ctr aes192-ctr" \
                -- "${cur}"))
            return
            ;;
        -p) return ;;
    esac

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "-h -n -z -p -c" -- "${cur}"))
        return
    fi

    # After colon: remote path — would need an SSH round-trip, skip
    if [[ "${cur}" == *:* ]]; then
        return
    fi

    local -a ssh_hosts=()
    _ssh_config_hosts ssh_hosts

    _filedir
    [[ ${#ssh_hosts[@]} -gt 0 ]] && \
        COMPREPLY+=($(compgen -W "${ssh_hosts[*]}" -- "${cur}"))
}

complete -F _rsync_ssh_complete rsync_ssh
complete -F _rsync_ssh_complete cp_ssh

# ---------------------------------------------------------------------------
# Bash completion for rm_ssh
# ---------------------------------------------------------------------------

_rm_ssh_complete() {
    local cur prev
    _init_completion || return

    case "${prev}" in
        -p) return ;;
    esac

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "-h -n -f -p" -- "${cur}"))
        return
    fi

    # Count positional (non-flag) words already typed to determine context.
    # words[0] is the command itself; we need to know if user@host was given.
    local positional=0
    local w
    for w in "${words[@]:1:${cword}-1}"; do
        [[ "${w}" == -* ]] && continue
        # Skip values consumed by flags that take an argument
        positional=$((positional + 1))
    done

    if [[ ${positional} -eq 0 ]]; then
        # First positional: the SSH target (user@host)
        local -a ssh_hosts=()
        _ssh_config_hosts ssh_hosts
        [[ ${#ssh_hosts[@]} -gt 0 ]] && \
            COMPREPLY=($(compgen -W "${ssh_hosts[*]}" -- "${cur}"))
    fi
    # Subsequent positionals are remote paths — no completion without SSH round-trip
}

complete -F _rm_ssh_complete rm_ssh
