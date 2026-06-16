#!/bin/bash
# Installs a pre-commit hook that prevents direct commits to main/master.
# Runs on every chezmoi apply; only writes if the guard is not already present,
# so any extra user hook logic is preserved.

set -euo pipefail

CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-${HOME}/.local/share/chezmoi}"
HOOKS_DIR="${CHEZMOI_SOURCE_DIR}/.git/hooks"
HOOK_FILE="${HOOKS_DIR}/pre-commit"
GUARD_MARKER="no-main-commit guard"

mkdir -p "${HOOKS_DIR}"

# Skip writing if the guard is already present in the hook
if [[ -f "${HOOK_FILE}" ]] && grep -qF "${GUARD_MARKER}" "${HOOK_FILE}"; then
    echo "pre-commit hook already contains no-main-commit guard, skipping"
    exit 0
fi

if [[ ! -f "${HOOK_FILE}" ]]; then
    # Create fresh hook with shebang
    cat > "${HOOK_FILE}" << 'HOOK'
#!/bin/bash
# no-main-commit guard
BRANCH=$(git symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')
if [[ "${BRANCH}" == "main" || "${BRANCH}" == "master" ]]; then
    echo "error: direct commits to '${BRANCH}' are not allowed"
    echo "       create a feature branch: git checkout -b feat/<name>"
    exit 1
fi
HOOK
else
    # Append guard to existing hook (preserve user's existing logic)
    cat >> "${HOOK_FILE}" << 'HOOK'

# no-main-commit guard
BRANCH=$(git symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')
if [[ "${BRANCH}" == "main" || "${BRANCH}" == "master" ]]; then
    echo "error: direct commits to '${BRANCH}' are not allowed"
    echo "       create a feature branch: git checkout -b feat/<name>"
    exit 1
fi
HOOK
fi

chmod +x "${HOOK_FILE}"
echo "pre-commit hook installed at ${HOOK_FILE}"
