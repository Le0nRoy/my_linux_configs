#!/bin/sh
# Polybar widget for uncommitted chezmoi changes

WHITELIST=(\
    .config/KeePass/KeePass.config.xml \
)
CHANGES=$(chezmoi status | awk '{print $2}')

for f in "${WHITELIST[@]}"; do
    CHANGES=$(echo "$CHANGES" | grep -v "^$f$")
done

[ -n "$CHANGES" ] && echo "!CHZ" || echo ""

