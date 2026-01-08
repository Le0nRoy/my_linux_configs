#!/bin/bash
# Helper Tmux Module - Tmux session management functions
# Depends on: common.bash (for TMUX_SESSION variable)

function tmux_ide_session() {
    # Create or attach to IDE-focused tmux session
    # Session name is based on current working directory
    local session_name
    session_name="$(basename "${PWD}")"

    # Check if session already exists
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        # Attach to existing session
        tmux attach-session -t "${session_name}" -d
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
        tmux attach-session -t "${session_name}" -d &
        local attach_pid=$!

        # Wait for terminal handshake to complete (PyCharm sends device queries on attach)
        sleep 0.3

        # Now send commands after terminal initialization is done
        # Use `C-u` (ctrl+u) to remove all special symbols, sent by IDE
        # Window 1 (ai-agents): left pane = claude, right pane = empty
        tmux send-keys -t "${session_name}:ai-agents.0" C-u
        tmux send-keys -t "${session_name}:ai-agents.0" "${HOME}/bin/claude_wrapper.bash"

        # Window 2 (dev): left pane = empty, right pane = git watch
        tmux send-keys -t "${session_name}:dev.1" "watch 'git branch --show-current; git status --short'" C-m

        # Wait for attach process to complete
        wait "${attach_pid}" 2>/dev/null || true
    else
        # Called as script: just prepare commands and print instructions
        sleep 0.1
        # Window 1 (ai-agents): left pane = claude, right pane = empty
        tmux send-keys -t "${session_name}:ai-agents.0" C-u
        tmux send-keys -t "${session_name}:ai-agents.0" "${HOME}/bin/claude_wrapper.bash"

        # Window 2 (dev): left pane = empty, right pane = git watch
        tmux send-keys -t "${session_name}:dev.1" "watch 'git branch --show-current; git status --short'" C-m

        echo "Session '${session_name}' created. To attach, run:"
        echo "  tmux attach-session -t ${session_name}"
    fi
}

function tmux_main_session() {
    # Create or attach to main tmux session with chezmoi and WorkSpace windows
    local session_name="${TMUX_SESSION:-tmux-main}"
    local chezmoi_dir="${HOME}/.local/share/chezmoi"

    # Check if session already exists
    if tmux has-session -t "${session_name}" 2>/dev/null; then
        # Attach to existing session
        tmux attach-session -t "${session_name}" -d
        return 0
    fi

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
    tmux send-keys -t "${session_name}:chezmoi.0" "${HOME}/bin/claude_wrapper.bash"

    # Pane 3 (bottom right bottom 50% of right quarter): watch git status (executed)
    tmux send-keys -t "${session_name}:chezmoi.3" "watch 'git branch --show-current; git status --short'" C-m

    # Create second window "WorkSpace" with single pane
    tmux new-window -d -t "${session_name}" -n "WorkSpace"

    # Select the first pane of first window
    tmux select-window -t "${session_name}:chezmoi"
    tmux select-pane -t "${session_name}:chezmoi.0"

    # Attach to the session
    tmux attach-session -t "${session_name}" -d
}
