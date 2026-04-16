#!/bin/bash
# Creates ~/bin/.firefox_profiles with an empty mapping on first chezmoi apply.
# Never overwrites the file if it already exists — user edits are preserved.

DEST="${HOME}/bin/.firefox_profiles"
[[ -f "${DEST}" ]] && exit 0

cat > "${DEST}" << 'EOF'
# Firefox profile display name overrides
#
# Format: one assignment per profile, path must be absolute (start with /).
#
#   FIREFOX_PROFILE_NAMES["/abs/path/to/profile"]="Rofi label"
#
# Profiles listed here that exist on disk are shown in the rofi menu
# even if they are not present in profiles.ini.
# The default profile (Default=1 in profiles.ini) is always labelled "Personal"
# unless explicitly overridden here.
#
# Find your profile paths:
#   ls ~/.mozilla/firefox/          # standard install
#   ls ~/.cache/mozilla/firefox/    # some distros
#
declare -A FIREFOX_PROFILE_NAMES=()

# FIREFOX_PROFILE_NAMES["$HOME/.mozilla/firefox/khbqv2t5.default-release"]="Personal"
# FIREFOX_PROFILE_NAMES["$HOME/.mozilla/firefox/TxktUkK5.Profile 1"]="Work"
EOF
