#!/bin/bash
# Links ~/.claude/skills -> ~/.agents/skills so Claude Code discovers agent skills
# Runs on every chezmoi apply

set -euo pipefail

SKILLS_DIR="${HOME}/.agents/skills"
CLAUDE_SKILLS="${HOME}/.claude/skills"

# Remove stale link/dir if it exists and isn't already correct
if [[ -e "${CLAUDE_SKILLS}" || -L "${CLAUDE_SKILLS}" ]]; then
    if [[ "$(readlink "${CLAUDE_SKILLS}")" != "${SKILLS_DIR}" ]]; then
        rm -rf "${CLAUDE_SKILLS}"
    fi
fi

if [[ ! -L "${CLAUDE_SKILLS}" ]]; then
    ln -s "${SKILLS_DIR}" "${CLAUDE_SKILLS}"
    echo "Linked ${CLAUDE_SKILLS} -> ${SKILLS_DIR}"
else
    echo "Link already correct: ${CLAUDE_SKILLS} -> ${SKILLS_DIR}"
fi
