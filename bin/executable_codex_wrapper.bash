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

# Run codex with its specific binds
run_sandboxed_agent "codex" -- \
    --bind "${HOME}/.codex" "${HOME}/.codex" \
    -- "$@"

