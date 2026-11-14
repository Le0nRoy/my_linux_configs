#!/bin/bash
# Helper Utils Module - Miscellaneous utility functions
# No dependencies

function hh_upgrade_system() {
    # Upgrade system packages and global npm packages.
    # Stops at the first failing step and returns its status, so a failed
    # pacman upgrade is never followed by AUR builds against it.

    # Step 1: pacman-managed packages (quick: just download and install)
    sudo pacman -Syu || return

    # Step 2: npm-based global packages (fast)
    # Only upgrade agents that are already installed — never install new ones
    if command -v claude >/dev/null 2>&1; then
        sudo npm install -g @anthropic-ai/claude-code@latest || return
        sudo node "$(npm root -g)/@anthropic-ai/claude-code/install.cjs" || return
    else
        echo "claude not installed, skipping upgrade"
    fi
    if command -v codex >/dev/null 2>&1; then
        sudo npm install -g @openai/codex@latest || return
    else
        echo "codex not installed, skipping upgrade"
    fi
    sudo npm cache clean --force || return

    # Step 3: yay-managed AUR packages (slowest due to compilation)
    # --noconfirm:    non-interactive, no confirmation prompts
    # --nodiffmenu:   skip PKGBUILD diff display
    # --nocleanmenu:  skip clean-build-files menu (handled by --cleanafter)
    # --noeditmenu:   skip PKGBUILD edit menu
    # --noupgrademenu: skip package selection/exclusion menu
    # --cleanafter:   remove build dirs after install (saves space; compiled pkgs stay in pacman cache)
    # --removemake:   remove make-only dependencies after build (saves space)
    yay -Syu --noconfirm --nodiffmenu --nocleanmenu --noeditmenu --noupgrademenu \
        --cleanafter --removemake || return

    # Trim pacman cache: keep 1 version (allows one rollback, avoids storing 3 old versions)
    sudo paccache -rk1
}

function hh_yay_no_cache() {
    # Upgrade AUR packages via yay (non-interactive, space-efficient).
    # The cache is trimmed only after a successful upgrade.
    yay --noconfirm --nodiffmenu --nocleanmenu --noeditmenu --noupgrademenu \
        --cleanafter --removemake || return
    sudo paccache -rk1
}

function hh_adb_pull_music() {
    # Pull music from Android device via ADB
    adb pull /sdcard/Vk/Vkontakte/ /Data/vkDownloads/Music/
}

function hh_unzip_books() {
    # In the current directory: extract every *.fb2.zip (the archive is
    # removed only after a successful extraction), then strip the
    # ".<author>.<id>" suffix from *.fb2 names (Title.author.123.fb2 ->
    # Title.fb2). Returns non-zero when there is nothing to do or any
    # extraction/rename failed.
    local file book new_name found=0 status=0
    for file in *.fb2.zip; do
        [[ -e "${file}" ]] || continue
        found=1
        if unzip "${file}"; then
            rm -f -- "${file}"
        else
            echo "hh_unzip_books: failed to extract '${file}' (archive kept)" >&2
            status=1
        fi
    done
    for book in *.fb2; do
        [[ -e "${book}" ]] || continue
        found=1
        [[ "${book}" =~ \.[a-zA-Z0-9_-]+\.[0-9]+\.fb2$ ]] || continue
        new_name="$(printf '%s\n' "${book}" | sed -E 's/(.*)\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2/\1.fb2/')"
        mv -- "${book}" "${new_name}" || status=1
    done
    if ((found == 0)); then
        echo "hh_unzip_books: no *.fb2.zip or *.fb2 files in ${PWD}" >&2
        return 1
    fi
    return "${status}"
}

function hh_cut_video() {
    # Cut a segment from video file
    # Usage: hh_cut_video <input> <start_time> <duration> <output>
    local input="${1}"
    local cut_start="${2}"
    local cut_duration="${3}"
    local output="${4}"
    ffmpeg -ss "${cut_start}" -i "${input}" -t "${cut_duration}" -vcodec copy -acodec copy "${output}"
}

function hh_gpg_decrypt() {
    # Decrypt <in> into <out> and verify the signature.
    # Usage: hh_gpg_decrypt <in.asc> <out>
    # Returns the status of the first failing pipeline stage.
    if (($# != 2)); then
        echo "Usage: hh_gpg_decrypt <in.asc> <out>" >&2
        return 1
    fi
    gpg --decrypt "${1}" | tee "${2}" | gpg --verify
    local -a stages=("${PIPESTATUS[@]}")
    local stage
    for stage in "${stages[@]}"; do
        ((stage == 0)) || return "${stage}"
    done
}

function hh_gpg_encrypt() {
    # Sign and encrypt stdin for <recipient> (ASCII armour on stdout).
    # Usage: hh_gpg_encrypt <recipient> < file
    if (($# != 1)); then
        echo "Usage: hh_gpg_encrypt <recipient> < file" >&2
        return 1
    fi
    gpg --local-user Vadim_signature --sign --encrypt --armor --recipient "${1}"
}
