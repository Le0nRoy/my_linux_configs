#!/bin/bash
# Lightweight, minimal-privilege wrapper for codex CLI using bubblewrap.
# Uses the universal AI agent wrapper with codex-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# No resource limits - agent is already sandboxed and should have full access within sandbox
export RLIMIT_AS=unlimited                       # Unlimited address space
export RLIMIT_CPU=unlimited                      # Unlimited CPU time
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=4096                         # High limit for parallel test workers and browser processes

# Bubblewrap (sandbox) flags - filesystem bindings
WRAPPER_FLAGS=( \
    --bind "${HOME}/.codex" "${HOME}/.codex" \
)

# Codex CLI flags - full autonomy within sandbox (no approvals needed)
CODEX_FLAGS=( \
    --dangerously-bypass-approvals-and-sandbox \
)

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    echo "Codex CLI - Session Options:"
    echo "1) Start new conversation"
    echo "2) Resume from list (picker)"
    echo "3) Resume last conversation"
    echo -n "Choose an option [1-3]: "
    read -r choice

    case "${choice}" in
        2)
            # Resume with picker
            run_sandboxed_agent "codex" -- "${WRAPPER_FLAGS[@]}" -- "${CODEX_FLAGS[@]}" resume
            exit $?
            ;;
        3)
            # Resume last conversation
            run_sandboxed_agent "codex" -- "${WRAPPER_FLAGS[@]}" -- "${CODEX_FLAGS[@]}" resume --last
            exit $?
            ;;
        1|*)
            # Start new conversation (default)
            ;;
    esac
fi

# Run codex with its specific binds
# AI rules (AGENTS.md and CLAUDE.md) are bound by default in universal wrapper
run_sandboxed_agent "codex" -- "${WRAPPER_FLAGS[@]}" -- "${CODEX_FLAGS[@]}" "$@"

