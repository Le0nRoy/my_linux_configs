#!/bin/bash
# Polybar widget for uncommitted chezmoi changes.
#
# Output: "" when clean, "!CHZ" when target files differ, "?CHZ" when
# `chezmoi status` fails (missing binary, broken source/config), so an error
# is never shown as a clean state.
#
# `chezmoi status` marks pending script runs with `R`
# (run_always_/run_onchange_/run_once_) even when no target file will
# change on disk. Those are noise for the widget — the operator only
# cares about real file adds/mods/deletes. Filter `R` rows out.

if ! STATUS=$(chezmoi status); then
    echo "?CHZ"
    exit 0
fi

CHANGES=$(printf '%s\n' "$STATUS" | awk 'NF && $1 !~ /R/')

[ -n "$CHANGES" ] && echo "!CHZ" || echo ""
