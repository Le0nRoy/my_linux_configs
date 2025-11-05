#!/bin/bash
# Lightweight, minimal-privilege wrapper for codex CLI using bubblewrap.
# Uses the universal AI agent wrapper with codex-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjusted for test debugging with pytest-xdist and Playwright)
export RLIMIT_AS=$((16 * 1024 * 1024 * 1024))   # 16 GiB (for browser instances)
export RLIMIT_CPU=600                            # 600s = 10 minutes (for long test suites)
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=256                          # For parallel test workers and browser processes

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    echo "Codex CLI - Session Options:"
    echo "1) Start new conversation"
    echo "2) Resume from list (picker)"
    echo "3) Resume last conversation"
    echo -n "Choose an option [1-3]: "
    read -r choice

    case "$choice" in
        2)
            # Resume with picker
            run_sandboxed_agent "codex" -- \
                --bind "${HOME}/.codex" "${HOME}/.codex" \
                -- resume
            ;;
        3)
            # Resume last conversation
            run_sandboxed_agent "codex" -- \
                --bind "${HOME}/.codex" "${HOME}/.codex" \
                -- resume --last
            ;;
        1|*)
            # Run codex with its specific binds
            run_sandboxed_agent "codex" -- \
                --bind "${HOME}/.codex" "${HOME}/.codex" \
                -- "$@"
            ;;
    esac
fi

