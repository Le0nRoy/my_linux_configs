#!/bin/bash
# Lightweight, minimal-privilege wrapper for Claude CLI using bubblewrap.
# Uses the universal AI agent wrapper with claude-specific configuration.
#
# Features:
# - Agent orchestration (plan → implement → test → review → merge)
# - Sandboxed execution with resource limits
# - Session resume support

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Source the menu library from data directory (not directly in PATH)
WRAPPER_DATA_DIR="$(dirname "${BASH_SOURCE[0]}")/claude_wrapper_data"
WRAPPER_LIB="${WRAPPER_DATA_DIR}/claude_wrapper_lib.bash"
if [[ -f "${WRAPPER_LIB}" ]]; then
    source "${WRAPPER_LIB}"
    MENU_AVAILABLE=1
else
    MENU_AVAILABLE=0
fi

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
CLAUDE_FLAGS=(
    --dangerously-skip-permissions
)

# Function to run claude with selected options
run_claude_session() {
    local action="${1}"
    shift
    local -a extra_claude_flags=("$@")

    case "${action}" in
        resume)
            run_sandboxed_agent "claude" -- "${WRAPPER_FLAGS[@]}" -- "${CLAUDE_FLAGS[@]}" "${extra_claude_flags[@]}" --resume
            ;;
        start|*)
            run_sandboxed_agent "claude" -- "${WRAPPER_FLAGS[@]}" -- "${CLAUDE_FLAGS[@]}" "${extra_claude_flags[@]}"
            ;;
    esac
}

# Function to run an orchestrated session
# Builds the orchestrator system prompt with role assignments and launches Claude
run_orchestrated_session() {
    # Build the orchestrator system prompt with role assignments
    local prompt_content
    if [[ "${ORCHESTRATION_MODE:-custom}" == "bulletproof" ]]; then
        prompt_content=$(build_bulletproof_prompt)
    else
        prompt_content=$(build_orchestrator_prompt)
    fi
    if [[ $? -ne 0 || -z "${prompt_content}" ]]; then
        echo "ERROR: Failed to build orchestrator prompt." >&2
        return 1
    fi

    # Write to temp file for --append-system-prompt
    local prompt_file="/tmp/claude-orchestrator-$$.md"
    echo "${prompt_content}" > "${prompt_file}"

    # Build additional flags from any MCP selections
    local -a extra_flags=()
    mapfile -t extra_flags < <(build_claude_flags)

    # Launch Claude with the orchestrator prompt appended
    run_sandboxed_agent "claude" -- "${WRAPPER_FLAGS[@]}" -- \
        "${CLAUDE_FLAGS[@]}" "${extra_flags[@]}" \
        --append-system-prompt "$(cat "${prompt_file}")"
}

# Interactive session selection (only if no arguments provided and stdin/stdout are terminals)
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    if [[ ${MENU_AVAILABLE} -eq 1 ]]; then
        # Use the full menu system
        action=$(run_menu_system)

        case "${action}" in
            orchestrate)
                run_orchestrated_session
                exit $?
                ;;
            *)
                # Build additional flags from selections
                mapfile -t extra_flags < <(build_claude_flags)
                run_claude_session "${action}" "${extra_flags[@]}"
                exit $?
                ;;
        esac
    else
        # Fallback to simple menu if library not available
        echo "Claude CLI - Session Options:"
        echo "1) Start new conversation"
        echo "2) Resume from list (picker)"
        echo -n "Choose an option [1-2]: "
        read -r choice

        case "${choice}" in
            2)
                run_claude_session "resume"
                exit $?
                ;;
            1|*)
                run_claude_session "start"
                exit $?
                ;;
        esac
    fi
fi

# Run claude with its specific binds (non-interactive mode or with arguments)
# Note: Added prlimit (was missing in original), removed incorrect /opt/cursor-agent ro-bind, Android is now a default bind
# AI rules (AGENTS.md and CLAUDE.md) are bound by default in universal wrapper
run_sandboxed_agent "claude" -- "${WRAPPER_FLAGS[@]}" -- "${CLAUDE_FLAGS[@]}" "$@"
