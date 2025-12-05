#!/bin/bash
# Lightweight, minimal-privilege wrapper for Cursor Agent CLI using bubblewrap.
# Uses the universal AI agent wrapper with cursor-agent-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# No resource limits - agent is already sandboxed and should have full access within sandbox
export RLIMIT_AS=unlimited                       # Unlimited address space
export RLIMIT_CPU=unlimited                      # Unlimited CPU time
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=4096                         # High limit for parallel test workers and browser processes

# Bubblewrap (sandbox) flags - filesystem bindings
WRAPPER_FLAGS=( \
    --ro-bind /opt/cursor-agent /opt/cursor-agent \
    --bind "${HOME}/.cursor" "${HOME}/.cursor" \
    --bind "${HOME}/.config/cursor" "${HOME}/.config/cursor" \
    --bind "${HOME}/.local/share/cursor-agent" "${HOME}/.local/share/cursor-agent" \
)

# Cursor Agent CLI flags - full autonomy within sandbox (no approvals needed)
CURSOR_FLAGS=( \
    --force \
)

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    echo "Cursor Agent - Session Options:"
    echo "1) Start new conversation"
    echo "2) Resume from list"
    echo "3) Resume last conversation"
    echo -n "Choose an option [1-3]: "
    read -r choice

    case "${choice}" in
        2)
            # Resume with picker - using --resume flag (common pattern)
            run_sandboxed_agent "cursor-agent" -- "${WRAPPER_FLAGS[@]}" -- "${CURSOR_FLAGS[@]}" --resume
            exit $?
            ;;
        3)
            # Resume last conversation - using --continue or similar flag
            run_sandboxed_agent "cursor-agent" -- "${WRAPPER_FLAGS[@]}" -- "${CURSOR_FLAGS[@]}" --continue
            exit $?
            ;;
        1|*)
            # Start new conversation (default)
            ;;
    esac
fi

# Run cursor-agent with its specific binds
# Note: Added prlimit (was missing in original), Android is now a default bind
# AI rules (AGENTS.md and CLAUDE.md) are bound by default in universal wrapper
run_sandboxed_agent "cursor-agent" -- "${WRAPPER_FLAGS[@]}" -- "${CURSOR_FLAGS[@]}" "$@"

