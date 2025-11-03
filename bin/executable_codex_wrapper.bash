#!/bin/bash
# Lightweight, minimal-privilege wrapper for codex CLI using bubblewrap.
# Uses the universal AI agent wrapper with codex-specific configuration.

# Source the universal wrapper
source "$(dirname "${BASH_SOURCE[0]}")/ai_agent_universal_wrapper.bash"

# Configurable rlimits (adjust as you like)
export RLIMIT_AS=$((4 * 1024 * 1024 * 1024))   # 4 GiB
export RLIMIT_CPU=60
export RLIMIT_NOFILE=1024
export RLIMIT_NPROC=60

# Run codex with its specific binds
run_sandboxed_agent "codex" -- \
    --bind "${HOME}/.codex" "${HOME}/.codex" \
    -- "$@"

