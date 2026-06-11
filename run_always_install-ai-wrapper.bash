#!/bin/bash
# Applies the AI-Wrapper submodule as a secondary chezmoi source.
# Runs on every chezmoi apply, after the main dotfiles are applied.
# This preserves the full AI wrapper installation (wrappers, skills, AGENTS.md)
# without needing to keep those files in the chezmoi-dotfiles repo.

set -euo pipefail

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
AI_WRAPPER_SRC="${CHEZMOI_SOURCE_DIR}/ai-wrapper"

# Initialize submodule if not yet done (fresh clone)
if [[ ! -f "${AI_WRAPPER_SRC}/AGENTS.md" ]]; then
    echo "AI-Wrapper submodule not initialized, running git submodule update..."
    git -C "${CHEZMOI_SOURCE_DIR}" submodule update --init --recursive ai-wrapper
fi

# Apply AI-Wrapper as a secondary chezmoi source
if [[ -f "${AI_WRAPPER_SRC}/AGENTS.md" ]]; then
    CHEZMOI_SOURCE_DIR="${AI_WRAPPER_SRC}" chezmoi apply
    echo "AI-Wrapper applied from ${AI_WRAPPER_SRC}"
else
    echo "Warning: AI-Wrapper submodule still not available at ${AI_WRAPPER_SRC}" >&2
fi
