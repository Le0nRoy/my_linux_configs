#!/bin/bash
# Helper Tmux Module - Tmux session management functions
# Depends on: common.bash (for TMUX_SESSION variable)

function tmux_ide_session() {
    # Create or attach to IDE-focused tmux session
    # Session name is based on current working directory
    local session_name
    session_name="$(basename "${PWD}")"

    # Check if session already exists (use '=' prefix for exact match)
    if tmux has-session -t "=${session_name}" 2>/dev/null; then
        # Attach to existing session
        tmux attach-session -t "=${session_name}" -d
        return 0
    fi

    # Create new session with first window "ai-agents"
    tmux new-session -d -s "${session_name}" -n "ai-agents"
    tmux split-window -d -h -t "${session_name}:ai-agents"

    tmux new-window -d -t "${session_name}" -n "dev"
    tmux split-window -d -h -t "${session_name}:dev"

    # Select the first pane and window before attaching
    tmux select-pane -t "${session_name}:ai-agents.0"
    tmux select-window -t "${session_name}:ai-agents"

    # Check if we have a controlling terminal (running in interactive shell vs called as script)
    if [[ -t 0 ]]; then
        # Interactive mode: attach in background to handle PyCharm's device queries
        tmux attach-session -t "=${session_name}" -d &
        local attach_pid=$!

        # Wait for terminal handshake to complete (PyCharm sends device queries on attach)
        sleep 0.3

        # Now send commands after terminal initialization is done
        # Use `C-u` (ctrl+u) to remove all special symbols, sent by IDE
        # Window 1 (ai-agents): left pane = claude, right pane = empty
        tmux send-keys -t "${session_name}:ai-agents.0" C-u
        tmux send-keys -t "${session_name}:ai-agents.0" "${HOME}/ai-wrapper/bin/claude_wrapper.bash"

        # Window 2 (dev): left pane = empty, right pane = git watch
        tmux send-keys -t "${session_name}:dev.1" "git_watch" C-m

        # Wait for attach process to complete
        wait "${attach_pid}" 2>/dev/null || true
    else
        # Called as script: just prepare commands and print instructions
        sleep 0.1
        # Window 1 (ai-agents): left pane = claude, right pane = empty
        tmux send-keys -t "${session_name}:ai-agents.0" C-u
        tmux send-keys -t "${session_name}:ai-agents.0" "${HOME}/ai-wrapper/bin/claude_wrapper.bash"

        # Window 2 (dev): left pane = empty, right pane = git watch
        tmux send-keys -t "${session_name}:dev.1" "git_watch" C-m

        echo "Session '${session_name}' created. To attach, run:"
        echo "  tmux attach-session -t '=${session_name}'"
    fi
}

function tmux_main_session() {
    # Create or attach to main tmux session with chezmoi and WorkSpace windows
    local session_name="${TMUX_SESSION:-tmux-main}"
    local chezmoi_dir="${HOME}/.local/share/chezmoi"
    local snapshot="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/resurrect/last"
    local restore_script="${HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

    # Check if session already exists (use '=' prefix for exact match)
    if tmux has-session -t "=${session_name}" 2>/dev/null; then
        # Attach to existing session
        tmux attach-session -t "=${session_name}" -d
        return 0
    fi

    # A saved resurrect snapshot wins over the hardcoded default layout.
    # LaunchAgent/systemd normally restores at login, so this branch
    # matters when the user invokes tmux_main_session after a manual
    # `tmux kill-server` or on a host without the service loaded.
    if [[ -e "${snapshot}" && -x "${restore_script}" ]]; then
        if ! tmux has-session 2>/dev/null; then
            # Create a throwaway session first: tmux < 3.2 requires a
            # live session for `run-shell` to work. PID-suffixed name
            # avoids colliding with a user session called _main_boot.
            local boot_session="_main_boot_$$"
            tmux new-session -d -s "${boot_session}"
            tmux run-shell "${restore_script}"
            # Always drop the bootstrap: if resurrect restored real
            # sessions, they remain and the empty _main_boot_$$ is just
            # noise; if it restored nothing, killing the bootstrap
            # makes has-session below return false and the default
            # layout builder runs. `|| true` covers the missing-target
            # case with no separate has-session guard.
            tmux kill-session -t "${boot_session}" 2>/dev/null || true
        fi
        if tmux has-session 2>/dev/null; then
            if tmux has-session -t "=${session_name}" 2>/dev/null; then
                tmux attach-session -t "=${session_name}" -d
            else
                tmux attach-session -d
            fi
            return 0
        fi
    fi

    # No snapshot on disk — build the hardcoded default layout.
    # Create new session with first window "chezmoi" in chezmoi directory
    tmux new-session -d -s "${session_name}" -n "chezmoi"

    # Split into 4 panes:
    # Layout: Top 50% (pane 0), Bottom left 50% (pane 1), Bottom right top 25% (pane 2), Bottom right bottom 25% (pane 3)

    # Split horizontally - top and bottom (50% each)
    tmux split-window -d -v -t "${session_name}:chezmoi" -l 50% -c "${chezmoi_dir}"
    # Split bottom pane vertically - left and right (50% each of bottom half)
    tmux split-window -d -h -t "${session_name}:chezmoi.1" -l 50% -c "${chezmoi_dir}"
    # Split right bottom pane horizontally - by some reason tmux makes it too small, so put 100% to bypass that behavior
    tmux split-window -d -v -t "${session_name}:chezmoi.2" -l 100% -c "${chezmoi_dir}"

    # Send commands to panes
    # Pane 0 (top 50%): cd to workdir and prepare claude_wrapper.bash to be executed
    tmux send-keys -t "${session_name}:chezmoi.0" "cd ${chezmoi_dir}" C-m C-l
    tmux send-keys -t "${session_name}:chezmoi.0" "${HOME}/ai-wrapper/bin/claude_wrapper.bash"

    # Pane 3 (bottom right bottom 50% of right quarter): watch git status (executed)
    tmux send-keys -t "${session_name}:chezmoi.3" "git_watch" C-m

    # Create second window "WorkSpace" with single pane
    tmux new-window -d -t "${session_name}" -n "WorkSpace"

    # Select the first pane of first window
    tmux select-window -t "${session_name}:chezmoi"
    tmux select-pane -t "${session_name}:chezmoi.0"

    # Attach to the session
    tmux attach-session -t "=${session_name}" -d
}

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
