#!/bin/bash
# Lightweight, minimal-privilege wrapper for Claude CLI using bubblewrap.
# Uses the universal AI agent wrapper with claude-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjust as you like)
export RLIMIT_AS=$((4 * 1024 * 1024 * 1024))   # 4 GiB
export RLIMIT_CPU=60
export RLIMIT_NOFILE=1024
export RLIMIT_NPROC=60

# Run claude with its specific binds
# Note: Added prlimit (was missing in original), removed incorrect /opt/cursor-agent ro-bind, Android is now a default bind
run_sandboxed_agent "claude" -- \
    --bind "${HOME}/.claude" "${HOME}/.claude" \
    --bind "${HOME}/.claude.json" "${HOME}/.claude.json" \
    -- "$@"

