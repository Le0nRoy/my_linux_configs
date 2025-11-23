#!/bin/bash
# Docker wrapper to block --pid flags for security
# Purpose: Prevent containers from accessing host PID namespace
# Security: Blocks Docker --pid=host vulnerability (CVE-INTERNAL-2025-11-23)
#
# Integration: This script is deployed to ~/bin/docker via chezmoi
#              AI agent wrappers set PATH="${HOME}/bin:/usr/bin:..."
#              So this wrapper intercepts all docker commands in the sandbox
#              Safe commands are forwarded to /usr/bin/docker
#
# Deployment: chezmoi apply (creates ~/bin/docker with executable permissions)
# Testing: See docs/security_test_results_docker_pid_blocking.md

set -e

# Path to real Docker binary
REAL_DOCKER="/usr/bin/docker"

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to show error message
show_security_error() {
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${RED}║          SECURITY: Docker --pid flag BLOCKED                  ║${NC}" >&2
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "${YELLOW}Reason:${NC} Containers with --pid=host can see and signal host processes." >&2
    echo -e "${YELLOW}Risk:${NC} Information disclosure, potential denial of service." >&2
    echo "" >&2
    echo "The --pid flag has been blocked for security reasons:" >&2
    echo "  • Containers with --pid=host can view ALL host processes" >&2
    echo "  • Can read process information (PIDs, commands, users)" >&2
    echo "  • Can send signals to host processes (potential DOS)" >&2
    echo "" >&2
    echo -e "${YELLOW}Blocked command:${NC}" >&2
    echo "  docker $*" >&2
    echo "" >&2
    echo "For more information, see:" >&2
    echo "  ~/docs/SECURITY_MODEL.md" >&2
    echo "  ~/docs/security_test_results_docker_pid_host.md" >&2
    echo "" >&2
    echo "If you absolutely need --pid access, run Docker outside the AI agent:" >&2
    echo "  /usr/bin/docker $*" >&2
    exit 1
}

# Function to check if command contains --pid flag
contains_pid_flag() {
    local -a args=("$@")

    for arg in "${args[@]}"; do
        # Check for --pid flag in various forms
        if [[ "${arg}" == "--pid" ]] || \
           [[ "${arg}" == "--pid="* ]] || \
           [[ "${arg}" =~ ^--pid[[:space:]] ]]; then
            return 0  # Found --pid flag
        fi
    done

    return 1  # No --pid flag found
}

# Function to check if this is a command that can use --pid
is_pid_capable_command() {
    local cmd="${1}"

    # Commands that support --pid flag
    case "${cmd}" in
        run|create|exec)
            return 0  # These commands can use --pid
            ;;
        *)
            return 1  # Other commands don't use --pid
            ;;
    esac
}

# Main logic

# If no arguments, just show Docker help
if [[ $# -eq 0 ]]; then
    exec "${REAL_DOCKER}"
fi

# Get the Docker subcommand (run, build, ps, etc.)
DOCKER_CMD="${1}"

# Check if this command can potentially use --pid flag
if is_pid_capable_command "${DOCKER_CMD}"; then
    # Check if --pid flag is present in arguments
    if contains_pid_flag "$@"; then
        show_security_error "$@"
    fi
fi

# If we get here, command is safe - execute real Docker
exec "${REAL_DOCKER}" "$@"
