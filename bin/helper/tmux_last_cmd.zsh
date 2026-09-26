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

# Per-pane zsh history: each tmux pane keeps its own history file so an
# up-arrow after `tmux_restore` shows the commands run in THAT pane,
# not a shared global list. Relies on the pane id (#S:#I.#P) staying
# stable across resurrect restore.
if [[ -n "${TMUX:-}" ]] && ! [[ -o INC_APPEND_HISTORY ]]; then
    _tmux_pane_id=$(tmux display-message -p '#S:#I.#P' 2>/dev/null || true)
    if [[ -n "${_tmux_pane_id}" ]]; then
        _tmux_pane_state="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
        mkdir -p "${_tmux_pane_state}"
        HISTFILE="${_tmux_pane_state}/${_tmux_pane_id}.zsh_history"
        # Load prior history for this pane if any.
        [[ -r "${HISTFILE}" ]] && fc -R "${HISTFILE}"
        # Persist every command immediately so a crash cannot lose it.
        setopt INC_APPEND_HISTORY
    fi
    unset _tmux_pane_id _tmux_pane_state
fi
