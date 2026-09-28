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
# not a shared global list. Deliberate tradeoff: commands typed inside
# tmux go only to the per-pane files, not to ~/.zsh_history.
#
# Same position tracking as the bash side (bin/helper/tmux.bash): the
# file is keyed by #S:#I.#P, re-checked at every prompt, and released
# via bin/tmux_pane_hist_release.bash when the pane moves or exits.
#
# No explicit `fc -R`: zsh reads $HISTFILE itself once .zshrc returns,
# and loading it here too would duplicate every entry.
_tmux_pane_hist_path() {
    local id
    id=$(tmux display-message -p -t "${TMUX_PANE}" '#S:#I.#P' 2>/dev/null) || return 1
    [[ -n "${id}" ]] || return 1
    print -r -- "${_TMUX_PANE_HIST_DIR}/${id}.zsh_history"
}

_tmux_pane_hist_claim() {
    ( umask 077 && : >> "${HISTFILE}" && print -rn -- "${HISTFILE}" > "${_TMUX_PANE_HIST_DIR}/.owner.${TMUX_PANE}" )
}

# Point $HISTFILE at the pane's current position. Returns 0 when the
# pane moved; the file it moved away from waits in _tmux_pane_hist_old
# until _tmux_pane_hist_sync writes the new file and releases the old.
_tmux_pane_hist_detect() {
    local new
    new=$(_tmux_pane_hist_path) || return 1
    [[ "${new}" == "${HISTFILE}" ]] && return 1
    : "${_tmux_pane_hist_old:=${HISTFILE}}"
    HISTFILE="${new}"
}

# zshaddhistory hook. INC_APPEND_HISTORY writes each line right after
# this hook, before precmd — so the first command after a swap-pane
# would land in a file another pane now owns. On a move, return 2:
# keep the line in memory, skip the file write; precmd then writes the
# full history. (fc -W is not used here: inside this hook it drops the
# entry before the current line.)
_tmux_pane_hist_addhistory() {
    _tmux_pane_hist_detect && return 2
    return 0
}

_tmux_pane_hist_sync() {
    _tmux_pane_hist_detect
    [[ -n "${_tmux_pane_hist_old:-}" ]] || return 0
    ( umask 077 && fc -W "${HISTFILE}" )
    _tmux_pane_hist_claim
    "${HOME}/bin/tmux_pane_hist_release.bash" "${TMUX_PANE}" "${_tmux_pane_hist_old}" 2>/dev/null || true
    unset _tmux_pane_hist_old
}

if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" && -z "${_TMUX_PANE_HIST_DIR:-}" ]]; then
    _TMUX_PANE_HIST_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
    mkdir -p -m 700 "${_TMUX_PANE_HIST_DIR}"
    if _tmux_pane_hist_file=$(_tmux_pane_hist_path); then
        HISTFILE="${_tmux_pane_hist_file}"
        _tmux_pane_hist_claim
        # Persist every command immediately so a crash cannot lose it.
        setopt INC_APPEND_HISTORY
        # precmd writes the file after a move (and keeps an idle pane's
        # file current for the next resurrect save); zshaddhistory keeps
        # the first post-move line out of the old file. (Ie) form, not
        # the (ie)/-gt guard above: it also works when the hook array is
        # still unset (zshaddhistory_functions usually is).
        (( ${precmd_functions[(Ie)_tmux_pane_hist_sync]} )) \
            || precmd_functions+=(_tmux_pane_hist_sync)
        (( ${zshaddhistory_functions[(Ie)_tmux_pane_hist_addhistory]} )) \
            || zshaddhistory_functions+=(_tmux_pane_hist_addhistory)
    fi
    unset _tmux_pane_hist_file
fi
