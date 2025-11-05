#!/bin/bash
# Lightweight, minimal-privilege wrapper for Cursor Agent CLI using bubblewrap.
# Uses the universal AI agent wrapper with cursor-agent-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjusted for test debugging with pytest-xdist and Playwright)
# Note: cursor-agent needs unlimited address space for WebAssembly modules
# We still limit CPU time and processes for security
export RLIMIT_AS=unlimited
export RLIMIT_CPU=600                            # 600s = 10 minutes (for long test suites)
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=256                          # For parallel test workers and browser processes

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
            run_sandboxed_agent "cursor-agent" -- \
                --ro-bind /opt/cursor-agent /opt/cursor-agent \
                --bind "${HOME}/.cursor" "${HOME}/.cursor" \
                --bind "${HOME}/.config/cursor" "${HOME}/.config/cursor" \
                --bind "${HOME}/.local/share/cursor-agent" "${HOME}/.local/share/cursor-agent" \
                -- --resume
            exit $?
            ;;
        3)
            # Resume last conversation - using --continue or similar flag
            run_sandboxed_agent "cursor-agent" -- \
                --ro-bind /opt/cursor-agent /opt/cursor-agent \
                --bind "${HOME}/.cursor" "${HOME}/.cursor" \
                --bind "${HOME}/.config/cursor" "${HOME}/.config/cursor" \
                --bind "${HOME}/.local/share/cursor-agent" "${HOME}/.local/share/cursor-agent" \
                -- --continue
            exit $?
            ;;
        1|*)
            # Start new conversation (default)
            ;;
    esac
fi

# Run cursor-agent with its specific binds
# Note: Added prlimit (was missing in original), Android is now a default bind
run_sandboxed_agent "cursor-agent" -- \
    --ro-bind /opt/cursor-agent /opt/cursor-agent \
    --bind "${HOME}/.cursor" "${HOME}/.cursor" \
    --bind "${HOME}/.config/cursor" "${HOME}/.config/cursor" \
    --bind "${HOME}/.local/share/cursor-agent" "${HOME}/.local/share/cursor-agent" \
    -- "$@"

