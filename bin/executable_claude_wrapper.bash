#!/bin/bash
# Lightweight, minimal-privilege wrapper for Claude CLI using bubblewrap.
# Uses the universal AI agent wrapper with claude-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjusted for test debugging with pytest-xdist and Playwright)
export RLIMIT_AS=unlimited                       # Unlimited for large models and WebAssembly
export RLIMIT_CPU=600                            # 600s = 10 minutes (for long test suites)
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=4096                         # High limit for parallel test workers and browser processes

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    echo "Claude CLI - Session Options:"
    echo "1) Start new conversation"
    echo "2) Resume from list (picker)"
    echo -n "Choose an option [1-2]: "
    read -r choice

    case "${choice}" in
        2)
            # Resume with interactive picker
            run_sandboxed_agent "claude" -- \
                --bind "${HOME}/.claude" "${HOME}/.claude" \
                --bind "${HOME}/.claude.json" "${HOME}/.claude.json" \
                -- --resume
            exit $?
            ;;
        1|*)
            # Start new conversation (default)
            ;;
    esac
fi

# Run claude with its specific binds
# Note: Added prlimit (was missing in original), removed incorrect /opt/cursor-agent ro-bind, Android is now a default bind
run_sandboxed_agent "claude" -- \
    --bind "${HOME}/.claude" "${HOME}/.claude" \
    --bind "${HOME}/.claude.json" "${HOME}/.claude.json" \
    -- "$@"

