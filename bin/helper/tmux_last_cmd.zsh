# zsh side of the tmux last-command logger. Sourced by dot_zshrc.
# Bash counterpart lives in bin/helper/tmux.bash (loaded through
# bin/helper.bash). File mode 0600 — history may contain secrets.

_tmux_log_last_cmd() {
    [[ -n "${TMUX:-}" ]] || return 0
    local id state
    id=$(tmux display-message -p '#S:#I.#P' 2>/dev/null) || return 0
    state="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
    mkdir -p "${state}"
    ( umask 077 && fc -ln -1 > "${state}/${id}.last" )
}

# Guard against re-source duplicating the hook.
if [[ ${precmd_functions[(ie)_tmux_log_last_cmd]} -gt ${#precmd_functions} ]]; then
    precmd_functions+=(_tmux_log_last_cmd)
fi
