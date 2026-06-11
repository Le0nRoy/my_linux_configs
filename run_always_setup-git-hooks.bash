#!/bin/bash
# Installs a pre-commit hook that prevents direct commits to main/master.
# Runs on every chezmoi apply to ensure the hook is always present.

set -euo pipefail

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
HOOKS_DIR="${CHEZMOI_SOURCE_DIR}/.git/hooks"
HOOK_FILE="${HOOKS_DIR}/pre-commit"

mkdir -p "${HOOKS_DIR}"

cat > "${HOOK_FILE}" << 'HOOK'
#!/bin/bash
BRANCH=$(git symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')
if [[ "${BRANCH}" == "main" || "${BRANCH}" == "master" ]]; then
    echo "error: direct commits to '${BRANCH}' are not allowed"
    echo "       create a feature branch: git checkout -b feat/<name>"
    exit 1
fi
HOOK

chmod +x "${HOOK_FILE}"
echo "pre-commit hook installed at ${HOOK_FILE}"
