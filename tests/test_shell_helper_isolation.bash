#!/usr/bin/env bash
# Regression test for issues #59 (E1) and #60 (E2): interactive shells load
# the public hh_* helpers and the owner-approved shell-plumbing callbacks
# only; script-private helpers stay callable inside `helper.bash <command>`
# but never enter the shell. Re-sourcing the startup files is idempotent
# (prompt hooks, PATH, zsh precmd hooks), and every implementation body is
# byte-identical to the fixed pre-E1 baseline except the approved hh_
# public/caller renames, the job_mount/job_umount removal and moves.
#
# Shells run in the synthetic sandbox from tests/lib/shell_fixture.bash
# (synthetic HOME, env -i, logging fakes first on PATH). No real startup
# file, runtime ~/bin/.env, job setup file, client, mount, service or live
# tmux server is touched. The three re-source defects E1 characterised are
# asserted fixed here and shown present in the baseline by the same probes.
# Missing zsh or a missing baseline commit is reported as GAP.
#
# Usage: bash tests/test_shell_helper_isolation.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Pre-E1 integration head (agent/feature-55 merge-base of this work package).
BASELINE_REF="${E1_BASELINE_REF:-0d46a7f7df3be7c8a79d8cad5e30c9176b28d7d7}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/e1-isolation.XXXXXX")"
TMUX_PANE_FIXTURE="%7"
TMUX_ID_MOVED="main:2.0"
TMUX_PLUMBING_MARKER="# Record the last-typed shell command per tmux pane"

trap 'rm -rf "${TMP_ROOT}"' EXIT
# shellcheck source=tests/lib/shell_fixture.bash
source "${REPO_ROOT}/tests/lib/shell_fixture.bash"

failures=0
gaps=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }
gap() { printf 'GAP: %s\n' "$1"; gaps=$((gaps + 1)); }

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
# Public interactive helpers: the owner-approved hh_ namespace (#60).
PUBLIC_BASH=(hh_colors hh_unar hh_tmux_restore hh_git_watch hh_git_cleanout
    hh_sshfsctl hh_gio_mount hh_gio_umount hh_upgrade_system hh_yay_no_cache
    hh_adb_pull_music hh_unzip_books hh_cut_video hh_gpg_decrypt hh_gpg_encrypt
    hh_rsync_ssh hh_rm_ssh hh_i3_save_chezmoi_ws hh_i3_save_ws hh_i3_restore_ws)
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
# zsh exposes the same public helpers (in-process or via bash_exec.zsh).
PUBLIC_ZSH=("${PUBLIC_BASH[@]}")
ALLOW_ZSH=(_ctrl_d_exit _reset_ctrl_d_count _tmux_log_last_cmd
    _tmux_pane_hist_path _tmux_pane_hist_claim _tmux_pane_hist_detect
    _tmux_pane_hist_addhistory _tmux_pane_hist_sync)
# Linux-only helpers chezmoi skips on macOS (.chezmoiignore).
MACOS_SKIPPED_MODULES=(firefox i3 storage system utils)
# Approved public renames (#60), applied to the fixed baseline before every
# body comparison. colors/ex are renamed at their definition line only.
RENAMED_PUBLIC='tmux_restore|git_watch|git_cleanout|sshfsctl|gio_mount|gio_umount|upgrade_system|yay_no_cache|adb_pull_music|unzip_books|cut_video|gpg_decrypt|gpg_encrypt|rsync_ssh|rm_ssh|cp_ssh|i3_save_chezmoi_ws|i3_save_ws|i3_restore_ws'
# Functions the owner approved for removal (#60).
REMOVED_FUNCS=(job_mount job_umount)

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

rename_public() {
    sed -E "s/\\b(${RENAMED_PUBLIC})\\b/hh_\\1/g; s/^colors\\(\\) \\{\$/hh_colors() {/; s/^ex \\(\\)\$/hh_unar ()/; s/extracted via ex\\(\\)/extracted via hh_unar()/" "$@"
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
hh_i3_save_chezmoi_ws >/dev/null; echo "i3_all=$?"
hh_i3_save_ws 1 >/dev/null; echo "i3_one=$?"
hh_i3_save_ws 0 2>"${HOME}/i3_err" >/dev/null; echo "i3_bad=$?"
hh_i3_restore_ws 1 >/dev/null; echo "i3_restore=$?"
echo "cmd=${cmd}"
helper.bash volume mute >/dev/null; echo "cli_volume=$?"
helper.bash volume bogus > "${HOME}/usage.out"; echo "cli_usage=$?"
helper.bash firefox >/dev/null; echo "cli_firefox=$?"
helper.bash e1_unknown > "${HOME}/unknown.out"; echo "cli_unknown=$?"
helper.bash rclone_bisync --e1 src dst >/dev/null; echo "cli_rclone=$?"
helper.bash tmux_session >/dev/null; echo "cli_tmux=$?"
echo "opts_same=$([[ "$-" == "${opts_before}" ]] && echo yes || echo no)"
echo "env=${E1_ENV_SENTINEL}"
hh_rsync_ssh -h >/dev/null; echo "rsync_help=$?"
declare -a e1_hosts=()
_ssh_config_hosts e1_hosts
echo "hosts=${e1_hosts[*]}"
hh_gio_mount; echo "gio_mount=$?"
echo "pwd=${PWD}"
hh_gio_umount; echo "gio_umount=$?"
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
assert_eq 0 "$(out_value i3_all "${NEW_HOME}")" "hh_i3_save_chezmoi_ws succeeds through wrapper"
assert_eq 0 "$(out_value i3_one "${NEW_HOME}")" "hh_i3_save_ws succeeds through wrapper"
assert_eq 1 "$(out_value i3_bad "${NEW_HOME}")" "hh_i3_save_ws failure status propagates"
assert_file_contains "${NEW_HOME}/i3_err" "workspace number must be 1-9" "hh_i3_save_ws failure stderr propagates"
assert_eq 0 "$(out_value i3_restore "${NEW_HOME}")" "hh_i3_restore_ws succeeds through wrapper"
assert_file_contains "${NEW_HOME}/calls.log" "i3-msg workspace 1; append_layout" "hh_i3_restore_ws reached i3-msg"
ws_file="${NEW_HOME}/.config/i3/workspaces/workspace_1-$(uname -n).json"
assert_file_contains "${ws_file}" '"class": "^E1$"' "i3 wrapper ran unchanged _i3_clean_layout body"
assert_eq E1_CALLER_CMD "$(out_value cmd "${NEW_HOME}")" "caller cmd variable untouched by hh_i3_save_chezmoi_ws loop"
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
assert_eq 0 "$(out_value rsync_help "${NEW_HOME}")" "hh_rsync_ssh -h works in-process"
assert_eq "bob@alpha beta" "$(out_value hosts "${NEW_HOME}")" "_ssh_config_hosts completion helper works"
assert_eq 0 "$(out_value gio_mount "${NEW_HOME}")" "hh_gio_mount succeeds"
assert_eq "<HOME>/mnt/phone" "$(out_value pwd "${NEW_HOME}")" "hh_gio_mount changes caller directory"
assert_eq 0 "$(out_value gio_umount "${NEW_HOME}")" "hh_gio_umount succeeds"
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


# --- Caller shell options from hh_sshfsctl (stateful public API) ------------
echo "== hh_sshfsctl keeps its in-process caller option contract"
run_bash "${NEW_HOME}" 'hh_sshfsctl -h >/dev/null; echo "st=$?"; echo "opts=$-"; echo "pf=$(set -o | grep -c "pipefail.*on")"'
assert_eq 0 "$(out_value st "${NEW_HOME}")" "hh_sshfsctl -h succeeds"
opts="$(out_value opts "${NEW_HOME}")"
if [[ "${opts}" == *e* && "${opts}" == *u* && "$(out_value pf "${NEW_HOME}")" == 1 ]]; then
    pass "hh_sshfsctl still sets errexit/nounset/pipefail in caller (unchanged body)"
else
    fail "hh_sshfsctl caller option contract changed: opts=${opts}"
fi

# --- Bash startup and re-source: tmux pane plumbing, PATH --------------------
# Seeded caller PATH carries an unrelated duplicate (/usr/bin twice) that
# must survive untouched while the managed entries are added once.
SEEDED_PATH="${FAKEBIN}:/usr/bin:/bin:/usr/bin"
RESOURCE_KEYS=(histfile prompt1 path1 sync histfile_moved prompt2 path2 histfile2)
TMUX_SCRIPT='
echo "histfile=${HISTFILE}"
echo "prompt1=${PROMPT_COMMAND}"
echo "path1=${PATH}"
if [[ -n "${E1_SIMULATE_MOVE:-}" ]]; then
    echo "'"${TMUX_ID_MOVED}"'" > "${HOME}/tmux_id"
    _tmux_pane_hist_sync; echo "sync=$?"
fi
echo "histfile_moved=${HISTFILE}"
source "${HOME}/.bashrc"
echo "prompt2=${PROMPT_COMMAND}"
echo "path2=${PATH}"
echo "histfile2=${HISTFILE}"
compgen -A function | sed "s/^/fn_resourced:/"
'
# run_resource_shell <home> <outside|valid|failed>
run_resource_shell() {
    local home="$1" mode="$2"
    case "${mode}" in
        outside)
            run_bash "${home}" "${TMUX_SCRIPT}" PATH="${SEEDED_PATH}"
            ;;
        valid)
            printf '%s\n' "${TMUX_ID_INITIAL}" > "${home}/tmux_id"
            run_bash "${home}" "${TMUX_SCRIPT}" PATH="${SEEDED_PATH}" \
                TMUX=/tmp/e1-fake,1,0 TMUX_PANE="${TMUX_PANE_FIXTURE}" E1_SIMULATE_MOVE=1
            ;;
        failed)
            : > "${home}/tmux_id"
            run_bash "${home}" "${TMUX_SCRIPT}" PATH="${SEEDED_PATH}" \
                TMUX=/tmp/e1-fake,1,0 TMUX_PANE="${TMUX_PANE_FIXTURE}"
            ;;
    esac
}
hook_count() { grep -o "$1" <<<"$2" | wc -l | tr -d ' '; }
EXPECTED_PATH="<HOME>/bin:<HOME>/ai-wrapper/bin:${SEEDED_PATH}"

echo "== Bash in valid tmux pane: history plumbing and re-source"
run_resource_shell "${NEW_HOME}" valid
assert_eq 0 "${RUN_STATUS}" "in-tmux interactive startup exits 0"
assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_INITIAL}.bash_history" \
    "$(out_value histfile "${NEW_HOME}")" "pane HISTFILE claimed at startup"
new_prompt1="$(out_value prompt1 "${NEW_HOME}")"
if [[ "${new_prompt1}" == "_tmux_pane_hist_sync || history -a; _tmux_log_last_cmd; "* ]]; then
    pass "history sync and last-command hooks registered in baseline order"
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
assert_eq "${new_prompt1}" "${new_prompt2}" "re-source restores the identical PROMPT_COMMAND"
assert_eq 1 "$(hook_count _tmux_pane_hist_sync "${new_prompt2}")" "re-source keeps exactly one history sync hook"
assert_eq 1 "$(hook_count _tmux_log_last_cmd "${new_prompt2}")" "re-source keeps exactly one last-command hook"
assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_MOVED}.bash_history" \
    "$(out_value histfile2 "${NEW_HOME}")" "re-source keeps the moved pane HISTFILE (no re-claim)"
assert_eq "${EXPECTED_PATH}" "$(out_value path1 "${NEW_HOME}")" "managed PATH entries prepended once at startup"
assert_eq "$(out_value path1 "${NEW_HOME}")" "$(out_value path2 "${NEW_HOME}")" \
    "re-source leaves PATH unchanged (no duplicates, unrelated duplicate kept)"
assert_set_eq "${EXPECTED_IDLE}" \
    "$(comm -12 <(functions_in resourced) <(printf '%s\n' "${REPO_FUNCS}"))" \
    "re-source: repository functions are exactly public + eager allowlist"

if (( have_baseline )); then
    new_values=()
    for key in "${RESOURCE_KEYS[@]}"; do
        new_values+=("${key}=$(out_value "${key}" "${NEW_HOME}")")
    done
    run_resource_shell "${BASE_HOME}" valid
    idx=0
    for key in "${RESOURCE_KEYS[@]}"; do
        case "${key}" in
            prompt2|path2) ;;
            *) assert_eq "${new_values[${idx}]}" "${key}=$(out_value "${key}" "${BASE_HOME}")" \
                "valid tmux ${key} identical to pre-E1 baseline" ;;
        esac
        idx=$((idx + 1))
    done
    base_prompt2="$(out_value prompt2 "${BASE_HOME}")"
    base_path2="$(out_value path2 "${BASE_HOME}")"
    if [[ "${base_prompt2}" != *_tmux_pane_hist_sync* ]]; then
        pass "control: same probe shows baseline re-source dropping _tmux_pane_hist_sync"
    else
        fail "control: baseline re-source unexpectedly kept _tmux_pane_hist_sync"
    fi
    if [[ "$(hook_count '<HOME>/bin:' "${base_path2}")" -gt 1 ]]; then
        pass "control: same probe shows baseline re-source duplicating PATH entries"
    else
        fail "control: baseline PATH duplication not detected: ${base_path2}"
    fi
fi

for mode in outside failed; do
    case "${mode}" in
        outside) echo "== Bash outside tmux: startup and re-source" ;;
        failed) echo "== Bash in tmux with failed pane lookup: startup and re-source" ;;
    esac
    run_resource_shell "${NEW_HOME}" "${mode}"
    assert_eq 0 "${RUN_STATUS}" "${mode}: interactive startup exits 0"
    prompt1="$(out_value prompt1 "${NEW_HOME}")"
    prompt2="$(out_value prompt2 "${NEW_HOME}")"
    assert_eq 0 "$(hook_count _tmux_pane_hist_sync "${prompt1}${prompt2}")" \
        "${mode}: no pane history hook installed at startup or re-source"
    assert_eq 1 "$(hook_count _tmux_log_last_cmd "${prompt2}")" "${mode}: one last-command hook after re-source"
    assert_eq "${prompt1}" "${prompt2}" "${mode}: re-source restores the identical PROMPT_COMMAND"
    assert_eq "<HOME>/.bash_history" "$(out_value histfile "${NEW_HOME}")" "${mode}: default HISTFILE kept"
    assert_eq "${EXPECTED_PATH}" "$(out_value path2 "${NEW_HOME}")" "${mode}: PATH unchanged by re-source"
    if (( have_baseline )); then
        new_prompt1="${prompt1}"
        new_histfile="$(out_value histfile "${NEW_HOME}")"
        run_resource_shell "${BASE_HOME}" "${mode}"
        assert_eq "${new_prompt1}" "$(out_value prompt1 "${BASE_HOME}")" "${mode}: startup PROMPT_COMMAND identical to baseline"
        assert_eq "${new_histfile}" "$(out_value histfile "${BASE_HOME}")" "${mode}: HISTFILE identical to baseline"
    fi
done

# --- Source failure inside a wrapper -----------------------------------------
echo "== i3 wrapper source failure"
run_bash "${NEW_HOME}" 'rm -f "${HOME}/bin/helper/i3.bash"; hh_i3_save_ws 1 >/dev/null 2>"${HOME}/i3_missing"; echo "st=$?"; echo "alive=yes"'
assert_eq 0 "${RUN_STATUS}" "shell survives a failed wrapper source (no recursion/timeout)"
assert_eq 1 "$(out_value st "${NEW_HOME}")" "wrapper returns the failed source status"
assert_eq yes "$(out_value alive "${NEW_HOME}")" "shell continues after failed wrapper source"
assert_file_contains "${NEW_HOME}/i3_missing" "i3.bash" "failed source reports the missing module"
cp "${REPO_ROOT}/bin/helper/i3.bash" "${NEW_HOME}/bin/helper/i3.bash"

# --- macOS module layout ------------------------------------------------------
echo "== Missing Linux-only modules (macOS layout)"
MAC_HOME="${TMP_ROOT}/macos"
deploy_tree "${REPO_ROOT}" "${MAC_HOME}" "${MACOS_SKIPPED_MODULES[@]}"
run_bash "${MAC_HOME}" 'compgen -A function | sed "s/^/fn_idle:/"; helper.bash tmux_session >/dev/null; echo "cli_tmux=$?"; hh_unar "${HOME}/nofile"; echo "ex=$?"'
assert_eq 0 "${RUN_STATUS}" "macOS-layout interactive startup exits 0"
MAC_ONLY_LINUX_FUNCS="$(defined_functions "${REPO_ROOT}/bin/helper/i3.bash" \
    "${REPO_ROOT}/bin/helper/storage.bash" "${REPO_ROOT}/bin/helper/utils.bash")"
mac_expected="$(comm -23 <(printf '%s\n' "${EXPECTED_IDLE}") <(printf '%s\n' "${MAC_ONLY_LINUX_FUNCS}"))"
assert_set_eq "${mac_expected}" "$(comm -12 <(functions_in idle) <(printf '%s\n' "${REPO_FUNCS}"))" \
    "macOS layout: only present modules' public helpers (no dangling i3 wrappers)"
if printf '%s\n' "${mac_expected}" | grep -qx hh_colors && printf '%s\n' "${mac_expected}" | grep -qx hh_unar; then
    pass "macOS layout keeps formerly unconditional hh_colors/hh_unar"
else
    fail "macOS layout lost hh_colors/hh_unar"
fi
assert_eq 0 "$(out_value ex "${MAC_HOME}")" "macOS layout: hh_unar runs"
assert_eq 0 "$(out_value cli_tmux "${MAC_HOME}")" "macOS layout: script-mode tmux_session still dispatches"

# --- Zsh ----------------------------------------------------------------------
echo "== Zsh"
OLD_NAMES=(colors ex tmux_restore git_watch git_cleanout sshfsctl gio_mount
    gio_umount job_mount job_umount upgrade_system yay_no_cache adb_pull_music
    unzip_books cut_video gpg_decrypt gpg_encrypt rsync_ssh rm_ssh cp_ssh
    i3_save_chezmoi_ws i3_save_ws i3_restore_ws)
ZSH_REPO_FUNCS="$(printf '%s\n' "$(defined_functions "${REPO_ROOT}/dot_zshrc" \
    "${REPO_ROOT}/bin/helper/"*.zsh "${REPO_ROOT}/bin/helper/"*.bash)" \
    "${REPO_FUNCS}" "${PRIVATE_BASH[@]}" "${OLD_NAMES[@]}" | sed '/^$/d' | sort -u)"
ZSH_EXPECTED="$(sorted_words "${PUBLIC_ZSH[@]}" "${ALLOW_ZSH[@]}")"
zsh_functions_in() { printf '%s\n' "${RUN_OUT}" | sed -n "s/^fn_$1://p" | sort -u \
    | comm -12 - <(printf '%s\n' "${ZSH_REPO_FUNCS}"); }
ZSH_SCRIPT='
print -l ${(k)functions} | sed "s/^/fn_idle:/"
print -r -- "precmd1=${precmd_functions[*]}"
print -r -- "addhist1=${zshaddhistory_functions[*]}"
print -r -- "path1=${PATH}"
print -r -- "histfile=${HISTFILE}"
precmd_functions+=(e1_vendor_hook)
hh_i3_save_ws 1 >/dev/null; print "i3_one=$?"
hh_i3_save_ws 0 >/dev/null 2>&1; print "i3_bad=$?"
hh_rsync_ssh -h >/dev/null; print "rsync_help=$?"
hh_unar "${HOME}/nofile" >/dev/null; print "ex=$?"
hh_gio_mount; print "gio_mount=$?"; print -r -- "pwd=${PWD}"
cd "${HOME}"
print -l ${(k)functions} | sed "s/^/fn_after:/"
source "${HOME}/.zshrc"
print -r -- "precmd2=${precmd_functions[*]}"
print -r -- "addhist2=${zshaddhistory_functions[*]}"
print -r -- "path2=${PATH}"
print -l ${(k)functions} | sed "s/^/fn_resourced:/"
'
if command -v zsh >/dev/null 2>&1; then
    for mode in outside valid failed; do
        echo "== Zsh ${mode}: namespace, calls and re-source"
        case "${mode}" in
            outside) run_zsh "${NEW_HOME}" "${ZSH_SCRIPT}" PATH="${SEEDED_PATH}" ;;
            valid)
                printf '%s\n' "${TMUX_ID_INITIAL}" > "${NEW_HOME}/tmux_id"
                run_zsh "${NEW_HOME}" "${ZSH_SCRIPT}" PATH="${SEEDED_PATH}" \
                    TMUX=/tmp/e1-fake,1,0 TMUX_PANE="${TMUX_PANE_FIXTURE}" ;;
            failed)
                : > "${NEW_HOME}/tmux_id"
                run_zsh "${NEW_HOME}" "${ZSH_SCRIPT}" PATH="${SEEDED_PATH}" \
                    TMUX=/tmp/e1-fake,1,0 TMUX_PANE="${TMUX_PANE_FIXTURE}" ;;
        esac
        assert_eq 0 "${RUN_STATUS}" "zsh ${mode}: startup + script exits 0"
        for phase in idle after resourced; do
            assert_set_eq "${ZSH_EXPECTED}" "$(zsh_functions_in "${phase}")" \
                "zsh ${mode} ${phase}: repository functions are exactly public + zsh allowlist"
        done
        precmd1="$(out_value precmd1 "${NEW_HOME}")"
        if [[ "${mode}" == valid ]]; then
            assert_eq "_reset_ctrl_d_count vcs_info _tmux_log_last_cmd _tmux_pane_hist_sync" "${precmd1}" \
                "zsh ${mode}: precmd hooks registered once in order"
            assert_eq "_tmux_pane_hist_addhistory" "$(out_value addhist1 "${NEW_HOME}")" \
                "zsh ${mode}: zshaddhistory hook registered"
            assert_eq "<HOME>/.local/state/tmux/panes/${TMUX_ID_INITIAL}.zsh_history" \
                "$(out_value histfile "${NEW_HOME}")" "zsh ${mode}: pane HISTFILE claimed"
        else
            assert_eq "_reset_ctrl_d_count vcs_info _tmux_log_last_cmd" "${precmd1}" \
                "zsh ${mode}: no pane history hook outside a valid pane"
            assert_eq "" "$(out_value addhist1 "${NEW_HOME}")" "zsh ${mode}: no zshaddhistory hook"
        fi
        assert_eq "${precmd1} e1_vendor_hook" "$(out_value precmd2 "${NEW_HOME}")" \
            "zsh ${mode}: re-source adds no duplicate and keeps vendor hook order"
        assert_eq "$(out_value addhist1 "${NEW_HOME}")" "$(out_value addhist2 "${NEW_HOME}")" \
            "zsh ${mode}: zshaddhistory hooks unchanged by re-source"
        assert_eq "${EXPECTED_PATH}" "$(out_value path1 "${NEW_HOME}")" "zsh ${mode}: managed PATH entries added once"
        assert_eq "${EXPECTED_PATH}" "$(out_value path2 "${NEW_HOME}")" "zsh ${mode}: PATH unchanged by re-source"
        assert_eq 0 "$(out_value i3_one "${NEW_HOME}")" "zsh ${mode}: hh_i3_save_ws runs under bash"
        assert_eq 1 "$(out_value i3_bad "${NEW_HOME}")" "zsh ${mode}: hh_i3_save_ws failure status propagates"
        assert_eq 0 "$(out_value rsync_help "${NEW_HOME}")" "zsh ${mode}: hh_rsync_ssh -h"
        assert_eq 0 "$(out_value ex "${NEW_HOME}")" "zsh ${mode}: hh_unar runs"
        assert_eq "<HOME>/mnt/phone" "$(out_value pwd "${NEW_HOME}")" "zsh ${mode}: hh_gio_mount changes caller cwd"
    done
    printf '%s\n' "${TMUX_ID_INITIAL}" > "${NEW_HOME}/tmux_id"

    if (( have_baseline )); then
        run_zsh "${BASE_HOME}" 'source "${HOME}/.zshrc"; print -r -- "precmd2=${precmd_functions[*]}"'
        if [[ "$(hook_count _reset_ctrl_d_count "$(out_value precmd2 "${BASE_HOME}")")" -gt 1 ]]; then
            pass "control: same probe shows baseline .zshrc re-source duplicating precmd hooks"
        else
            fail "control: baseline precmd duplication not detected"
        fi
    fi

    echo "== Zsh macOS layout"
    run_zsh "${MAC_HOME}" 'print -l ${(k)functions} | sed "s/^/fn_idle:/"'
    assert_eq 0 "${RUN_STATUS}" "zsh macOS-layout startup exits 0"
    assert_set_eq "$(comm -23 <(printf '%s\n' "${ZSH_EXPECTED}") <(printf '%s\n' "${MAC_ONLY_LINUX_FUNCS}"))" \
        "$(zsh_functions_in idle)" "zsh macOS layout: only present modules' public helpers"
else
    gap "zsh not installed on this runner: zsh namespace, bash_exec boundary, re-source and macOS layout not verified here (owner-side native run required)"
fi

# --- Source-body equivalence against the pre-E1 baseline ---------------------
# Every function body must match the fixed baseline after applying exactly
# the approved rename map; only job_mount/job_umount may disappear.
column0_functions() {
    sed -En 's/^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\).*/\2/p' "$@" | sort -u
}
column0_count() {
    cat "${@:2}" | grep -cE "^(function[[:space:]]+)?$1[[:space:]]*\(\)"
}
function_body() {
    local name="$1"
    shift
    awk -v n="${name}" '
        !on && $0 ~ ("^(function[ \t]+)?" n "[ \t]*[(][)]") { on = 1 }
        on { print; lines++ }
        on && (/^}$/ || (lines == 1 && /}[ \t]*$/)) { exit }' "$@"
}
if (( have_baseline )); then
    echo "== Source-body equivalence vs ${BASELINE_REF} (approved renames applied)"
    RENAMED_SRC="${TMP_ROOT}/baseline-renamed"
    (cd "${BASE_SRC}" && find . -type f) | while read -r f; do
        mkdir -p "${RENAMED_SRC}/$(dirname "${f}")"
        rename_public "${BASE_SRC}/${f}" > "${RENAMED_SRC}/${f}"
    done
    # Approved calling-pane target resolution (#61): inside
    # _tmux_log_last_cmd only, the guard line and the lookup line are
    # replaced (lookup gains a non-empty check). Applied to the renamed
    # baseline; each site must match exactly once, everything else in the
    # function and file is still compared byte for byte.
    LOG_OLD_GUARD='    [[ -n "${TMUX:-}" ]] || return 0'
    LOG_OLD_LOOKUP="    id=\$(tmux display-message -p '#S:#I.#P' 2>/dev/null) || return 0"
    LOG_NEW_LOOKUP="    id=\$(tmux display-message -p -t \"\${TMUX_PANE}\" '#S:#I.#P' 2>/dev/null) || return 0
    [[ -n \"\${id}\" ]] || return 0"
    # apply_target_fix <renamed baseline file> <new guard line>
    apply_target_fix() {
        local file="$1" sites
        sites=$(OG="${LOG_OLD_GUARD}" NG="$2" OL="${LOG_OLD_LOOKUP}" NL="${LOG_NEW_LOOKUP}" awk '
            /^(function[ \t]+)?_tmux_log_last_cmd[ \t]*[(][)]/ { on = 1 }
            on && $0 == ENVIRON["OG"] { print ENVIRON["NG"]; n++; next }
            on && $0 == ENVIRON["OL"] { print ENVIRON["NL"]; n++; next }
            on && /^}$/ { on = 0 }
            { print }
            END { print n + 0 > "/dev/stderr" }' "${file}" 2>&1 >"${file}.fixed")
        mv "${file}.fixed" "${file}"
        assert_eq 2 "${sites}" "approved logger target-resolution sites applied once each: ${file#"${RENAMED_SRC}"/}"
    }
    apply_target_fix "${RENAMED_SRC}/bin/helper/tmux.bash" \
        '    [[ -n "${TMUX:-}" && "${TMUX_PANE:-}" =~ ^%[0-9]+$ ]] || return 0'
    apply_target_fix "${RENAMED_SRC}/bin/helper/tmux_last_cmd.zsh" \
        '    [[ -n "${TMUX:-}" && "${TMUX_PANE:-}" == %<-> ]] || return 0'

    unchanged=(dot_xsessionrc dot_bash_completion.d/helper.bash
        dot_bash_completion.d/transfer.bash bin/executable_firefox_rofi.bash
        bin/executable_tmux_pane_hist_release.bash bin/helper/tmux_last_cmd.zsh)
    for mod in git utils transfer tmux_commands i3 common system backup firefox; do
        unchanged+=("bin/helper/${mod}.bash")
    done
    for f in "${unchanged[@]}"; do
        if cmp -s "${RENAMED_SRC}/${f}" "${REPO_ROOT}/${f}"; then
            pass "identical after approved renames: ${f}"
        else
            fail "changed beyond approved renames: ${f}"
        fi
    done

    # side <label> <baseline files (relative)> -- <current files (relative)>
    check_bodies() {
        local label="$1" base_files=() cur_files=() name base_body
        shift
        while [[ "$1" != "--" ]]; do base_files+=("${RENAMED_SRC}/$1"); shift; done
        shift
        for f in "$@"; do cur_files+=("${REPO_ROOT}/${f}"); done
        local checked=0 bad=0
        while read -r name; do
            [[ " ${REMOVED_FUNCS[*]} " == *" ${name} "* ]] && continue
            checked=$((checked + 1))
            base_body="$(function_body "${name}" "${base_files[@]}")"
            if [[ "$(column0_count "${name}" "${cur_files[@]}")" -ne 1 ]]; then
                fail "${label}: ${name} not defined exactly once"
                bad=1
            elif [[ "${base_body}" != "$(function_body "${name}" "${cur_files[@]}")" ]]; then
                fail "${label}: ${name} body differs from baseline"
                bad=1
            fi
        done < <(column0_functions "${base_files[@]}")
        (( bad )) || pass "${label}: all ${checked} baseline function bodies byte-identical (renames applied)"
    }
    cd "${REPO_ROOT}" || exit 1
    base_bash=(dot_bashrc dot_xsessionrc dot_bash_completion.d/helper.bash
        dot_bash_completion.d/transfer.bash bin/executable_helper.bash)
    for f in "${BASE_SRC}/bin/helper/"*.bash; do base_bash+=("bin/helper/${f##*/}"); done
    cur_bash=(dot_bashrc dot_xsessionrc dot_bash_completion.d/*.bash bin/executable_helper.bash bin/helper/*.bash)
    check_bodies "bash side" "${base_bash[@]}" -- "${cur_bash[@]}"
    check_bodies "zsh side" dot_zshrc bin/helper/tmux_last_cmd.zsh bin/helper/tmux_commands.bash \
        -- dot_zshrc bin/helper/*.zsh bin/helper/tmux_commands.bash
    cd - >/dev/null || exit 1

    removed_left="$(defined_functions "${REPO_ROOT}/dot_bashrc" "${REPO_ROOT}/dot_zshrc" \
        "${REPO_ROOT}/bin/executable_helper.bash" "${REPO_ROOT}/bin/helper/"* \
        | grep -xE 'job_mount|job_umount' | tr '\n' ' ')"
    assert_eq "" "${removed_left}" "job_mount/job_umount removed everywhere"
    if [[ -n "$(function_body job_mount "${RENAMED_SRC}/bin/helper/storage.bash")" ]]; then
        pass "control: baseline still defines job_mount (removal is real)"
    else
        fail "control: baseline job_mount not found"
    fi

    base_tmux="${RENAMED_SRC}/bin/helper/tmux.bash"
    marker_line="$(grep -nF "${TMUX_PLUMBING_MARKER}" "${base_tmux}" | cut -d: -f1)"
    if [[ "$(grep -cF "${TMUX_PLUMBING_MARKER}" "${REPO_ROOT}/bin/helper/tmux_last_cmd.bash")" -eq 1 ]]; then
        pass "plumbing block present exactly once in tmux_last_cmd.bash"
    else
        fail "plumbing block missing or duplicated in tmux_last_cmd.bash"
    fi
    if [[ -n "${marker_line}" ]] && cmp -s <(head -n $((marker_line - 1)) "${base_tmux}") \
        <(head -n $((marker_line - 1)) "${REPO_ROOT}/bin/helper/tmux.bash"); then
        pass "tmux.bash session builders and header identical after approved renames"
    else
        fail "tmux.bash session builders changed"
    fi
    if ! defined_functions "${REPO_ROOT}/bin/helper/tmux.bash" | grep -q '^_tmux_'; then
        pass "tmux.bash no longer duplicates the _tmux_* callbacks"
    else
        fail "tmux.bash still defines _tmux_* callbacks"
    fi
    extract_dispatch() { sed -n '/^## Main body of script$/,$p' "$1"; }
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
