#!/bin/bash
# Applies the AI-Wrapper submodule as a secondary chezmoi source.
# Runs on every chezmoi apply, after the main dotfiles are applied.
# This preserves the full AI wrapper installation (wrappers, skills, AGENTS.md)
# without needing to keep those files in the chezmoi-dotfiles repo.

set -euo pipefail

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
AI_WRAPPER_SRC="${CHEZMOI_SOURCE_DIR}/ai-wrapper"

# Initialize submodule if not yet done (fresh clone).
# Use .git dir as sentinel — stable across any repo reorganization.
if [[ ! -d "${AI_WRAPPER_SRC}/.git" ]]; then
    echo "AI-Wrapper submodule not initialized, running git submodule update..."
    if ! git -C "${CHEZMOI_SOURCE_DIR}" submodule update --init --recursive ai-wrapper 2>&1; then
        echo "Warning: could not initialize AI-Wrapper submodule." >&2
        echo "  Ensure network access and retry: git -C \"${CHEZMOI_SOURCE_DIR}\" submodule update --init --recursive ai-wrapper" >&2
        exit 0
    fi
fi

# Apply AI-Wrapper as a secondary chezmoi source
if [[ -d "${AI_WRAPPER_SRC}/.git" ]]; then
    CHEZMOI_SOURCE_DIR="${AI_WRAPPER_SRC}" chezmoi apply
    echo "AI-Wrapper applied from ${AI_WRAPPER_SRC}"
else
    echo "Warning: AI-Wrapper submodule still not available at ${AI_WRAPPER_SRC}" >&2
fi
