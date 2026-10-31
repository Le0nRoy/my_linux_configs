#!/usr/bin/env bash
# Regression test for issue #59: interactive shells load public helpers and
# the owner-approved shell-plumbing callbacks only; script-private helpers
# stay callable inside `helper.bash <command>` but never enter the shell.
#
# Every shell runs against a synthetic HOME built from tracked files (deployed
# under their chezmoi target names) with `env -i` and a PATH whose first entry
# is a directory of logging fakes for every external command the exercised
# code paths reach (xhost, tmux, X11/input tools, GIO, fscrypt, systemd, audio,
# notifications, i3, rofi, browsers, rclone, network clients). No real
# startup file, runtime ~/bin/.env, job setup file, client, mount, service or
# live tmux server is touched.
#
# Known baseline defects owned by #60 (E2) are reported as KNOWN-BASELINE and
# compared against the pre-E1 baseline so E1 is proven not to worsen them;
# they are never counted as passes. Missing zsh or a missing baseline commit
# is reported as GAP.
#
# Usage: bash tests/test_shell_helper_isolation.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Pre-E1 integration head (agent/feature-55 merge-base of this work package).
BASELINE_REF="${E1_BASELINE_REF:-0d46a7f7df3be7c8a79d8cad5e30c9176b28d7d7}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/e1-isolation.XXXXXX")"
FAKEBIN="${TMP_ROOT}/fakebin"
SHELL_TIMEOUT_SECONDS=30
TMUX_PANE_FIXTURE="%7"
TMUX_ID_INITIAL="main:1.0"
TMUX_ID_MOVED="main:2.0"
TMUX_PLUMBING_MARKER="# Record the last-typed shell command per tmux pane"

trap 'rm -rf "${TMP_ROOT}"' EXIT

failures=0
gaps=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }
gap() { printf 'GAP: %s\n' "$1"; gaps=$((gaps + 1)); }
known() { printf 'KNOWN-BASELINE (#60): %s\n' "$1"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        pass "${label}"
    else
        fail "${label}: expected [${expected}] got [${actual}]"
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    if [[ -f "${file}" ]] && grep -qF -- "${needle}" "${file}"; then
        pass "${label}"
    else
        fail "${label}: [${needle}] not found in ${file##*/}"
    fi
}

# --- Symbol classification ---------------------------------------------------
# Public interactive helpers kept for the E1 intermediate stage (renames and
# job_mount/job_umount removal belong to #60).
PUBLIC_BASH=(colors ex tmux_restore git_watch git_cleanout sshfsctl gio_mount
    gio_umount job_mount job_umount upgrade_system yay_no_cache adb_pull_music
    unzip_books cut_video gpg_decrypt gpg_encrypt rsync_ssh rm_ssh
    i3_save_chezmoi_ws i3_save_ws i3_restore_ws)
# Owner-approved Bash shell plumbing: eager callbacks plus the nested
# completion helper that exists only after completion has run.
ALLOW_EAGER_BASH=(_bashrc_git_branch _tmux_log_last_cmd _tmux_pane_hist_path
    _tmux_pane_hist_claim _tmux_pane_hist_sync _helper_script
    _rsync_ssh_complete _rm_ssh_complete _ssh_config_hosts)
ALLOW_LAZY_BASH=(_flush)
# Script-private: callable only inside helper.bash script execution.
PRIVATE_BASH=(tmux_ide_session tmux_main_session rclone_systemd
    rclone_to_backup get_display set_us_ru_layout set_us_ge_layout
    set_background polybar_start send_notification_brightnes
    send_notification_volume set_volume print_usage
    apply_xsession_input_settings show_error_and_usage _ff_find_profiles_ini
    _ff_parse_profiles_ini _ff_launch _ff_profile_is_open _ff_launch_sandboxed
    _ff_profile_picker _ff_open_link __emit _i3_get_host _i3_check_ws_num
    _i3_clean_layout)
PUBLIC_ZSH=(tmux_restore git_watch)
ALLOW_ZSH=(_ctrl_d_exit _reset_ctrl_d_count _tmux_log_last_cmd
    _tmux_pane_hist_path _tmux_pane_hist_claim _tmux_pane_hist_detect
    _tmux_pane_hist_addhistory _tmux_pane_hist_sync)
# Linux-only helpers chezmoi skips on macOS (.chezmoiignore).
MACOS_SKIPPED_MODULES=(firefox i3 storage system utils)

sorted_words() { printf '%s\n' "$@" | sort -u; }

# Function names defined (at any nesting depth) by the given files.
defined_functions() {
    sed -En 's/^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\).*/\2/p' "$@" | sort -u
}

# Print "+name" / "-name" lines describing how set $2 differs from set $1.
set_diff() {
    comm -3 <(printf '%s\n' "$1" | sed '/^$/d') <(printf '%s\n' "$2" | sed '/^$/d') \
        | sed -E 's/^\t/+/; t; s/^/-/' | tr '\n' ' '
}

assert_set_eq() {
    local expected="$1" actual="$2" label="$3" delta
    delta="$(set_diff "${expected}" "${actual}")"
    if [[ -z "${delta}" ]]; then
        pass "${label}"
    else
        fail "${label}: ${delta}"
    fi
}

# --- Fixtures ----------------------------------------------------------------
make_fakebin() {
    mkdir -p "${FAKEBIN}"
    cat > "${FAKEBIN}/e1-fake" <<'FAKE'
#!/bin/bash
# Logging stand-in for an external command; never touches the host.
name="${0##*/}"
printf '%s %s\n' "${name}" "$*" >> "${E1_CALL_LOG:-/dev/null}"
case "${name}" in
    tmux)
        case "${1:-}" in
            display-message) cat "${E1_TMUX_ID_FILE:?}" ;;
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
esac
exit 0
FAKE
    chmod +x "${FAKEBIN}/e1-fake"
    local cmd
    for cmd in xhost tmux gio fscrypt i3-msg i3-save-tree jq pactl dunstify \
        dunstctl notify-send setxkbmap xset xinput pkill kbdd feh systemctl \
        journalctl systemd-escape light rofi wmctrl xdotool xclip firefox \
        firejail rclone ssh rsync scp pyenv ssh-agent docker i3lock i3-nagbar \
        polybar launchctl yay pacman apt sudo adb ffmpeg gpg watch zenity; do
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
    for f in "${src}/bin/helper/"*.bash "${src}/bin/helper/"*.zsh; do
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

# run_bash <home> <script> [VAR=value...]: real interactive bash startup
# (~/.bashrc) followed by <script>. Sets RUN_OUT / RUN_STATUS.
run_bash() {
    local home="$1" script="$2"
    shift 2
    RUN_OUT="$(cd "${home}" && env -i HOME="${home}" USER=e1user HOSTNAME=e1host \
        TERM=xterm PATH="${FAKEBIN}:/usr/bin:/bin" \
        XDG_STATE_HOME="${home}/.local/state" E1_CALL_LOG="${home}/calls.log" \
        E1_TMUX_ID_FILE="${home}/tmux_id" E1_GIO_MOUNT="${home}/mnt/phone" "$@" \
        timeout "${SHELL_TIMEOUT_SECONDS}" bash --noprofile -i -c "${script}" \
        2>"${home}/stderr.log")"
    RUN_STATUS=$?
}

# Value of "key=value" line in RUN_OUT, with the sandbox HOME normalised.
out_value() {
    local key="$1" home="$2"
    printf '%s\n' "${RUN_OUT}" | sed -n "s|^${key}=||p" | head -n 1 \
        | sed "s|${home}|<HOME>|g"
}

functions_in() { printf '%s\n' "${RUN_OUT}" | sed -n "s/^fn_$1://p" | sort -u; }

# --- Setup -------------------------------------------------------------------
make_fakebin
NEW_HOME="${TMP_ROOT}/new"
deploy_tree "${REPO_ROOT}" "${NEW_HOME}"

BASE_SRC="${TMP_ROOT}/baseline-src"
BASE_HOME="${TMP_ROOT}/baseline"
have_baseline=0
if git -C "${REPO_ROOT}" cat-file -e "${BASELINE_REF}^{commit}" 2>/dev/null; then
    mkdir -p "${BASE_SRC}"
    git -C "${REPO_ROOT}" archive "${BASELINE_REF}" dot_bashrc dot_zshrc dot_xsessionrc \
        dot_bash_completion.d bin | tar -x -C "${BASE_SRC}"
    deploy_tree "${BASE_SRC}" "${BASE_HOME}"
    have_baseline=1
else
    gap "baseline ${BASELINE_REF} unavailable: baseline comparison and body equivalence not verified"
fi

REPO_FUNCS="$(defined_functions "${REPO_ROOT}/dot_bashrc" "${REPO_ROOT}/dot_xsessionrc" \
    "${REPO_ROOT}/dot_bash_completion.d/"* "${REPO_ROOT}/bin/executable_helper.bash" \
    "${REPO_ROOT}/bin/helper/"*.bash)"
EXPECTED_IDLE="$(sorted_words "${PUBLIC_BASH[@]}" "${ALLOW_EAGER_BASH[@]}")"
EXPECTED_AFTER="$(sorted_words "${PUBLIC_BASH[@]}" "${ALLOW_EAGER_BASH[@]}" "${ALLOW_LAZY_BASH[@]}")"

echo "== Classification completeness"
assert_set_eq "$(sorted_words "${PUBLIC_BASH[@]}" "${ALLOW_EAGER_BASH[@]}" \
    "${ALLOW_LAZY_BASH[@]}" "${PRIVATE_BASH[@]}")" "${REPO_FUNCS}" \
    "every repository Bash function definition is classified exactly once"

# --- Interactive Bash: idle namespace, public calls, post-call namespace ------
# The script records the function table before and after exercising public
# helpers, CLI script-private paths and the lazy completion helper.
IDLE_SCRIPT='
compgen -A function | sed "s/^/fn_idle:/"
echo "path=${PATH}"
echo "job=${E1_JOB_SENTINEL:-unset}"
echo "prompt=${PROMPT_COMMAND}"
for f in '"${PRIVATE_BASH[*]}"'; do "$f" >/dev/null 2>&1; echo "call_${f}=$?"; done
cmd=E1_CALLER_CMD
export E1_ENV_SENTINEL=keep
opts_before="$-"
i3_save_chezmoi_ws >/dev/null; echo "i3_all=$?"
i3_save_ws 1 >/dev/null; echo "i3_one=$?"
i3_save_ws 0 2>"${HOME}/i3_err" >/dev/null; echo "i3_bad=$?"
i3_restore_ws 1 >/dev/null; echo "i3_restore=$?"
echo "cmd=${cmd}"
helper.bash volume mute >/dev/null; echo "cli_volume=$?"
helper.bash volume bogus > "${HOME}/usage.out"; echo "cli_usage=$?"
helper.bash firefox >/dev/null; echo "cli_firefox=$?"
helper.bash e1_unknown > "${HOME}/unknown.out"; echo "cli_unknown=$?"
helper.bash rclone_bisync --e1 src dst >/dev/null; echo "cli_rclone=$?"
helper.bash tmux_session >/dev/null; echo "cli_tmux=$?"
echo "opts_same=$([[ "$-" == "${opts_before}" ]] && echo yes || echo no)"
echo "env=${E1_ENV_SENTINEL}"
rsync_ssh -h >/dev/null; echo "rsync_help=$?"
declare -a e1_hosts=()
_ssh_config_hosts e1_hosts
echo "hosts=${e1_hosts[*]}"
gio_mount; echo "gio_mount=$?"
echo "pwd=${PWD}"
gio_umount; echo "gio_umount=$?"
compgen -A function | sed "s/^/fn_after:/"
'

echo "== Interactive Bash startup and public helper calls"
run_bash "${NEW_HOME}" "${IDLE_SCRIPT}"
assert_eq 0 "${RUN_STATUS}" "interactive bash startup + script exits 0"
NEW_IDLE="$(functions_in idle)"
assert_set_eq "${EXPECTED_IDLE}" "$(comm -12 <(printf '%s\n' "${NEW_IDLE}") <(printf '%s\n' "${REPO_FUNCS}"))" \
    "idle: repository functions are exactly public + eager allowlist"
if printf '%s\n' "${NEW_IDLE}" | grep -qx '_vendor_fixture_complete'; then
    pass "idle: third-party underscore completion function preserved"
else
    fail "idle: third-party underscore completion function missing"
fi
not_callable=1
for f in "${PRIVATE_BASH[@]}"; do
    status="$(out_value "call_${f}" "${NEW_HOME}")"
    if [[ "${status}" != 127 ]]; then
        fail "idle: ${f} is callable (status ${status:-none})"
        not_callable=0
    fi
done
(( not_callable )) && pass "idle: all ${#PRIVATE_BASH[@]} script-private names are not callable (127)"
assert_eq "<HOME>/bin:<HOME>/ai-wrapper/bin:${FAKEBIN}:/usr/bin:/bin" \
    "$(out_value path "${NEW_HOME}")" "PATH export kept in caller"
assert_eq loaded "$(out_value job "${NEW_HOME}")" "JOB_SETUP_FILE from .env sourced in caller"
assert_eq 0 "$(out_value i3_all "${NEW_HOME}")" "i3_save_chezmoi_ws succeeds through wrapper"
assert_eq 0 "$(out_value i3_one "${NEW_HOME}")" "i3_save_ws succeeds through wrapper"
assert_eq 1 "$(out_value i3_bad "${NEW_HOME}")" "i3_save_ws failure status propagates"
assert_file_contains "${NEW_HOME}/i3_err" "workspace number must be 1-9" "i3_save_ws failure stderr propagates"
assert_eq 0 "$(out_value i3_restore "${NEW_HOME}")" "i3_restore_ws succeeds through wrapper"
assert_file_contains "${NEW_HOME}/calls.log" "i3-msg workspace 1; append_layout" "i3_restore_ws reached i3-msg"
ws_file="${NEW_HOME}/.config/i3/workspaces/workspace_1-$(uname -n).json"
assert_file_contains "${ws_file}" '"class": "^E1$"' "i3 wrapper ran unchanged _i3_clean_layout body"
assert_eq E1_CALLER_CMD "$(out_value cmd "${NEW_HOME}")" "caller cmd variable untouched by i3_save_chezmoi_ws loop"
assert_eq 0 "$(out_value cli_volume "${NEW_HOME}")" "script mode: volume mute dispatches"
assert_file_contains "${NEW_HOME}/calls.log" "pactl set-sink-mute @DEFAULT_SINK@ toggle" "script mode: set_volume reached pactl"
assert_file_contains "${NEW_HOME}/calls.log" "dunstify -a changeVolume" "script mode: send_notification_volume ran"
assert_eq 1 "$(out_value cli_usage "${NEW_HOME}")" "script mode: bad volume action exits 1"
assert_file_contains "${NEW_HOME}/usage.out" "volume [-s pulseaudio_sink_name] action" "script mode: nested print_usage executed"
assert_eq 0 "$(out_value cli_firefox "${NEW_HOME}")" "script mode: firefox picker dispatches"
assert_file_contains "${NEW_HOME}/calls.log" "rofi-menu: Personal (e1profile)" "script mode: nested __emit produced profile entry"
assert_eq 1 "$(out_value cli_unknown "${NEW_HOME}")" "script mode: unknown command exits 1"
assert_file_contains "${NEW_HOME}/unknown.out" 'Unknown command "e1_unknown"' "script mode: show_error_and_usage ran"
assert_file_contains "${NEW_HOME}/unknown.out" "volume|" "script mode: usage lists dispatch commands"
assert_eq 0 "$(out_value cli_rclone "${NEW_HOME}")" "script mode: rclone_bisync dispatches"
assert_file_contains "${NEW_HOME}/calls.log" "--modify-window 24h bisync --e1 src dst" "script mode: rclone_systemd reached rclone"
assert_eq 0 "$(out_value cli_tmux "${NEW_HOME}")" "script mode: tmux_session dispatches"
assert_file_contains "${NEW_HOME}/calls.log" "tmux attach-session -t =tmux-main -d" "script mode: tmux_main_session reached tmux"
assert_eq yes "$(out_value opts_same "${NEW_HOME}")" "caller shell options unchanged by i3/CLI calls"
assert_eq keep "$(out_value env "${NEW_HOME}")" "caller environment unchanged by i3/CLI calls"
assert_eq 0 "$(out_value rsync_help "${NEW_HOME}")" "rsync_ssh -h works in-process"
assert_eq "bob@alpha beta" "$(out_value hosts "${NEW_HOME}")" "_ssh_config_hosts completion helper works"
assert_eq 0 "$(out_value gio_mount "${NEW_HOME}")" "gio_mount succeeds"
assert_eq "<HOME>/mnt/phone" "$(out_value pwd "${NEW_HOME}")" "gio_mount changes caller directory"
assert_eq 0 "$(out_value gio_umount "${NEW_HOME}")" "gio_umount succeeds"
assert_set_eq "${EXPECTED_AFTER}" \
    "$(comm -12 <(functions_in after) <(printf '%s\n' "${REPO_FUNCS}"))" \
    "after calls: repository functions are exactly public + eager + lazy _flush"
if grep -q 'xhost' "${NEW_HOME}/calls.log"; then
    pass "startup xhost call resolved to the fake"
else
    fail "startup xhost call not trapped by the fake"
fi

if (( have_baseline )); then
    echo "== Baseline detection control"
    run_bash "${BASE_HOME}" 'compgen -A function | sed "s/^/fn_idle:/"'
    base_leaks="$(comm -12 <(functions_in idle) <(sorted_words "${PRIVATE_BASH[@]}") | tr '\n' ' ')"
    if [[ "${base_leaks}" == *_ff_launch* && "${base_leaks}" == *_i3_get_host* \
        && "${base_leaks}" == *apply_xsession_input_settings* ]]; then
        pass "baseline leak detected by the same probe (${base_leaks% })"
    else
        fail "probe does not detect baseline leaks: [${base_leaks}]"
    fi
fi

# --- Caller shell options from sshfsctl (stateful public API) ---------------
echo "== sshfsctl keeps its in-process caller option contract"
run_bash "${NEW_HOME}" 'sshfsctl -h >/dev/null; echo "st=$?"; echo "opts=$-"; echo "pf=$(set -o | grep -c "pipefail.*on")"'
assert_eq 0 "$(out_value st "${NEW_HOME}")" "sshfsctl -h succeeds"
opts="$(out_value opts "${NEW_HOME}")"
if [[ "${opts}" == *e* && "${opts}" == *u* && "$(out_value pf "${NEW_HOME}")" == 1 ]]; then
    pass "sshfsctl still sets errexit/nounset/pipefail in caller (unchanged body)"
else
    fail "sshfsctl caller option contract changed: opts=${opts}"
fi

# --- tmux pane plumbing, re-source behaviour vs baseline ---------------------
TMUX_SCRIPT='
echo "histfile=${HISTFILE}"
echo "prompt1=${PROMPT_COMMAND}"
echo "path1=${PATH}"
echo "'"${TMUX_ID_MOVED}"'" > "${HOME}/tmux_id"
_tmux_pane_hist_sync; echo "sync=$?"
echo "histfile_moved=${HISTFILE}"
source "${HOME}/.bashrc"
echo "prompt2=${PROMPT_COMMAND}"
echo "path2=${PATH}"
compgen -A function | sed "s/^/fn_resourced:/"
'
run_tmux_shell() {
    local home="$1"
    printf '%s\n' "${TMUX_ID_INITIAL}" > "${home}/tmux_id"
    run_bash "${home}" "${TMUX_SCRIPT}" TMUX=/tmp/e1-fake,1,0 TMUX_PANE="${TMUX_PANE_FIXTURE}"
}

echo "== tmux pane history plumbing"
run_tmux_shell "${NEW_HOME}"
assert_eq 0 "${RUN_STATUS}" "in-tmux interactive startup exits 0"
assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_INITIAL}.bash_history" \
    "$(out_value histfile "${NEW_HOME}")" "pane HISTFILE claimed at startup"
new_prompt1="$(out_value prompt1 "${NEW_HOME}")"
if [[ "${new_prompt1}" == "_tmux_pane_hist_sync || history -a; _tmux_log_last_cmd; "* ]]; then
    pass "history sync and last-command hooks registered"
else
    fail "unexpected PROMPT_COMMAND: ${new_prompt1}"
fi
assert_eq 0 "$(out_value sync "${NEW_HOME}")" "_tmux_pane_hist_sync follows a pane move"
assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_MOVED}.bash_history" \
    "$(out_value histfile_moved "${NEW_HOME}")" "_tmux_pane_hist_sync updates caller HISTFILE"
assert_file_contains "${NEW_HOME}/calls.log" "release ${TMUX_PANE_FIXTURE}" "old pane history released"
if [[ -f "${NEW_HOME}/.local/state/tmux/panes/.owner.${TMUX_PANE_FIXTURE}" ]]; then
    pass "_tmux_pane_hist_claim wrote owner file"
else
    fail "_tmux_pane_hist_claim owner file missing"
fi
new_prompt2="$(out_value prompt2 "${NEW_HOME}")"
if [[ "$(grep -o '_tmux_log_last_cmd' <<<"${new_prompt2}" | wc -l)" -eq 1 ]]; then
    pass "re-source keeps exactly one last-command hook"
else
    fail "re-source duplicated or lost the last-command hook: ${new_prompt2}"
fi
assert_set_eq "${EXPECTED_IDLE}" \
    "$(comm -12 <(functions_in resourced) <(printf '%s\n' "${REPO_FUNCS}"))" \
    "re-source: repository functions are exactly public + eager allowlist"
[[ "${new_prompt2}" != *_tmux_pane_hist_sync* ]] \
    && known "re-sourcing .bashrc drops the _tmux_pane_hist_sync hook (PROMPT_COMMAND reset + _TMUX_PANE_HIST_DIR guard)"
new_path2="$(out_value path2 "${NEW_HOME}")"
[[ "$(grep -o '<HOME>/bin:' <<<"${new_path2}" | wc -l)" -gt 1 ]] \
    && known "re-sourcing .bashrc duplicates ~/bin and ~/ai-wrapper/bin in PATH"

if (( have_baseline )); then
    new_values=()
    for key in histfile prompt1 path1 sync histfile_moved prompt2 path2; do
        new_values+=("${key}=$(out_value "${key}" "${NEW_HOME}")")
    done
    run_tmux_shell "${BASE_HOME}"
    idx=0
    for key in histfile prompt1 path1 sync histfile_moved prompt2 path2; do
        assert_eq "${new_values[${idx}]}" "${key}=$(out_value "${key}" "${BASE_HOME}")" \
            "tmux/re-source ${key} identical to pre-E1 baseline (no new regression)"
        idx=$((idx + 1))
    done
fi

# --- Source failure inside a wrapper -----------------------------------------
echo "== i3 wrapper source failure"
run_bash "${NEW_HOME}" 'rm -f "${HOME}/bin/helper/i3.bash"; i3_save_ws 1 >/dev/null 2>"${HOME}/i3_missing"; echo "st=$?"; echo "alive=yes"'
assert_eq 0 "${RUN_STATUS}" "shell survives a failed wrapper source (no recursion/timeout)"
assert_eq 1 "$(out_value st "${NEW_HOME}")" "wrapper returns the failed source status"
assert_eq yes "$(out_value alive "${NEW_HOME}")" "shell continues after failed wrapper source"
assert_file_contains "${NEW_HOME}/i3_missing" "i3.bash" "failed source reports the missing module"
cp "${REPO_ROOT}/bin/helper/i3.bash" "${NEW_HOME}/bin/helper/i3.bash"

# --- macOS module layout ------------------------------------------------------
echo "== Missing Linux-only modules (macOS layout)"
MAC_HOME="${TMP_ROOT}/macos"
deploy_tree "${REPO_ROOT}" "${MAC_HOME}" "${MACOS_SKIPPED_MODULES[@]}"
run_bash "${MAC_HOME}" 'compgen -A function | sed "s/^/fn_idle:/"; helper.bash tmux_session >/dev/null; echo "cli_tmux=$?"'
assert_eq 0 "${RUN_STATUS}" "macOS-layout interactive startup exits 0"
mac_expected="$(comm -23 <(printf '%s\n' "${EXPECTED_IDLE}") <(defined_functions \
    "${REPO_ROOT}/bin/helper/i3.bash" "${REPO_ROOT}/bin/helper/storage.bash" \
    "${REPO_ROOT}/bin/helper/utils.bash"))"
assert_set_eq "${mac_expected}" "$(comm -12 <(functions_in idle) <(printf '%s\n' "${REPO_FUNCS}"))" \
    "macOS layout: only present modules' public helpers (no dangling i3 wrappers)"
assert_eq 0 "$(out_value cli_tmux "${MAC_HOME}")" "macOS layout: script-mode tmux_session still dispatches"

# --- Zsh ----------------------------------------------------------------------
echo "== Zsh"
if command -v zsh >/dev/null 2>&1; then
    ZSH_OUT="$(cd "${NEW_HOME}" && env -i HOME="${NEW_HOME}" ZDOTDIR="${NEW_HOME}" TERM=xterm \
        PATH="${FAKEBIN}:/usr/bin:/bin" E1_CALL_LOG="${NEW_HOME}/calls.log" \
        timeout "${SHELL_TIMEOUT_SECONDS}" zsh -i -c '
            print -l ${(k)functions} | sed "s/^/fn:/"
            print "precmd1=${precmd_functions[*]}"
            source "${HOME}/.zshrc"
            print "precmd2=${precmd_functions[*]}"' 2>/dev/null)"
    zsh_repo="$(defined_functions "${REPO_ROOT}/dot_zshrc" \
        "${REPO_ROOT}/bin/helper/tmux_commands.bash" "${REPO_ROOT}/bin/helper/tmux_last_cmd.zsh")"
    assert_set_eq "$(sorted_words "${PUBLIC_ZSH[@]}" "${ALLOW_ZSH[@]}")" \
        "$(comm -12 <(printf '%s\n' "${ZSH_OUT}" | sed -n 's/^fn://p' | sort -u) \
            <(printf '%s\n' "${zsh_repo}" "${PRIVATE_BASH[@]}" | sort -u))" \
        "zsh: repository functions are exactly public + allowlist"
    precmd2="$(printf '%s\n' "${ZSH_OUT}" | sed -n 's/^precmd2=//p')"
    [[ "$(grep -o '_reset_ctrl_d_count' <<<"${precmd2}" | wc -l)" -gt 1 ]] \
        && known "re-sourcing .zshrc duplicates precmd_functions entries"
else
    gap "zsh not installed: Zsh namespace, Ctrl+D and re-source behaviour not verified here"
fi

# --- Source-body equivalence against the pre-E1 baseline ---------------------
if (( have_baseline )); then
    echo "== Source-body equivalence vs ${BASELINE_REF}"
    unchanged=(dot_bashrc dot_zshrc dot_xsessionrc dot_bash_completion.d/helper.bash
        dot_bash_completion.d/transfer.bash bin/executable_firefox_rofi.bash
        bin/executable_tmux_pane_hist_release.bash)
    for f in "${REPO_ROOT}/bin/helper/"*.bash "${REPO_ROOT}/bin/helper/"*.zsh; do
        case "${f##*/}" in
            tmux.bash|tmux_last_cmd.bash) ;;
            *) unchanged+=("bin/helper/${f##*/}") ;;
        esac
    done
    for f in "${unchanged[@]}"; do
        if cmp -s "${BASE_SRC}/${f}" "${REPO_ROOT}/${f}"; then
            pass "byte-identical: ${f}"
        else
            fail "changed vs baseline: ${f}"
        fi
    done
    base_tmux="${BASE_SRC}/bin/helper/tmux.bash"
    marker_line="$(grep -nF "${TMUX_PLUMBING_MARKER}" "${base_tmux}" | cut -d: -f1)"
    plumbing_bytes="$(tail -n +"${marker_line}" "${base_tmux}"; echo x)"
    new_plumbing="$(cat "${REPO_ROOT}/bin/helper/tmux_last_cmd.bash"; echo x)"
    if [[ -n "${marker_line}" && "${new_plumbing}" == *"${plumbing_bytes}" ]]; then
        pass "tmux_last_cmd.bash ends with the original plumbing block byte-for-byte"
    else
        fail "tmux_last_cmd.bash does not carry the original plumbing block"
    fi
    if [[ "$(grep -cF "${TMUX_PLUMBING_MARKER}" "${REPO_ROOT}/bin/helper/tmux_last_cmd.bash")" -eq 1 ]]; then
        pass "plumbing block present exactly once in tmux_last_cmd.bash"
    else
        fail "plumbing block missing or duplicated in tmux_last_cmd.bash"
    fi
    if cmp -s <(head -n $((marker_line - 1)) "${base_tmux}") \
        <(head -n $((marker_line - 1)) "${REPO_ROOT}/bin/helper/tmux.bash"); then
        pass "tmux.bash session builders and header byte-identical"
    else
        fail "tmux.bash session builders changed"
    fi
    if ! defined_functions "${REPO_ROOT}/bin/helper/tmux.bash" | grep -q '^_tmux_'; then
        pass "tmux.bash no longer duplicates the _tmux_* callbacks"
    else
        fail "tmux.bash still defines _tmux_* callbacks"
    fi
    extract_error_fn() { sed -n '/^show_error_and_usage() {$/,/^}$/p' "$1"; }
    extract_dispatch() { sed -n '/^## Main body of script$/,$p' "$1"; }
    if [[ -n "$(extract_error_fn "${REPO_ROOT}/bin/executable_helper.bash")" ]] \
        && cmp -s <(extract_error_fn "${BASE_SRC}/bin/executable_helper.bash") \
            <(extract_error_fn "${REPO_ROOT}/bin/executable_helper.bash"); then
        pass "helper.bash show_error_and_usage body byte-identical"
    else
        fail "helper.bash show_error_and_usage body changed"
    fi
    if cmp -s <(extract_dispatch "${BASE_SRC}/bin/executable_helper.bash") \
        <(extract_dispatch "${REPO_ROOT}/bin/executable_helper.bash"); then
        pass "helper.bash CLI dispatch table byte-identical"
    else
        fail "helper.bash CLI dispatch table changed"
    fi
fi

echo
echo "${failures} failure(s), ${gaps} verification gap(s)"
(( failures == 0 ))
