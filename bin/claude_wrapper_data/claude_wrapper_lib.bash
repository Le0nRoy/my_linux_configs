#!/bin/bash
# Claude Wrapper Library - Menu functions for claude_wrapper.bash
#
# Provides an interactive menu for session management and orchestration mode
# selection. Sourced by executable_claude_wrapper.bash — not executed directly.

# ===== CONSTANTS =====

# Configuration paths - WRAPPER_DATA_DIR is set by the wrapper before sourcing
WRAPPER_DATA_DIR="${WRAPPER_DATA_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
WRAPPER_HELP="${WRAPPER_DATA_DIR}/wrapper-help.md"
ORCHESTRATOR_PROMPT="${WRAPPER_DATA_DIR}/orchestrator-prompt.md"
BULLETPROOF_PROMPT="${WRAPPER_DATA_DIR}/bulletproof-prompt.md"

# ===== UTILITY FUNCTIONS =====

# Log message to stderr
wrapper_log() {
    local level="${1}"
    shift
    echo -e "[claude-wrapper] ${level}: $*" >&2
}

# ===== MENU DISPLAY =====
# All menu output goes to /dev/tty to avoid capture by $() subshells

# Clear screen and show header
show_header() {
    clear >/dev/tty
    echo "==========================================" >/dev/tty
    echo "       Claude CLI - Session Options      " >/dev/tty
    echo "==========================================" >/dev/tty
    echo "" >/dev/tty
}

# Display help from wrapper-help.md (falls back to inline text)
display_help() {
    show_header

    if [[ -f "${WRAPPER_HELP}" ]]; then
        if command -v less &>/dev/null; then
            less "${WRAPPER_HELP}" </dev/tty >/dev/tty
        else
            cat "${WRAPPER_HELP}" >/dev/tty
        fi
    else
        echo "Claude CLI Wrapper" >/dev/tty
        echo "" >/dev/tty
        echo "Options:" >/dev/tty
        echo "  Orchestration - Multi-phase dev workflow (orchestrator-mode skill)" >/dev/tty
        echo "  Bulletproof   - 12-stage verified dev workflow (bulletproof skill)" >/dev/tty
        echo "  Start new     - Plain Claude session" >/dev/tty
        echo "  Resume        - Resume a previous Claude session" >/dev/tty
        echo "" >/dev/tty
        echo "Press Enter to return to menu..." >/dev/tty
        read -r </dev/tty
    fi
}

# ===== MAIN MENU =====

# Show main menu
# Returns selected action via stdout: "orchestrate", "bulletproof", "start", "resume"
show_main_menu() {
    while true; do
        show_header

        echo "Options:" >/dev/tty
        echo "  1) Start orchestration  (orchestrator-mode skill)" >/dev/tty
        echo "  2) Start bulletproof    (12-stage verified workflow)" >/dev/tty
        echo "  3) Start new conversation" >/dev/tty
        echo "  4) Resume from list" >/dev/tty
        echo "  h) Help" >/dev/tty
        echo "" >/dev/tty
        echo -n "Choose an option [1-4, h]: " >/dev/tty
        read -r choice </dev/tty

        case "${choice}" in
            1) echo "orchestrate"; return 0 ;;
            2) echo "bulletproof"; return 0 ;;
            3) echo "start"; return 0 ;;
            4) echo "resume"; return 0 ;;
            h|H|help) display_help ;;
            *)
                echo "Invalid choice. Press Enter to continue..." >/dev/tty
                read -r </dev/tty
                ;;
        esac
    done
}

# Run the interactive menu system
# Returns selected action via stdout: "start", "resume", "orchestrate", or "bulletproof"
run_menu_system() {
    local action
    action=$(show_main_menu)
    echo "${action}"
}

# ===== ORCHESTRATION =====

# Build the orchestrator system prompt
# Outputs the prompt content to stdout
build_orchestrator_prompt() {
    if [[ ! -f "${ORCHESTRATOR_PROMPT}" ]]; then
        wrapper_log "ERROR" "Orchestrator prompt not found: ${ORCHESTRATOR_PROMPT}"
        return 1
    fi
    cat "${ORCHESTRATOR_PROMPT}"
}

# Build the bulletproof system prompt
# Outputs the prompt content to stdout
build_bulletproof_prompt() {
    if [[ ! -f "${BULLETPROOF_PROMPT}" ]]; then
        wrapper_log "ERROR" "Bulletproof prompt not found: ${BULLETPROOF_PROMPT}"
        return 1
    fi
    cat "${BULLETPROOF_PROMPT}"
}

# ===== CLEANUP =====

cleanup_wrapper() {
    rm -f /tmp/claude-orchestrator-$$.md 2>/dev/null
}

trap cleanup_wrapper EXIT

# ===== SCRIPT GUARD =====

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    echo "Usage: source claude_wrapper_lib.bash" >&2
    exit 1
fi
