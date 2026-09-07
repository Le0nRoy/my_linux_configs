#!/bin/bash
# Applies the AI-Wrapper submodule as a secondary chezmoi source.
# Runs on every chezmoi apply, after the main dotfiles are applied.
# This preserves the full AI wrapper installation (wrappers, skills, AGENTS.md)
# without needing to keep those files in the chezmoi-dotfiles repo.

set -euo pipefail

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
AI_WRAPPER_SRC="${CHEZMOI_SOURCE_DIR}/ai-wrapper"

# Initialize submodule if not yet done (fresh clone).
# Use .git as sentinel — stable across any repo reorganization.
# NOTE: for a submodule, .git is a FILE (gitlink pointer), not a directory —
# use -e, not -d, or this check never sees it as initialized.
if [[ ! -e "${AI_WRAPPER_SRC}/.git" ]]; then
    echo "AI-Wrapper submodule not initialized, running git submodule update..."
    if ! git -C "${CHEZMOI_SOURCE_DIR}" submodule update --init --recursive ai-wrapper > /dev/null 2>&1; then
        echo "Warning: could not initialize AI-Wrapper submodule." >&2
        echo "  Ensure network access and retry: git -C \"${CHEZMOI_SOURCE_DIR}\" submodule update --init --recursive ai-wrapper" >&2
        exit 0
    fi
fi

# Apply AI-Wrapper as a secondary chezmoi source.
# NOTE: setting the CHEZMOI_SOURCE_DIR env var does nothing here — chezmoi does
# not read it back as an override, so the --source flag is required or this
# silently re-applies the main source tree instead.
# NOTE: --persistent-state must point somewhere other than the default state
# file — this script runs from inside an in-progress `chezmoi apply`, which
# already holds the lock on the default state file; reusing it deadlocks with
# "timeout obtaining persistent state lock".
if [[ -e "${AI_WRAPPER_SRC}/.git" ]]; then
    # chezmoi apply manages entries within an existing destination root but
    # won't create the root itself on a fresh machine.
    mkdir -p "${HOME}/ai-wrapper"
    chezmoi apply \
        --source "${AI_WRAPPER_SRC}" \
        --destination "${HOME}/ai-wrapper" \
        --persistent-state "${HOME}/.cache/chezmoi/ai-wrapper-state.boltdb"
    echo "AI-Wrapper applied from ${AI_WRAPPER_SRC} to ${HOME}/ai-wrapper"
else
    echo "Warning: AI-Wrapper submodule still not available at ${AI_WRAPPER_SRC}" >&2
fi
