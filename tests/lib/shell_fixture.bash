#!/usr/bin/env bash
# Shared sandbox for the interactive-shell regression tests.
#
# Every shell runs against a synthetic HOME built from tracked files (deployed
# under their chezmoi target names) with `env -i` and a PATH whose first entry
# is a directory of logging fakes for every external command the exercised
# code paths reach. No real startup file, runtime ~/bin/.env, job setup file,
# client, mount, service or live tmux server is touched.
#
# Callers set TMP_ROOT before sourcing; FAKEBIN lives below it.

FAKEBIN="${TMP_ROOT:?TMP_ROOT must be set}/fakebin"
SHELL_TIMEOUT_SECONDS=30
TMUX_ID_INITIAL="main:1.0"
# Fake commands the exercised code paths reach.
FAKE_COMMANDS=(xhost tmux gio fscrypt i3-msg i3-save-tree jq pactl dunstify
    dunstctl notify-send setxkbmap xset xinput pkill kbdd feh systemctl
    journalctl systemd-escape light rofi wmctrl xdotool xclip firefox
    firejail rclone ssh rsync scp pyenv ssh-agent docker i3lock i3-nagbar
    polybar launchctl yay pacman apt sudo adb ffmpeg gpg watch zenity
    unzip tar 7z xev xprop)

make_fakebin() {
    mkdir -p "${FAKEBIN}"
    cat > "${FAKEBIN}/e1-fake" <<'FAKE'
#!/bin/bash
# Logging stand-in for an external command; never touches the host.
name="${0##*/}"
{ printf '%s' "${name}"; printf ' [%s]' "$@"; printf '\n'; } >> "${E1_ARGV_LOG:-/dev/null}"
printf '%s %s\n' "${name}" "$*" >> "${E1_CALL_LOG:-/dev/null}"
case "${name}" in
    tmux)
        case "${1:-}" in
            display-message)
                [[ -s "${E1_TMUX_ID_FILE:?}" ]] || exit 1
                cat "${E1_TMUX_ID_FILE}"
                ;;
        esac
        ;;
    gio)
        case "${1:-} ${2:-}" in
            "mount -li") echo "activation_root=mtp://e1phone/" ;;
        esac
        [[ "${1:-}" == "info" ]] && echo "local path: ${E1_GIO_MOUNT:?}"
        ;;
    i3-msg)
        [[ "${1:-} ${2:-}" == "-t get_workspaces" ]] && echo '[{"num":1}]'
        ;;
    jq) cat > /dev/null; echo 1 ;;
    i3-save-tree) printf '// "class": "^E1$",\n{ "nodes": [] }\n' ;;
    pactl)
        case "${1:-}" in
            get-sink-volume) echo "Volume: front-left: 32768 / 50% / -18.06 dB" ;;
            get-sink-mute) echo "Mute: no" ;;
        esac
        ;;
    systemd-escape) printf '%s\n' "$1" ;;
    rofi) sed 's/^/rofi-menu: /' >> "${E1_CALL_LOG:-/dev/null}" ;;
    rsync|ssh) [[ "${E1_FAIL_TRANSFER:-}" == 1 ]] && { echo "${name}: e1 failure" >&2; exit 23; } ;;
esac
exit 0
FAKE
    chmod +x "${FAKEBIN}/e1-fake"
    local cmd
    for cmd in "${FAKE_COMMANDS[@]}"; do
        ln -s e1-fake "${FAKEBIN}/${cmd}"
    done
}

# deploy_tree <source_root> <home> [skipped helper module...]
deploy_tree() {
    local src="$1" home="$2" skip f mod
    shift 2
    mkdir -p "${home}/bin/helper" "${home}/.bash_completion.d" "${home}/.ssh" \
        "${home}/job" "${home}/mnt/phone" "${home}/.local/state" \
        "${home}/.mozilla/firefox/e1profile"
    cp "${src}/dot_bashrc" "${home}/.bashrc"
    cp "${src}/dot_zshrc" "${home}/.zshrc"
    cp "${src}/dot_xsessionrc" "${home}/.xsessionrc"
    cp "${src}/dot_bash_completion.d/"* "${home}/.bash_completion.d/"
    cp "${src}/bin/executable_helper.bash" "${home}/bin/helper.bash"
    chmod +x "${home}/bin/helper.bash"
    for f in "${src}/bin/helper/"*.bash "${src}/bin/helper/"*.zsh "${src}/bin/helper/"*.shrc; do
        [[ -e "${f}" ]] || continue
        mod="${f##*/}"
        for skip in "$@"; do
            [[ "${mod}" == "${skip}.bash" ]] && continue 2
        done
        cp "${f}" "${home}/bin/helper/${mod}"
    done
    for skip in "$@"; do
        [[ "${skip}" == "system" ]] && rm -f "${home}/.xsessionrc"
    done
    # Synthetic runtime inputs (the real ~/bin/.env and job setup are never read).
    printf 'export JOB_SETUP_FILE="${HOME}/job/add_exports.bash"\n' > "${home}/bin/.env"
    printf 'export E1_JOB_SENTINEL=loaded\n' > "${home}/job/add_exports.bash"
    printf '#!/bin/bash\necho "release $*" >> "${E1_CALL_LOG:-/dev/null}"\n' \
        > "${home}/bin/tmux_pane_hist_release.bash"
    chmod +x "${home}/bin/tmux_pane_hist_release.bash"
    printf 'Host alpha\n    User bob\nHost beta\nHost *.wild\n' > "${home}/.ssh/config"
    printf '[Profile0]\nName=e1\nPath=e1profile\nDefault=1\n' \
        > "${home}/.mozilla/firefox/profiles.ini"
    # Third-party completion fixture: underscore vendor symbols must survive.
    printf '_vendor_fixture_complete() { :; }\ncomplete -F _vendor_fixture_complete e1vendor\n' \
        > "${home}/.bash_completion.d/zz_vendor_fixture"
    printf '%s\n' "${TMUX_ID_INITIAL}" > "${home}/tmux_id"
}

# Environment shared by every sandboxed shell: env -i plus these.
sandbox_env() {
    local home="$1"
    SANDBOX_ENV=(HOME="${home}" USER=e1user HOSTNAME=e1host TERM=xterm
        PATH="${FAKEBIN}:/usr/bin:/bin" XDG_STATE_HOME="${home}/.local/state"
        E1_CALL_LOG="${home}/calls.log" E1_ARGV_LOG="${home}/argv.log"
        E1_TMUX_ID_FILE="${home}/tmux_id" E1_GIO_MOUNT="${home}/mnt/phone")
}

# run_bash <home> <script> [VAR=value...]: real interactive bash startup
# (~/.bashrc) followed by <script>. Sets RUN_OUT / RUN_STATUS.
run_bash() {
    local home="$1" script="$2"
    shift 2
    sandbox_env "${home}"
    RUN_OUT="$(cd "${home}" && env -i "${SANDBOX_ENV[@]}" "$@" \
        timeout "${SHELL_TIMEOUT_SECONDS}" bash --noprofile -i -c "${script}" \
        2>"${home}/stderr.log" </dev/null)"
    RUN_STATUS=$?
}

# run_zsh <home> <script> [VAR=value...]: real interactive zsh startup
# (~/.zshrc via ZDOTDIR) followed by <script>. Sets RUN_OUT / RUN_STATUS.
run_zsh() {
    local home="$1" script="$2"
    shift 2
    sandbox_env "${home}"
    RUN_OUT="$(cd "${home}" && env -i "${SANDBOX_ENV[@]}" ZDOTDIR="${home}" "$@" \
        timeout "${SHELL_TIMEOUT_SECONDS}" zsh -i -c "${script}" \
        2>"${home}/stderr.log" </dev/null)"
    RUN_STATUS=$?
}

# Value of "key=value" line in RUN_OUT, with the sandbox HOME normalised.
out_value() {
    local key="$1" home="$2"
    printf '%s\n' "${RUN_OUT}" | sed -n "s|^${key}=||p" | head -n 1 \
        | sed "s|${home}|<HOME>|g"
}

# "status=<RUN_STATUS> stderr=<first stderr line>" for failure messages.
run_summary() {
    local home="$1"
    printf 'status=%s stderr=%s' "${RUN_STATUS}" "$(head -n 1 "${home}/stderr.log" 2>/dev/null)"
}
