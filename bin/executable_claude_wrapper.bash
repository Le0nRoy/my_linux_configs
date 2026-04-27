#!/bin/bash
# Lightweight, minimal-privilege wrapper for Claude CLI using bubblewrap.
# Uses the universal AI agent wrapper with claude-specific configuration.
#
# Features:
# - Agent orchestration (plan → implement → test → review → merge)
# - Sandboxed execution with resource limits
# - Session resume support

source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

WRAPPER_DATA_DIR="$(dirname "${BASH_SOURCE[0]}")/ai_wrapper_data"
# Hard source — chezmoi guarantees the lib exists; no fallback needed.
source "${WRAPPER_DATA_DIR}/claude_wrapper_lib.bash"

# Configurable rlimits (adjusted for test debugging with pytest-xdist and Playwright)
export RLIMIT_AS=unlimited                       # Unlimited for large models and WebAssembly
export RLIMIT_CPU=unlimited                      # Unlimited CPU time
export RLIMIT_NOFILE=4096                        # Higher limit for browsers and test files
export RLIMIT_NPROC=4096                         # High limit for parallel test workers and browser processes

# Bubblewrap (sandbox) flags - filesystem bindings
WRAPPER_FLAGS=(
    --bind "${HOME}/.claude" "${HOME}/.claude"
    --bind "${HOME}/.claude.json" "${HOME}/.claude.json"
    --bind "/Data/Job/secrets/kuber/dot_kube_devenv" "${HOME}/.kube"
)

# Claude CLI flags - full autonomy within sandbox (no approvals needed)
AGENT_FLAGS=(
    --dangerously-skip-permissions
)

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    check_agent_binary
    action=$(show_main_menu)

    case "${action}" in
        orchestrate|bulletproof)
            run_orchestrated_session "${action}"
            exit $?
            ;;
        *)
            run_agent_session "${action}"
            exit $?
            ;;
    esac
fi

# Non-interactive mode or with arguments
# AI rules (AGENTS.md and CLAUDE.md) are bound by default in universal wrapper
run_sandboxed_agent "${AI_AGENT_COMMAND}" -- "${WRAPPER_FLAGS[@]}" -- "${AGENT_FLAGS[@]}" "$@"
