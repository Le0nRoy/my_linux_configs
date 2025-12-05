#!/bin/bash
# Helper Utils Module - Miscellaneous utility functions
# No dependencies

function upgrade_system() {
    # Upgrade system packages and global npm packages
    yay -Syu
    sudo paccache -r
    sudo npm install -g @openai/codex@latest
    sudo npm install -g @anthropic-ai/claude-code@latest
    sudo npm cache clean
    npm outdated -g --depth=0
}

function adb_pull_music() {
    # Pull music from Android device via ADB
    adb pull /sdcard/Vk/Vkontakte/ /Data/vkDownloads/Music/
}

function unzip_books() {
    # Unzip fb2 book files and rename them properly
    for file in *.fb2.zip; do
        unzip "${file}"
        rm "${file}"
    done
    for book in $(ls | grep -E ".*\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2"); do
        local new_name
        new_name="$(echo "${book}" | sed -E 's/(.*)\.[a-zA-Z0-9_\-]+\.[0-9]+\.fb2/\1.fb2/')"
        mv "${book}" "${new_name}"
    done
}

function cut_video() {
    # Cut a segment from video file
    # Usage: cut_video <input> <start_time> <duration> <output>
    local input="${1}"
    local cut_start="${2}"
    local cut_duration="${3}"
    local output="${4}"
    ffmpeg -ss "${cut_start}" -i "${input}" -t "${cut_duration}" -vcodec copy -acodec copy "${output}"
}

function gpg_decrypt() {
    # Decrypt and verify GPG file
    shift
    gpg --decrypt "${1}" | tee "${2}" | gpg --verify
}

function gpg_encrypt() {
    # Encrypt and sign file with GPG
    shift
    gpg --local-user Vadim_signature --sign --encrypt --armor --recipient "${1}"
}
