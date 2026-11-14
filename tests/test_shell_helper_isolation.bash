#!/usr/bin/env bash
# Interactive shells load the public hh_* helpers and the approved shell
# plumbing callbacks only; script-private helpers stay callable inside
# `helper.bash <command>` but never enter the shell. Re-sourcing the startup
# files is idempotent (prompt hooks, PATH, history file, zsh hooks).
#
# Leak detection is behavioural: after real interactive startup every live
# function is attributed to the file that defined it (bash `declare -F`
# under extdebug, zsh $functions_source). The functions defined by files in
# the sandbox HOME must be exactly the public helpers plus the allowlisted
# plumbing (plus the vendor completion fixture); functions from system
# files (bash-completion, zsh's fpath) are not ours and are ignored.
#
# Per-helper behaviour and zsh parity live in tests/test_hh_public_api.bash.
# Sandbox: tests/lib/shell_fixture.bash (synthetic HOME, env -i, fakes).
# Missing zsh is a SKIP (a failure under CI / TESTS_STRICT=1).
#
# Usage: bash tests/test_shell_helper_isolation.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"
tests_init_tmp hh-isolation
# shellcheck source=tests/lib/shell_fixture.bash
source "${REPO_ROOT}/tests/lib/shell_fixture.bash"
make_fakebin

TMUX_PANE_FIXTURE="%7"
TMUX_ID_MOVED="main:2.0"
FAKE_TMUX="/tmp/fixture-tmux,1,0"
# Caller PATH with an unrelated duplicate (/usr/bin twice) that must survive
# while the managed entries are added once.
SEEDED_PATH="${FAKEBIN}:/usr/bin:/bin:/usr/bin"
EXPECTED_PATH="<HOME>/bin:<HOME>/ai-wrapper/bin:${SEEDED_PATH}"

PUBLIC=(hh_colors hh_unar hh_tmux_restore hh_git_watch hh_git_cleanout
    hh_sshfsctl hh_gio_mount hh_gio_umount hh_upgrade_system hh_yay_no_cache
    hh_adb_pull_music hh_unzip_books hh_cut_video hh_gpg_decrypt hh_gpg_encrypt
    hh_rsync_ssh hh_rm_ssh hh_i3_save_chezmoi_ws hh_i3_save_ws hh_i3_restore_ws)
# Public helpers of the Linux-only modules chezmoi skips on macOS.
MACOS_SKIPPED_MODULES=(firefox i3 storage system utils)
LINUX_ONLY_PUBLIC=(hh_i3_save_chezmoi_ws hh_i3_save_ws hh_i3_restore_ws
    hh_sshfsctl hh_gio_mount hh_gio_umount hh_upgrade_system hh_yay_no_cache
    hh_adb_pull_music hh_unzip_books hh_cut_video hh_gpg_decrypt hh_gpg_encrypt)
# Owner-approved Bash plumbing: prompt/history callbacks and completion.
ALLOW_BASH=(_bashrc_git_branch _tmux_log_last_cmd _tmux_pane_hist_path
    _tmux_pane_hist_claim _tmux_pane_hist_sync _helper_script
    _rsync_ssh_complete _rm_ssh_complete _ssh_config_hosts)
# Defined only once host completion has run (nested in _ssh_config_hosts).
ALLOW_BASH_LAZY=(_flush)
VENDOR_FIXTURE=(_vendor_fixture_complete)
ALLOW_ZSH=(_ctrl_d_exit _reset_ctrl_d_count _tmux_log_last_cmd
    _tmux_pane_hist_path _tmux_pane_hist_claim _tmux_pane_hist_detect
    _tmux_pane_hist_addhistory _tmux_pane_hist_sync)

words() { printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort -u; }
# without <set> <word...>: set minus the words.
without() {
    local set="$1"
    shift
    LC_ALL=C comm -23 <(printf '%s\n' "${set}") <(words "$@")
}

# Probes: print "fn_<phase>:<name>" for every function defined by a file in
# the sandbox HOME.
BASH_PROBE='
home_functions() {
    local n _line file
    shopt -s extdebug
    for n in $(compgen -A function); do
        read -r _ _line file < <(declare -F "${n}")
        [[ "${file}" == "${HOME}/"* ]] && printf "fn_%s:%s\n" "$1" "${n}"
    done
    shopt -u extdebug
}
'
ZSH_PROBE='
home_functions() {
    local n
    for n in ${(k)functions}; do
        [[ ${functions_source[${n}]} == ${HOME}/* ]] && print -r -- "fn_$1:${n}"
    done
}
'
functions_in() { printf '%s\n' "${RUN_STDOUT}" | sed -n "s/^fn_$1://p" | LC_ALL=C sort -u; }

# Print "+name" / "-name" for how actual differs from expected.
assert_set_eq() {
    local expected="$1" actual="$2" label="$3" delta
    delta="$(LC_ALL=C comm -3 <(printf '%s\n' "${expected}" | sed '/^$/d') \
        <(printf '%s\n' "${actual}" | sed '/^$/d') | sed -E 's/^\t/+/; t; s/^/-/' | tr '\n' ' ')"
    if [[ -z "${delta}" ]]; then
        pass "${label}"
    else
        fail "${label}: ${delta}"
    fi
}

# assert_clean_startup <label>: the probe ran to the end with status 0, the
# rc file's own status (first thing the probe records) was 0, and nothing
# but bash's no-terminal job-control notice reached stderr.
assert_clean_startup() {
    local label="$1" noise
    assert_status 0 "${RUN_STATUS}" "${label}: probe exits 0"
    assert_contains "${RUN_STDOUT}" "PROBE_DONE" "${label}: probe ran to completion"
    assert_eq 0 "$(out_value startup_status "")" "${label}: rc file finished with status 0"
    noise="$(startup_noise_filtered)"
    assert_eq "" "${noise}" "${label}: nothing on stderr"
}
STARTUP_STATUS='echo "startup_status=$?"'
hook_count() { grep -o -- "$1" <<< "$2" | wc -l | tr -d ' '; }

# --- Bash: function set at startup and after use -------------------------------
scenario_bash_function_set() {
    local home expected
    home="$(new_home bash-functions)" || return
    run_bash "${home}" "${STARTUP_STATUS}${BASH_PROBE}"'
home_functions idle
{
    hh_rsync_ssh -h
    hh_unar "${HOME}/nofile"
    hh_i3_save_ws 1
    hh_i3_restore_ws 1
    hh_gio_mount; cd "${HOME}"
    hh_sshfsctl help
    declare -a hosts=(); _ssh_config_hosts hosts
    helper.bash volume mute
    helper.bash e1_unknown
} > /dev/null 2>&1
home_functions after
echo PROBE_DONE'
    assert_clean_startup "bash startup"
    expected="$(words "${PUBLIC[@]}" "${ALLOW_BASH[@]}" "${VENDOR_FIXTURE[@]}")"
    assert_set_eq "${expected}" "$(functions_in idle)" \
        "bash idle: functions from HOME files are exactly public + allowlist + vendor fixture"
    assert_set_eq "$(words ${expected} "${ALLOW_BASH_LAZY[@]}")" "$(functions_in after)" \
        "bash after public calls, completion and script mode: only the lazy _flush was added"
}

# --- Bash: script mode still reaches the private helpers -------------------------
scenario_bash_script_mode() {
    local home
    home="$(new_home bash-script-mode)" || return
    run_bash "${home}" '
helper.bash volume mute > /dev/null; echo "volume=$?"
helper.bash volume bogus > "${HOME}/usage.out"; echo "volume_bad=$?"
helper.bash firefox > /dev/null; echo "firefox=$?"
helper.bash e1_unknown > "${HOME}/unknown.out"; echo "unknown=$?"
helper.bash rclone_bisync --flag "src dir" dst > /dev/null 2>&1; echo "rclone=$?"
echo PROBE_DONE'
    assert_contains "${RUN_STDOUT}" PROBE_DONE "script mode: probe ran to completion"
    assert_eq 0 "$(out_value volume "${home}")" "script mode: volume mute exits 0"
    assert_file_contains "${home}/fake.log" "pactl [set-sink-mute] [@DEFAULT_SINK@] [toggle]" \
        "script mode: set_volume reached pactl"
    assert_file_contains "${home}/fake.log" "dunstify [-a] [changeVolume]" \
        "script mode: send_notification_volume ran"
    assert_eq 1 "$(out_value volume_bad "${home}")" "script mode: bad volume action exits 1"
    assert_file_contains "${home}/usage.out" "volume [-s pulseaudio_sink_name] action" \
        "script mode: nested print_usage ran"
    assert_eq 0 "$(out_value firefox "${home}")" "script mode: firefox picker exits 0"
    assert_file_contains "${home}/fake.log" "rofi-menu: Personal (fixtureprofile)" \
        "script mode: firefox picker offered the profile from profiles.ini"
    assert_eq 1 "$(out_value unknown "${home}")" "script mode: unknown command exits 1"
    assert_file_contains "${home}/unknown.out" 'Unknown command "e1_unknown"' \
        "script mode: unknown command reported"
    assert_file_contains "${home}/unknown.out" "volume|" "script mode: usage lists the commands"
    assert_eq 0 "$(out_value rclone "${home}")" "script mode: rclone_bisync exits 0"
    assert_file_contains "${home}/fake.log" \
        "rclone [--log-systemd] [--log-level] [INFO] [--auto-confirm] [--human-readable] [--modify-window] [24h] [bisync] [--flag] [src dir] [dst]" \
        "script mode: rclone_systemd passed arguments through"
}

# --- Bash: re-sourcing ~/.bashrc ---------------------------------------------------
BASH_RESOURCE_PROBE='
echo "histfile=${HISTFILE}"
echo "prompt1=${PROMPT_COMMAND}"
echo "path1=${PATH}"
if [[ -n "${MOVE_PANE:-}" ]]; then
    echo "'"${TMUX_ID_MOVED}"'" > "${HOME}/tmux_id"
    _tmux_pane_hist_sync; echo "sync=$?"
fi
echo "histfile_moved=${HISTFILE}"
source "${HOME}/.bashrc"
echo "resource_status=$?"
echo "prompt2=${PROMPT_COMMAND}"
echo "path2=${PATH}"
echo "histfile2=${HISTFILE}"
home_functions resourced
echo PROBE_DONE'

# scenario_bash_resource <outside|valid|failed>: outside tmux, in a pane
# whose id lookup works, in a pane whose lookup fails.
scenario_bash_resource() {
    local mode="$1" home prompt1 prompt2 histfile
    home="$(new_home "bash-resource-${mode}")" || return
    local -a env=(PATH="${SEEDED_PATH}")
    case "${mode}" in
        valid) env+=(TMUX="${FAKE_TMUX}" TMUX_PANE="${TMUX_PANE_FIXTURE}" MOVE_PANE=1) ;;
        failed) : > "${home}/tmux_id"; env+=(TMUX="${FAKE_TMUX}" TMUX_PANE="${TMUX_PANE_FIXTURE}") ;;
    esac
    run_bash "${home}" "${STARTUP_STATUS}${BASH_PROBE}${BASH_RESOURCE_PROBE}" "${env[@]}"
    assert_clean_startup "bash ${mode}"
    assert_eq 0 "$(out_value resource_status "${home}")" "bash ${mode}: re-source exits 0"
    prompt1="$(out_value prompt1 "${home}")"
    prompt2="$(out_value prompt2 "${home}")"
    assert_eq "${prompt1}" "${prompt2}" "bash ${mode}: re-source keeps PROMPT_COMMAND identical"
    assert_eq 1 "$(hook_count _tmux_log_last_cmd "${prompt2}")" "bash ${mode}: one last-command hook"
    assert_eq "${EXPECTED_PATH}" "$(out_value path1 "${home}")" "bash ${mode}: managed PATH entries added once"
    assert_eq "${EXPECTED_PATH}" "$(out_value path2 "${home}")" "bash ${mode}: PATH unchanged by re-source"
    assert_set_eq "$(words "${PUBLIC[@]}" "${ALLOW_BASH[@]}" "${VENDOR_FIXTURE[@]}")" "$(functions_in resourced)" \
        "bash ${mode}: re-source defines no extra functions"
    histfile="<HOME>/.local/state/tmux/panes"
    if [[ "${mode}" == valid ]]; then
        assert_eq 1 "$(hook_count _tmux_pane_hist_sync "${prompt2}")" "bash valid: one pane history hook"
        assert_eq "${histfile}/${TMUX_ID_INITIAL}.bash_history" "$(out_value histfile "${home}")" \
            "bash valid: pane HISTFILE claimed at startup"
        assert_eq 0 "$(out_value sync "${home}")" "bash valid: history sync after a pane move exits 0"
        assert_eq "${histfile}/${TMUX_ID_MOVED}.bash_history" "$(out_value histfile_moved "${home}")" \
            "bash valid: pane move updates HISTFILE"
        assert_eq "${histfile}/${TMUX_ID_MOVED}.bash_history" "$(out_value histfile2 "${home}")" \
            "bash valid: re-source keeps the moved pane HISTFILE (no re-claim)"
    else
        assert_eq 0 "$(hook_count _tmux_pane_hist_sync "${prompt1}${prompt2}")" \
            "bash ${mode}: no pane history hook"
        assert_eq "<HOME>/.bash_history" "$(out_value histfile2 "${home}")" "bash ${mode}: default HISTFILE"
    fi
}

# --- Bash: i3 wrapper whose module disappeared after startup -------------------------
scenario_bash_i3_wrapper_source_failure() {
    local home
    home="$(new_home bash-i3-missing)" || return
    run_bash "${home}" '
rm -f "${HOME}/bin/helper/i3.bash"
hh_i3_save_ws 1 > /dev/null 2> "${HOME}/i3.err"; echo "status=$?"
echo PROBE_DONE'
    assert_contains "${RUN_STDOUT}" PROBE_DONE "i3 wrapper: shell survives a failed module source"
    assert_eq 1 "$(out_value status "${home}")" "i3 wrapper: returns the failed source status"
    assert_file_contains "${home}/i3.err" "i3.bash" "i3 wrapper: error names the missing module"
}

# --- macOS module layout -------------------------------------------------------------
scenario_bash_macos_layout() {
    local home
    home="$(new_home bash-macos "${MACOS_SKIPPED_MODULES[@]}")" || return
    run_bash "${home}" "${STARTUP_STATUS}${BASH_PROBE}"'
home_functions idle
helper.bash rclone_bisync src dst > /dev/null 2>&1; echo "script_mode=$?"
echo PROBE_DONE'
    assert_clean_startup "bash macOS layout"
    assert_set_eq "$(without "$(words "${PUBLIC[@]}" "${ALLOW_BASH[@]}" "${VENDOR_FIXTURE[@]}")" "${LINUX_ONLY_PUBLIC[@]}")" \
        "$(functions_in idle)" "bash macOS layout: only the present modules' helpers (no dangling wrappers)"
    assert_eq 0 "$(out_value script_mode "${home}")" "bash macOS layout: script mode still dispatches"
}

# --- zsh ---------------------------------------------------------------------------
ZSH_SCRIPT='
home_functions idle
print -r -- "precmd1=${precmd_functions[*]}"
print -r -- "addhist1=${zshaddhistory_functions[*]}"
print -r -- "path1=${PATH}"
print -r -- "histfile=${HISTFILE}"
precmd_functions+=(vendor_hook)
{
    hh_i3_save_ws 1
    hh_rsync_ssh -h
    hh_unar "${HOME}/nofile"
    hh_gio_mount; cd "${HOME}"
    hh_sshfsctl help
} > /dev/null 2>&1
home_functions after
source "${HOME}/.zshrc"
print -r -- "resource_status=$?"
print -r -- "precmd2=${precmd_functions[*]}"
print -r -- "addhist2=${zshaddhistory_functions[*]}"
print -r -- "path2=${PATH}"
home_functions resourced
echo PROBE_DONE'

scenario_zsh() {
    local mode="$1" home phase precmd1 expected
    home="$(new_home "zsh-${mode}")" || return
    local -a env=(PATH="${SEEDED_PATH}")
    case "${mode}" in
        valid) env+=(TMUX="${FAKE_TMUX}" TMUX_PANE="${TMUX_PANE_FIXTURE}") ;;
        failed) : > "${home}/tmux_id"; env+=(TMUX="${FAKE_TMUX}" TMUX_PANE="${TMUX_PANE_FIXTURE}") ;;
    esac
    run_zsh "${home}" "${STARTUP_STATUS}${ZSH_PROBE}${ZSH_SCRIPT}" "${env[@]}"
    assert_clean_startup "zsh ${mode}"
    assert_eq 0 "$(out_value resource_status "${home}")" "zsh ${mode}: re-source exits 0"
    expected="$(words "${PUBLIC[@]}" "${ALLOW_ZSH[@]}")"
    for phase in idle after resourced; do
        assert_set_eq "${expected}" "$(functions_in "${phase}")" \
            "zsh ${mode} ${phase}: functions from HOME files are exactly public + zsh allowlist"
    done
    precmd1="$(out_value precmd1 "${home}")"
    assert_eq "${precmd1} vendor_hook" "$(out_value precmd2 "${home}")" \
        "zsh ${mode}: re-source adds no duplicate precmd hook and keeps a vendor hook"
    assert_eq "$(out_value addhist1 "${home}")" "$(out_value addhist2 "${home}")" \
        "zsh ${mode}: zshaddhistory hooks unchanged by re-source"
    assert_eq 1 "$(hook_count _tmux_log_last_cmd "${precmd1}")" "zsh ${mode}: one last-command hook"
    assert_eq "${EXPECTED_PATH}" "$(out_value path1 "${home}")" "zsh ${mode}: managed PATH entries added once"
    assert_eq "${EXPECTED_PATH}" "$(out_value path2 "${home}")" "zsh ${mode}: PATH unchanged by re-source"
    if [[ "${mode}" == valid ]]; then
        assert_eq 1 "$(hook_count _tmux_pane_hist_sync "${precmd1}")" "zsh valid: one pane history hook"
        assert_eq "_tmux_pane_hist_addhistory" "$(out_value addhist1 "${home}")" \
            "zsh valid: zshaddhistory hook registered"
        assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_INITIAL}.zsh_history" \
            "$(out_value histfile "${home}")" "zsh valid: pane HISTFILE claimed"
    else
        assert_eq 0 "$(hook_count _tmux_pane_hist_sync "${precmd1}")" "zsh ${mode}: no pane history hook"
        assert_eq "" "$(out_value addhist1 "${home}")" "zsh ${mode}: no zshaddhistory hook"
    fi
}

scenario_zsh_macos_layout() {
    local home
    home="$(new_home zsh-macos "${MACOS_SKIPPED_MODULES[@]}")" || return
    run_zsh "${home}" "${STARTUP_STATUS}${ZSH_PROBE}"'
home_functions idle
echo PROBE_DONE'
    assert_clean_startup "zsh macOS layout"
    assert_set_eq "$(without "$(words "${PUBLIC[@]}" "${ALLOW_ZSH[@]}")" "${LINUX_ONLY_PUBLIC[@]}")" \
        "$(functions_in idle)" "zsh macOS layout: only the present modules' helpers"
}

echo "== Bash"
scenario_bash_function_set
scenario_bash_script_mode
for mode in outside valid failed; do
    scenario_bash_resource "${mode}"
done
scenario_bash_i3_wrapper_source_failure
scenario_bash_macos_layout

echo "== zsh"
if require_cmd "zsh function set, re-source and macOS layout" zsh; then
    for mode in outside valid failed; do
        scenario_zsh "${mode}"
    done
    scenario_zsh_macos_layout
fi

tests_finish
