#!/bin/bash
# Lightweight, minimal-privilege wrapper for Cursor Agent CLI using bubblewrap.
# Uses the universal AI agent wrapper with cursor-agent-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjust as you like)
# Note: cursor-agent needs unlimited address space for WebAssembly modules
# We still limit CPU time and processes for security
export RLIMIT_AS=unlimited
export RLIMIT_CPU=60
export RLIMIT_NOFILE=1024
export RLIMIT_NPROC=60

# Run cursor-agent with its specific binds
# Note: Added prlimit (was missing in original), Android is now a default bind
run_sandboxed_agent "cursor-agent" -- \
    --ro-bind /opt/cursor-agent /opt/cursor-agent \
    --bind "${HOME}/.cursor" "${HOME}/.cursor" \
    --bind "${HOME}/.config/cursor" "${HOME}/.config/cursor" \
    --bind "${HOME}/.local/share/cursor-agent" "${HOME}/.local/share/cursor-agent" \
    -- "$@"

