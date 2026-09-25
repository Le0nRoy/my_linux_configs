#!/bin/bash
# Polybar widget for uncommitted chezmoi changes.
#
# `chezmoi status` first column marks pending script runs with `R`
# (run_always_/run_onchange_/run_once_) even when no target file will
# change on disk. Those are noise for the widget — the operator only
# cares about real file adds/mods/deletes. Filter `R` rows out.

WHITELIST=(\
    .config/KeePass/KeePass.config.xml \
)
CHANGES=$(chezmoi status | awk '$1 !~ /R/ {print $2}')

for f in "${WHITELIST[@]}"; do
    CHANGES=$(echo "$CHANGES" | grep -v "^$f$")
done

[ -n "$CHANGES" ] && echo "!CHZ" || echo ""
