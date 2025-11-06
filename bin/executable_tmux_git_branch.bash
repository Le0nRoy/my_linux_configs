#!/bin/bash
# Get current git branch for tmux status bar
# Returns empty string if not in a git repository

# Get the pane's current path
PANE_PATH="${1:-$PWD}"

# Change to the pane's directory
cd "${PANE_PATH}" 2>/dev/null || exit 0

# Check if we're in a git repository and get the branch
if git rev-parse --git-dir >/dev/null 2>&1; then
    branch="$(git symbolic-ref --short HEAD 2>/dev/null)"

    # If detached HEAD, show short commit hash
    if [[ -z "${branch}" ]]; then
        branch="$(git rev-parse --short HEAD 2>/dev/null)"
        branch="detached:${branch}"
    fi

    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        modified="*"
    else
        modified=""
    fi

    echo " ${branch}${modified}"
fi
