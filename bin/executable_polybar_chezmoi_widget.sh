#!/bin/bash
# Polybar widget for uncommitted chezmoi changes and remote updates

WHITELIST=(
    .config/KeePass/KeePass.config.xml
)

# Check for local uncommitted changes
CHANGES="$(chezmoi status | awk '{print $2}')"

for f in "${WHITELIST[@]}"; do
    CHANGES="$(echo "${CHANGES}" | grep -v "^${f}$")"
done

# Check for remote updates (in chezmoi source directory)
CHEZMOI_SOURCE="$(chezmoi source-path 2>/dev/null)"
REMOTE_BEHIND=0
if [[ -d "${CHEZMOI_SOURCE}/.git" ]]; then
    # Fetch remote silently (timeout to avoid blocking)
    timeout 5 git -C "${CHEZMOI_SOURCE}" fetch --quiet 2>/dev/null || true
    # Check if local is behind remote
    LOCAL="$(git -C "${CHEZMOI_SOURCE}" rev-parse HEAD 2>/dev/null)"
    REMOTE="$(git -C "${CHEZMOI_SOURCE}" rev-parse '@{u}' 2>/dev/null)"
    if [[ -n "${LOCAL}" && -n "${REMOTE}" && "${LOCAL}" != "${REMOTE}" ]]; then
        # Check if we're behind (remote has commits we don't have)
        if git -C "${CHEZMOI_SOURCE}" merge-base --is-ancestor HEAD '@{u}' 2>/dev/null; then
            REMOTE_BEHIND=1
        fi
    fi
fi

# Output indicator
if [[ -n "${CHANGES}" && "${REMOTE_BEHIND}" -eq 1 ]]; then
    echo "!CHZ↓"  # Local changes AND remote updates
elif [[ -n "${CHANGES}" ]]; then
    echo "!CHZ"   # Only local changes
elif [[ "${REMOTE_BEHIND}" -eq 1 ]]; then
    echo "CHZ↓"   # Only remote updates available
else
    echo ""       # All clean
fi

