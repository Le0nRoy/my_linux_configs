#!/bin/bash
# Helper Tmux Shell-Plumbing Module - per-pane prompt/history callbacks
# Loaded by interactive helper.bash startup and by tmux.bash. Defines only
# the owner-approved _tmux_* callbacks and registers their prompt hooks.

# Record the last-typed shell command per tmux pane so tmux-resurrect's
# post-restore hook (bin/tmux_prefill_last_cmd.bash) can re-arm it after
# a snapshot restore. File mode 0600 — history may contain secrets.
function _tmux_log_last_cmd() {
    [[ -n "${TMUX:-}" ]] || return 0
    local id state
    id=$(tmux display-message -p '#S:#I.#P' 2>/dev/null) || return 0
    state="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
    mkdir -p "${state}"
    ( umask 077 && history 1 | sed 's/^ *[0-9]* *//' > "${state}/${id}.last" )
}

# Wire the logger into PROMPT_COMMAND once. Guard against a re-source of
# helper.bash duplicating the hook.
if [[ "${PROMPT_COMMAND:-}" != *_tmux_log_last_cmd* ]]; then
    PROMPT_COMMAND="_tmux_log_last_cmd${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}"
fi

# Per-pane bash history: each tmux pane keeps its own history file so an
# up-arrow after `tmux_restore` shows the commands run in THAT pane,
# not a shared global list. Deliberate tradeoff: commands typed inside
# tmux go only to the per-pane files, not to ~/.bash_history.
#
# Files are keyed by pane position (#S:#I.#P) because that is what
# resurrect restores. Positions shift during a session (closing a
# lower-index pane renumbers the rest; rename-session, swap-pane,
# move-pane), so _tmux_pane_hist_sync re-checks the position at every
# prompt and, when it changed, writes this shell's full history to the
# new position's file and releases the old one. A pane-exited hook in
# tmux.conf releases the file when a shell exits, so a new pane that
# later takes that position starts clean. See
# bin/tmux_pane_hist_release.bash for the ownership rules.
#
# No explicit `history -r`: bash reads $HISTFILE itself once .bashrc
# returns, and loading it here too would duplicate every entry.
function _tmux_pane_hist_path() {
    local id
    id=$(tmux display-message -p -t "${TMUX_PANE}" '#S:#I.#P' 2>/dev/null) || return 1
    [[ -n "${id}" ]] || return 1
    printf '%s/%s.bash_history' "${_TMUX_PANE_HIST_DIR}" "${id}"
}

function _tmux_pane_hist_claim() {
    ( umask 077 && : >> "${HISTFILE}" && printf '%s' "${HISTFILE}" > "${_TMUX_PANE_HIST_DIR}/.owner.${TMUX_PANE}" )
}

# Returns 0 only after a move, when it has already written the full
# history; the caller runs `history -a` otherwise.
function _tmux_pane_hist_sync() {
    local new old old_umask
    new=$(_tmux_pane_hist_path) || return 1
    [[ "${new}" == "${HISTFILE}" ]] && return 1
    old="${HISTFILE}"
    HISTFILE="${new}"
    old_umask=$(umask)
    umask 077
    history -w "${HISTFILE}"
    umask "${old_umask}"
    _tmux_pane_hist_claim
    "${HOME}/bin/tmux_pane_hist_release.bash" "${TMUX_PANE}" "${old}" 2>/dev/null || true
    return 0
}

if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" && -z "${_TMUX_PANE_HIST_DIR:-}" ]]; then
    _TMUX_PANE_HIST_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
    mkdir -p -m 700 "${_TMUX_PANE_HIST_DIR}"
    if _tmux_pane_hist_file=$(_tmux_pane_hist_path); then
        HISTFILE="${_tmux_pane_hist_file}"
        _tmux_pane_hist_claim
        # Follow the pane if it moved (full rewrite), otherwise append
        # the new command right away so a crash cannot lose it. Sync
        # must come first: after a swap-pane, `history -a` would append
        # to the old file, which another pane may already own. It is
        # skipped after a rewrite because `history -w` does not stop
        # `history -a` re-appending the latest command.
        PROMPT_COMMAND="_tmux_pane_hist_sync || history -a; ${PROMPT_COMMAND}"
    fi
    unset _tmux_pane_hist_file
fi
