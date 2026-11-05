#!/usr/bin/env bash
# Regression test for issue #60: the public hh_* helper API, its aliases and
# non-secret environment behave the same in interactive Bash and zsh.
#
# - every public helper/alias exists; old names and job_mount/job_umount are
#   gone as helper definitions/aliases (unrelated executables may exist);
# - help/success/failure paths, quoted/spaced/empty/glob arguments, alias
#   expansion inside bodies, caller cwd/options/environment: the same script
#   runs in both shells and must produce identical outputs, statuses and
#   external argv sequences (Bash is also checked against expected values);
# - aliases and environment match between shells and the pre-E1 baseline
#   (plus the approved hh_cp_ssh rename and claude_wrapper alias);
# - real keys in isolated PTYs: `hh<Tab>` lists only the public helpers,
#   transfer option/host/path completion, zsh Ctrl+D on empty/non-empty lines;
# - no live caller still uses an old name.
#
# Runs in the tests/lib/shell_fixture.bash sandbox (synthetic HOME, env -i,
# logging fakes). Missing zsh, python3, system bash-completion or the
# baseline commit is reported as GAP, never as a pass.
#
# Usage: bash tests/test_hh_public_api.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE_REF="${E1_BASELINE_REF:-0d46a7f7df3be7c8a79d8cad5e30c9176b28d7d7}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/e2-api.XXXXXX")"
PTY_DRIVER="${REPO_ROOT}/tests/pty_drive.py"
BASH_COMPLETION_ENTRY="/usr/share/bash-completion/bash_completion"

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

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        pass "${label}"
    else
        fail "${label}: [${needle}] not found"
    fi
}

PUBLIC_FUNCS=(hh_colors hh_ex hh_tmux_restore hh_git_watch hh_git_cleanout
    hh_sshfsctl hh_gio_mount hh_gio_umount hh_upgrade_system hh_yay_no_cache
    hh_adb_pull_music hh_unzip_books hh_cut_video hh_gpg_decrypt hh_gpg_encrypt
    hh_rsync_ssh hh_rm_ssh hh_i3_save_chezmoi_ws hh_i3_save_ws hh_i3_restore_ws)
PUBLIC_ALIASES=(hh_cp_ssh)
OLD_NAMES=(colors ex tmux_restore git_watch git_cleanout sshfsctl gio_mount
    gio_umount job_mount job_umount upgrade_system yay_no_cache adb_pull_music
    unzip_books cut_video gpg_decrypt gpg_encrypt rsync_ssh rm_ssh cp_ssh
    i3_save_chezmoi_ws i3_save_ws i3_restore_ws)
# Intended non-secret environment (common.bash, .bashrc exports, synthetic
# ~/bin/.env + job setup, dircolors, managed PATH).
ENV_KEYS=(JOB_MOUNT_DIR JOB_SETUP_FILE JOB_TEARDOWN_FILE PORT_SWAGGER_UI
    PORT_SWAGGER_EDITOR DESKTOP_BG LOCK_SCREEN_IMAGE TMUX_SESSION SINK_NAME
    EDITOR VISUAL PIPENV_VENV_IN_PROJECT JAVA_HOME VBOX_USB
    USE_GKE_GCLOUD_AUTH_PLUGIN PYTHONWARNINGS E1_JOB_SENTINEL LS_COLORS PATH)
# Repository-managed aliases: the shared file plus the transfer alias.
mapfile -t MANAGED_ALIASES < <(sed -En 's/^alias ([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' \
    "${REPO_ROOT}/bin/helper/aliases.shrc")
MANAGED_ALIASES+=("${PUBLIC_ALIASES[@]}")
# Literal alias value (tilde is expanded by the shell at use, not here).
TILDE='~'
CLAUDE_WRAPPER_ALIAS="${TILDE}/ai-wrapper/bin/claude_wrapper.bash"

# Shell-specific probes with one output format: kind (function/alias/file/
# builtin/keyword or empty), alias value, alias names.
BASH_PRELUDE='
kind() { type -t "$1"; }
aval() { printf "%s" "${BASH_ALIASES[$1]}"; }
anames() { compgen -a; }
'
ZSH_PRELUDE='
kind() {
    local w="$(whence -w "$1")"
    w="${w#*: }"
    case "${w}" in none) w="" ;; command) w=file ;; reserved) w=keyword ;; esac
    print -r -- "${w}"
}
aval() { print -rn -- "${aliases[$1]}"; }
anames() { print -l ${(k)aliases}; }
'

# Shell-neutral API script (bash/zsh common subset). Runs in ~/work; each
# helper's stdout/stderr goes to an o_* file compared across shells.
API_SCRIPT='
cd "${HOME}/work" || exit 9
for n in '"${PUBLIC_FUNCS[*]} ${PUBLIC_ALIASES[*]}"'; do echo "kind_${n}=$(kind "${n}")"; done
for n in '"${OLD_NAMES[*]}"'; do echo "old_${n}=$(kind "${n}")"; done
for k in '"${ENV_KEYS[*]}"'; do printf "%s\n" "env_${k}=$(printenv "${k}")"; done
for a in $(anames); do printf "%s\n" "alias_${a}=$(aval "${a}")"; done
export E1_ENV_SENTINEL=keep
cmd=E1_CALLER_CMD
opts_before="$-"
: > "${E1_ARGV_LOG}"
hh_rsync_ssh -h > o_rsync_help 2>&1; echo "rsync_help=$?"
hh_rsync_ssh > o_rsync_noargs 2>&1; echo "rsync_noargs=$?"
hh_rsync_ssh -x a b > o_rsync_badopt 2>&1; echo "rsync_badopt=$?"
hh_rsync_ssh -p > o_rsync_noval 2>&1; echo "rsync_noval=$?"
hh_rsync_ssh -n -p 2222 "src dir/" "bob@alpha:/dst path/" > o_rsync_spaced 2>&1; echo "rsync_spaced=$?"
hh_cp_ssh -z "" "beta:*.log" > o_cp_alias 2>&1; echo "cp_alias=$?"
E1_FAIL_TRANSFER=1 hh_rsync_ssh a b > o_rsync_fail 2>&1; echo "rsync_fail=$?"
hh_rm_ssh -h > o_rm_help 2>&1; echo "rm_help=$?"
hh_rm_ssh > o_rm_noargs 2>&1; echo "rm_noargs=$?"
hh_rm_ssh -n -p 2200 bob@alpha "/tmp/a b" "*.tmp" > o_rm_dry 2>&1; echo "rm_dry=$?"
printf "n\n" | hh_rm_ssh bob@alpha /tmp/x > o_rm_cancel 2>&1; echo "rm_cancel=$?"
hh_rm_ssh -f beta "/tmp/y z" > o_rm_force 2>&1; echo "rm_force=$?"
hh_ex x.zip > o_ex_zip 2>&1; echo "ex_zip=$?"
hh_ex "a b.zip" > o_ex_spaced 2>/dev/null; echo "ex_spaced=$?"
hh_ex arc.tar.gz > o_ex_tgz 2>&1; echo "ex_tgz=$?"
hh_ex missing.zip > o_ex_missing 2>&1; echo "ex_missing=$?"
hh_ex notes.txt > o_ex_unknown 2>&1; echo "ex_unknown=$?"
hh_colors > o_colors 2>&1; echo "colors=$?"
(cd empty && hh_unzip_books > ../o_books_empty 2>&1; echo "books_empty=$?")
(cd books && hh_unzip_books > ../o_books 2>&1; echo "books=$?")
echo "books_after=$(cd books && ls | tr "\n" " ")"
hh_cut_video "in put.mp4" 00:01 5 "out put.mp4" > o_cut 2>&1; echo "cut=$?"
hh_gpg_encrypt ignored rcpt > o_gpg_enc 2>&1; echo "gpg_enc=$?"
hh_gpg_decrypt ignored in.asc out.txt > o_gpg_dec 2>&1; echo "gpg_dec=$?"
hh_adb_pull_music > o_adb 2>&1; echo "adb=$?"
hh_upgrade_system > o_upgrade 2>&1; echo "upgrade=$?"
hh_yay_no_cache > o_yay 2>&1; echo "yay=$?"
hh_git_watch > o_git_watch 2>&1; echo "git_watch=$?"
PATH="${HOME}/gitfake:${PATH}" hh_git_cleanout > o_cleanout 2>&1; echo "cleanout=$?"
TMUX=/tmp/e2-nested hh_tmux_restore > o_tmux_nested 2>&1; echo "tmux_nested=$?"
hh_tmux_restore > o_tmux_restore 2>&1; echo "tmux_restore=$?"
hh_i3_save_ws -h > o_i3_help 2>&1; echo "i3_help=$?"
hh_i3_save_ws 1 > o_i3_one 2>&1; echo "i3_one=$?"
hh_i3_save_ws 0 > o_i3_bad 2>&1; echo "i3_bad=$?"
hh_i3_restore_ws 7 > o_i3_restore_missing 2>&1; echo "i3_restore_missing=$?"
hh_i3_restore_ws 1 2 > o_i3_restore 2>&1; echo "i3_restore=$?"
hh_i3_save_chezmoi_ws > o_i3_all 2>&1; echo "i3_all=$?"
echo "cmd=${cmd}"
echo "env=${E1_ENV_SENTINEL}"
echo "pwd_after_calls=${PWD}"
if [ "$-" = "${opts_before}" ]; then echo "opts_same=yes"; else echo "opts_same=no"; fi
hh_gio_mount > o_gio_mount 2>&1; echo "gio_mount=$?"
echo "pwd_mounted=${PWD}"
hh_gio_umount > o_gio_umount 2>&1; echo "gio_umount=$?"
cd "${HOME}/work" || exit 9
cp "${E1_ARGV_LOG}" argv_api.log
hh_sshfsctl -r u@h start /r "/l p" > o_sshfs_start 2>&1; echo "sshfs_start=$?"
hh_sshfsctl bogus /r /l > o_sshfs_bad 2>&1 || echo "sshfs_bad=$?"
echo "opts_sshfs=$-"
echo "pipefail=$(set -o | grep -c "pipefail.*on")"
echo "api_done=yes"
'

# prepare_work <home>: per-run working directory fixtures.
prepare_work() {
    local home="$1"
    rm -rf "${home}/work" "${home}/gitfake"
    mkdir -p "${home}/work/empty" "${home}/work/books" "${home}/gitfake"
    touch "${home}/work/x.zip" "${home}/work/a b.zip" "${home}/work/arc.tar.gz" \
        "${home}/work/notes.txt" "${home}/work/books/a.fb2.zip" \
        "${home}/work/books/Title.author_x.123.fb2"
    ln -s "${FAKEBIN}/e1-fake" "${home}/gitfake/git"
    mkdir -p "${home}/.config/i3/workspaces"
    printf '{}\n' > "${home}/.config/i3/workspaces/workspace_1-$(uname -n).json"
}

# collect <home> <dest>: o_* outputs and argv logs, sandbox HOME normalised.
collect() {
    local home="$1" dest="$2" f
    mkdir -p "${dest}"
    for f in "${home}/work/"o_* "${home}/work/argv_api.log" "${home}/argv.log"; do
        [[ -e "${f}" ]] || continue
        sed "s|${home}|<HOME>|g" "${f}" > "${dest}/${f##*/}"
    done
    printf '%s\n' "${RUN_OUT}" | sed "s|${home}|<HOME>|g" > "${dest}/out"
}

# The exercised helpers' pipelines whose two stages are both logging fakes,
# as "<first stage argv line><Tab><second stage argv line>": hh_gpg_decrypt
# (gpg --decrypt | tee | gpg --verify) and hh_i3_save_chezmoi_ws
# (i3-msg -t get_workspaces | jq). Both stages start together, so which one
# logs first is scheduling, not behaviour.
PIPELINE_STAGES=$'gpg [--decrypt] [in.asc]\tgpg [--verify]
i3-msg [-t] [get_workspaces]\tjq [[.[].num] | sort | unique[]]'

# pipeline_order <file>: the file with each adjacent pair of a known
# pipeline's stages in stage order. Only exact adjacent stage pairs move;
# every other line keeps its position and every line is kept.
pipeline_order() {
    F_STAGES="${PIPELINE_STAGES}" awk '
        BEGIN {
            n = split(ENVIRON["F_STAGES"], pairs, "\n")
            for (i = 1; i <= n; i++) {
                split(pairs[i], stage, "\t")
                first_of[stage[2]] = stage[1]
            }
        }
        held != "" && $0 == first_of[held] { print; print held; held = ""; next }
        held != "" { print held; held = "" }
        $0 in first_of { held = $0; next }
        { print }
        END { if (held != "") print held }' "$1"
}

# Controls for pipeline_order: a swapped stage pair is normalised; a swap of
# unrelated lines, a lost or duplicated stage, or a stage pair split by
# another call still differs.
order_case() {
    local label="$1" expect="$2" a="$3" b="$4" actual
    if cmp -s <(pipeline_order <(printf '%s\n' "${a}")) <(pipeline_order <(printf '%s\n' "${b}")); then
        actual=same
    else
        actual=differs
    fi
    assert_eq "${expect}" "${actual}" "pipeline_order control: ${label}"
}
STAGE_I3="i3-msg [-t] [get_workspaces]"
STAGE_JQ="jq [[.[].num] | sort | unique[]]"
order_case "i3-msg|jq stages swapped" same \
    $'a\n'"${STAGE_I3}"$'\n'"${STAGE_JQ}"$'\nb' $'a\n'"${STAGE_JQ}"$'\n'"${STAGE_I3}"$'\nb'
order_case "gpg stages swapped" same \
    $'gpg [--decrypt] [in.asc]\ngpg [--verify]' $'gpg [--verify]\ngpg [--decrypt] [in.asc]'
order_case "unrelated calls swapped" differs $'a\n'"${STAGE_I3}"$'\nb' $'b\n'"${STAGE_I3}"$'\na'
order_case "stage lost" differs "${STAGE_I3}"$'\n'"${STAGE_JQ}" "${STAGE_I3}"
order_case "stage duplicated" differs "${STAGE_I3}"$'\n'"${STAGE_JQ}" \
    "${STAGE_JQ}"$'\n'"${STAGE_I3}"$'\n'"${STAGE_JQ}"
order_case "stage pair split by another call" differs \
    "${STAGE_I3}"$'\n'"${STAGE_JQ}"$'\nb' "${STAGE_JQ}"$'\nb\n'"${STAGE_I3}"

# kv <dir> <key>: value of key=value in a collected run.
kv() { sed -n "s|^$2=||p" "$1/out" | head -n 1; }

make_fakebin
NEW_HOME="${TMP_ROOT}/new"
deploy_tree "${REPO_ROOT}" "${NEW_HOME}"
BASH_RES="${TMP_ROOT}/res-bash"
ZSH_RES="${TMP_ROOT}/res-zsh"

# --- Bash: expected values ------------------------------------------------------
echo "== Bash public API"
prepare_work "${NEW_HOME}"
run_bash "${NEW_HOME}" "${BASH_PRELUDE}${API_SCRIPT}"
collect "${NEW_HOME}" "${BASH_RES}"
assert_eq yes "$(kv "${BASH_RES}" api_done)" "bash API script ran to completion ($(run_summary "${NEW_HOME}"))"
for n in "${PUBLIC_FUNCS[@]}"; do
    [[ "$(kv "${BASH_RES}" "kind_${n}")" == function ]] || fail "bash: ${n} is not a function"
done
pass "bash: kinds of all ${#PUBLIC_FUNCS[@]} public helpers checked"
assert_eq alias "$(kv "${BASH_RES}" kind_hh_cp_ssh)" "bash: hh_cp_ssh is an alias"
assert_eq hh_rsync_ssh "$(kv "${BASH_RES}" alias_hh_cp_ssh)" "bash: hh_cp_ssh expands to hh_rsync_ssh"
old_bad=""
for n in "${OLD_NAMES[@]}"; do
    case "$(kv "${BASH_RES}" "old_${n}")" in function|alias) old_bad+="${n} " ;; esac
done
assert_eq "" "${old_bad}" "bash: no old public name or job_* is a function/alias"

declare -A BASH_EXPECT=(
    [rsync_help]=0 [rsync_noargs]=1 [rsync_badopt]=1 [rsync_noval]=1
    [rsync_spaced]=0 [cp_alias]=0 [rsync_fail]=23 [rm_help]=0 [rm_noargs]=1
    [rm_dry]=0 [rm_cancel]=0 [rm_force]=0 [ex_zip]=0 [ex_spaced]=0 [ex_tgz]=0
    [ex_missing]=0 [ex_unknown]=0 [colors]=0 [books_empty]=0 [books]=0
    [cut]=0 [gpg_enc]=0 [gpg_dec]=0 [adb]=0 [upgrade]=0 [yay]=0 [git_watch]=0
    [cleanout]=0 [tmux_nested]=1 [tmux_restore]=0 [i3_help]=0 [i3_one]=0
    [i3_bad]=1 [i3_restore_missing]=1 [i3_restore]=0 [i3_all]=0 [gio_mount]=0
    [gio_umount]=0 [sshfs_start]=0 [sshfs_bad]=1 [pipefail]=1
    [cmd]=E1_CALLER_CMD [env]=keep [opts_same]=yes
    [pwd_after_calls]="<HOME>/work" [pwd_mounted]="<HOME>/mnt/phone"
    [books_after]="Title.fb2 ")
for key in "${!BASH_EXPECT[@]}"; do
    assert_eq "${BASH_EXPECT[${key}]}" "$(kv "${BASH_RES}" "${key}")" "bash: ${key}"
done
opts="$(kv "${BASH_RES}" opts_sshfs)"
[[ "${opts}" == *e* && "${opts}" == *u* ]] && pass "bash: hh_sshfsctl sets errexit/nounset in caller" \
    || fail "bash: hh_sshfsctl caller options: ${opts}"
argv_api="$(cat "${BASH_RES}/argv_api.log")"
# The pipeline stage table must name lines the helpers really log, or
# pipeline_order would silently stop normalising them.
while IFS=$'\t' read -r stage_first stage_second; do
    for stage in "${stage_first}" "${stage_second}"; do
        assert_eq 1 "$(grep -cxF -- "${stage}" "${BASH_RES}/argv_api.log")" \
            "bash: pipeline stage logged exactly once: ${stage}"
    done
done <<< "${PIPELINE_STAGES}"
assert_contains "${argv_api}" "rsync [-aH] [--info=progress2] [--dry-run] [-e] [ssh -c aes128-gcm@openssh.com -p 2222] [src dir/] [bob@alpha:/dst path/]" \
    "bash: hh_rsync_ssh keeps spaced argument boundaries"
assert_contains "${argv_api}" "rsync [-aH] [--info=progress2] [-z] [-e] [ssh -c aes128-gcm@openssh.com -p 22] [] [beta:*.log]" \
    "bash: hh_cp_ssh alias passes empty and glob arguments literally"
assert_contains "${argv_api}" 'ssh [-p] [2200] [bob@alpha] [find /tmp/a\ b \*.tmp  -ls' \
    "bash: hh_rm_ssh dry run shell-quotes remote paths (printf %q)"
assert_contains "${argv_api}" 'ssh [-p] [22] [beta] [rm -rf -- /tmp/y\ z ]' "bash: hh_rm_ssh -f deletes in one ssh call"
assert_contains "${argv_api}" "unzip [-q] [x.zip]" "bash: hh_ex expands the shared unzip alias"
assert_contains "${argv_api}" "tar [xzf] [arc.tar.gz]" "bash: hh_ex extracts tar.gz"
assert_contains "${argv_api}" "unzip [-q] [a.fb2.zip]" "bash: hh_unzip_books expands the shared unzip alias"
assert_contains "${argv_api}" "unzip [-q] [*.fb2.zip]" "bash: hh_unzip_books keeps Bash literal-glob semantics"
assert_contains "${argv_api}" "ffmpeg [-ss] [00:01] [-i] [in put.mp4] [-t] [5] [-vcodec] [copy] [-acodec] [copy] [out put.mp4]" \
    "bash: hh_cut_video argument boundaries"
assert_contains "${argv_api}" "gpg [--local-user] [Vadim_signature] [--sign] [--encrypt] [--armor] [--recipient] [rcpt]" \
    "bash: hh_gpg_encrypt"
assert_contains "${argv_api}" "gpg [--decrypt] [in.asc]" "bash: hh_gpg_decrypt"
assert_contains "${argv_api}" "adb [pull] [/sdcard/Vk/Vkontakte/] [/Data/vkDownloads/Music/]" "bash: hh_adb_pull_music"
assert_contains "${argv_api}" "sudo [pacman] [-Syu]" "bash: hh_upgrade_system"
assert_contains "${argv_api}" "watch [git branch --show-current; git status --short]" "bash: hh_git_watch"
assert_contains "${argv_api}" "git [fetch] [--prune] [--all]" "bash: hh_git_cleanout"
assert_contains "${argv_api}" "tmux [attach]" "bash: hh_tmux_restore attaches"
assert_contains "${argv_api}" "i3-msg [workspace 2; append_layout <HOME>/.config/i3/workspaces/workspace_1-$(uname -n).json]" \
    "bash: hh_i3_restore_ws"
assert_contains "$(cat "${BASH_RES}/argv.log")" "systemctl [--user] [start] [sshfs@u@h:/r:/l p]" \
    "bash: hh_sshfsctl keeps spaced local path"
assert_contains "$(cat "${BASH_RES}/o_rsync_help")" "Usage: hh_rsync_ssh [OPTIONS]" "bash: help text uses the hh_ name"
assert_contains "$(cat "${BASH_RES}/o_rsync_badopt")" "Error: unknown option -x" "bash: hh_rsync_ssh bad option on stderr"
assert_contains "$(cat "${BASH_RES}/o_rsync_fail")" "rsync: e1 failure" "bash: transfer failure stderr propagates"
assert_contains "$(cat "${BASH_RES}/o_rm_cancel")" "Cancelled." "bash: hh_rm_ssh confirmation reads caller stdin"
assert_contains "$(cat "${BASH_RES}/o_ex_spaced")" "'a b.zip' is not a valid file" "bash: hh_ex unquoted-\$1 semantics preserved"
assert_contains "$(cat "${BASH_RES}/o_ex_missing")" "'missing.zip' is not a valid file" "bash: hh_ex missing file"
assert_contains "$(cat "${BASH_RES}/o_ex_unknown")" "'notes.txt' cannot be extracted via ex()" "bash: hh_ex unknown type"
assert_contains "$(cat "${BASH_RES}/o_colors")" "Color escapes are" "bash: hh_colors prints the table"
assert_contains "$(cat "${BASH_RES}/o_tmux_nested")" "hh_tmux_restore: already inside tmux" "bash: hh_tmux_restore nested guard"
assert_contains "$(cat "${BASH_RES}/o_i3_bad")" "workspace number must be 1-9" "bash: hh_i3_save_ws failure stderr"

# --- Aliases and environment: Bash vs pre-E1 baseline -------------------------
# Extract "alias_*"/"env_*" lines from a collected run.
alias_lines() { grep '^alias_' "$1/out" | sort; }
managed_alias_lines() {
    local a
    for a in "${MANAGED_ALIASES[@]}"; do grep "^alias_${a}=" "$1/out"; done | sort
}
env_lines() { grep '^env_' "$1/out" | sort; }

BASE_SRC="${TMP_ROOT}/baseline-src"
if git -C "${REPO_ROOT}" cat-file -e "${BASELINE_REF}^{commit}" 2>/dev/null; then
    echo "== Bash aliases/environment vs pre-E1 baseline"
    mkdir -p "${BASE_SRC}"
    git -C "${REPO_ROOT}" archive "${BASELINE_REF}" dot_bashrc dot_zshrc dot_xsessionrc \
        dot_bash_completion.d bin | tar -x -C "${BASE_SRC}"
    BASE_HOME="${TMP_ROOT}/baseline"
    deploy_tree "${BASE_SRC}" "${BASE_HOME}"
    prepare_work "${BASE_HOME}"
    run_bash "${BASE_HOME}" "${BASH_PRELUDE}"'
for k in '"${ENV_KEYS[*]}"'; do printf "%s\n" "env_${k}=$(printenv "${k}")"; done
for a in $(anames); do printf "%s\n" "alias_${a}=$(aval "${a}")"; done'
    collect "${BASE_HOME}" "${TMP_ROOT}/res-base"
    expected_aliases="$( (alias_lines "${TMP_ROOT}/res-base" | sed 's/^alias_cp_ssh=rsync_ssh$/alias_hh_cp_ssh=hh_rsync_ssh/'
        echo "alias_claude_wrapper=${CLAUDE_WRAPPER_ALIAS}") | sort)"
    assert_eq "${expected_aliases}" "$(alias_lines "${BASH_RES}")" \
        "bash aliases = baseline + hh_cp_ssh rename + claude_wrapper"
    assert_eq "$(env_lines "${TMP_ROOT}/res-base")" "$(env_lines "${BASH_RES}")" \
        "bash intended environment identical to baseline"
else
    gap "baseline ${BASELINE_REF} unavailable: bash alias/env baseline comparison not verified"
fi
assert_eq "${CLAUDE_WRAPPER_ALIAS}" "$(kv "${BASH_RES}" alias_claude_wrapper)" \
    "claude_wrapper alias targets the deployed wrapper name"
assert_eq "<HOME>/bin:<HOME>/ai-wrapper/bin:${FAKEBIN}:/usr/bin:/bin" "$(kv "${BASH_RES}" env_PATH)" "bash PATH"
assert_eq loaded "$(kv "${BASH_RES}" env_E1_JOB_SENTINEL)" "bash sources synthetic JOB_SETUP_FILE"

# --- zsh: same script, same results --------------------------------------------
echo "== zsh public API parity"
if command -v zsh >/dev/null 2>&1; then
    prepare_work "${NEW_HOME}"
    run_zsh "${NEW_HOME}" "${ZSH_PRELUDE}${API_SCRIPT}"
    collect "${NEW_HOME}" "${ZSH_RES}"
    assert_eq yes "$(kv "${ZSH_RES}" api_done)" "zsh API script ran to completion ($(run_summary "${NEW_HOME}"))"
    for f in "${BASH_RES}/"o_* "${BASH_RES}/argv_api.log"; do
        if cmp -s <(pipeline_order "${f}") <(pipeline_order "${ZSH_RES}/${f##*/}"); then
            pass "zsh = bash: ${f##*/}"
        else
            fail "zsh differs from bash: ${f##*/}: $(diff "${f}" "${ZSH_RES}/${f##*/}" | head -n 4 | tr '\n' ' ')"
        fi
    done
    assert_eq "$(grep 'systemctl' "${BASH_RES}/argv.log")" "$(grep 'systemctl' "${ZSH_RES}/argv.log")" \
        "zsh = bash: hh_sshfsctl systemctl argv"
    for key in "${!BASH_EXPECT[@]}" opts_sshfs; do
        val="$(kv "${ZSH_RES}" "${key}")"
        if [[ "${key}" == opts_sshfs ]]; then
            [[ "${val}" == *e* && "${val}" == *u* ]] && pass "zsh: hh_sshfsctl sets errexit/nounset in caller" \
                || fail "zsh: hh_sshfsctl caller options: ${val}"
        else
            assert_eq "$(kv "${BASH_RES}" "${key}")" "${val}" "zsh = bash: ${key}"
        fi
    done
    assert_eq "$(grep -E '^(kind|old)_' "${BASH_RES}/out" | sed -E 's/=(file|builtin|keyword)$/=external/' | sort)" \
        "$(grep -E '^(kind|old)_' "${ZSH_RES}/out" | sed -E 's/=(file|builtin|keyword)$/=external/' | sort)" \
        "zsh = bash: public helper/alias kinds and old-name absence"
    assert_eq "$(managed_alias_lines "${BASH_RES}")" "$(managed_alias_lines "${ZSH_RES}")" \
        "zsh = bash: every repository-managed alias value"
    assert_eq "$(env_lines "${BASH_RES}")" "$(env_lines "${ZSH_RES}")" "zsh = bash: intended environment"
else
    gap "zsh not installed on this runner: zsh API/alias/env parity not verified here (owner-side native run required)"
fi

# --- Live callers --------------------------------------------------------------
echo "== Live callers use only hh_ names"
live_old="$(cd "${REPO_ROOT}" && git grep -nwE \
    'tmux_restore|git_watch|git_cleanout|sshfsctl|gio_mount|gio_umount|job_mount|job_umount|upgrade_system|yay_no_cache|adb_pull_music|unzip_books|cut_video|gpg_decrypt|gpg_encrypt|rsync_ssh|rm_ssh|cp_ssh|i3_save_chezmoi_ws|i3_save_ws|i3_restore_ws' \
    -- bin dot_bashrc dot_zshrc dot_bash_completion.d dot_config ':!bin/helper/README.md' | tr '\n' ' ')"
assert_eq "" "${live_old}" "no live script/config/completion/tmux caller uses an old name"
send_keys="$(grep -c 'send-keys .*"hh_git_watch" C-m' "${REPO_ROOT}/bin/helper/tmux.bash")"
assert_eq 3 "${send_keys}" "tmux session builders send hh_git_watch"
if grep -qE '^(colors|ex) ?\(\)' "${REPO_ROOT}/dot_bashrc" "${REPO_ROOT}/bin/helper/"*; then
    fail "old colors/ex definitions remain"
else
    pass "old colors/ex definitions removed"
fi
if grep -qE '^#alias ' "${REPO_ROOT}/dot_bashrc"; then
    fail "commented-out alias definitions remain in dot_bashrc"
else
    pass "commented-out alias definitions removed"
fi
if grep -qF 'executable_claude_wrapper' "${REPO_ROOT}/dot_zshrc" "${REPO_ROOT}/bin/helper/aliases.shrc"; then
    fail "claude_wrapper alias still targets the chezmoi source name"
else
    pass "claude_wrapper alias no longer targets the chezmoi source name"
fi

# --- PTY: real keys --------------------------------------------------------------
# pty_run <shell> <name> <step...>: run steps against an interactive shell
# in an isolated PTY; sets PTY_LOG (transcript) and PTY_STATUS.
pty_run() {
    local shell="$1" name="$2" steps="${TMP_ROOT}/${2}.steps"
    shift 2
    printf '%s\n' "$@" > "${steps}"
    PTY_LOG="${TMP_ROOT}/${name}.log"
    sandbox_env "${NEW_HOME}"
    local cmd=(bash --noprofile -i)
    [[ "${shell}" == zsh ]] && cmd=(zsh -i)
    (cd "${NEW_HOME}" && env -i "${SANDBOX_ENV[@]}" ZDOTDIR="${NEW_HOME}" \
        timeout "${SHELL_TIMEOUT_SECONDS}" python3 -I "${PTY_DRIVER}" "${steps}" "${PTY_LOG}" -- "${cmd[@]}") \
        2>"${TMP_ROOT}/${name}.err"
    PTY_STATUS=$?
}
# Text between <<MARK a>> and <<MARK b>> in the last transcript.
pty_section() { sed -n "/<<MARK $1>>/,/<<MARK $2>>/p" "${PTY_LOG}"; }
# Each marker also waits for the next prompt ("$ " bash, "% " zsh), so keys
# are typed only once the line editor is reading.
READY=('wait [$%] $' 'send echo READY_$((1+1))\r' 'wait READY_2\n[\s\S]*[$%] $')
DONE=('send \x15' 'send echo DONE_$((2+2))\r' 'wait DONE_4\n[\s\S]*[$%] $')
external_hh() {
    local dir
    for dir in "${FAKEBIN}" /usr/bin /bin; do
        find "${dir}/" -maxdepth 1 -name 'hh*' \( -type f -o -type l \) -printf '%f\n' 2>/dev/null
    done
}
EXPECTED_HH="$(printf '%s\n' "${PUBLIC_FUNCS[@]}" "${PUBLIC_ALIASES[@]}" "$(external_hh)" | sed '/^$/d' | sort -u)"

# check_completion <shell>: hh<Tab> discovery and transfer completions.
check_completion() {
    local shell="$1" listed
    touch "${NEW_HOME}/e1file.txt"
    pty_run "${shell}" "${shell}-tab" "${READY[@]}" 'mark tab' 'send hh' 'wait hh' 'tabuntil hh_yay_no_cache' "${DONE[@]}" 'mark end' 'send exit\r' 'eof'
    if [[ "${PTY_STATUS}" -ne 0 ]]; then
        fail "${shell}: hh<Tab> PTY session failed: $(cat "${TMP_ROOT}/${shell}-tab.err")"
        return
    fi
    listed="$(pty_section tab end | grep -oE '(^|[^A-Za-z0-9_])hh[A-Za-z0-9_]*' | sed -E 's/^[^h]//' \
        | grep -vxE 'hh_?' | sort -u)"
    assert_eq "${EXPECTED_HH}" "${listed}" "${shell}: hh<Tab> lists exactly the public helpers"

    if [[ "${shell}" == bash && ! -r "${BASH_COMPLETION_ENTRY}" ]]; then
        gap "bash-completion not installed (${BASH_COMPLETION_ENTRY}): bash transfer argument completion not verified here"
        return
    fi
    local options
    pty_run "${shell}" "${shell}-opts" "${READY[@]}" \
        'mark rsync' 'send hh_rsync_ssh -' 'wait ssh -' 'tabuntil -z' "${DONE[@]}" \
        'mark rm' 'send hh_rm_ssh -' 'wait ssh -' 'tabuntil -f' "${DONE[@]}" \
        'mark cipher' 'send hh_rsync_ssh -c aes' 'wait c aes' 'tabuntil aes128-gcm@openssh\.com' "${DONE[@]}" 'mark end' 'send exit\r' 'eof'
    if [[ "${PTY_STATUS}" -ne 0 ]]; then
        fail "${shell}: option completion PTY session failed: $(cat "${TMP_ROOT}/${shell}-opts.err")"
        return
    fi
    options="$(pty_section rsync rm | grep -oE '(^|[[:space:]])-[a-z]\b' | tr -d ' \t' | sort -u | tr '\n' ' ')"
    assert_eq "-c -h -n -p -z " "${options}" "${shell}: hh_rsync_ssh -<Tab> offers its options"
    options="$(pty_section rm cipher | grep -oE '(^|[[:space:]])-[a-z]\b' | tr -d ' \t' | sort -u | tr '\n' ' ')"
    assert_eq "-f -h -n -p " "${options}" "${shell}: hh_rm_ssh -<Tab> offers its options"
    assert_contains "$(pty_section cipher end)" "aes128-gcm@openssh.com" "${shell}: hh_rsync_ssh -c <Tab> offers ciphers"
    for probe in 'hh_rsync_ssh be|hh_rsync_ssh +beta' 'hh_cp_ssh be|hh_cp_ssh +beta' \
        'hh_rm_ssh be|hh_rm_ssh +beta' 'hh_rsync_ssh e1f|hh_rsync_ssh +e1file\.txt'; do
        # One Tab completes the unique word; Ctrl+L then redraws prompt and
        # line buffer, so the match reads the buffer itself. A Tab response
        # carries only the inserted suffix and redraws the line only when it
        # lists candidates (no redraw when nothing is left to complete).
        pty_run "${shell}" "${shell}-word" "${READY[@]}" "send ${probe%%|*}" "wait ${probe%%|*}" 'tab' \
            'send \x0c' "wait ${probe#*|}" "${DONE[@]}" 'send exit\r' 'eof'
        if [[ "${PTY_STATUS}" -eq 0 ]]; then
            pass "${shell}: '${probe%%|*}<Tab>' completes (${probe#*|})"
        else
            fail "${shell}: '${probe%%|*}<Tab>' did not complete: $(cat "${TMP_ROOT}/${shell}-word.err")"
        fi
    done
}

echo "== PTY: completion"
if command -v python3 >/dev/null 2>&1; then
    check_completion bash
    if command -v zsh >/dev/null 2>&1; then
        check_completion zsh
        echo "== PTY: zsh Ctrl+D"
        # Empty-line ^D warns once; a ^D on a non-empty line resets the count
        # (so the next empty ^D warns again instead of exiting); two empty
        # ^D in a row exit the shell.
        pty_run zsh zsh-ctrl-d "${READY[@]}" \
            'send \x04' 'wait Press Ctrl\+D again' \
            'send echo x\x04' 'send \x15' 'send \x04' 'wait Press Ctrl\+D again' \
            'send echo ALIVE_$((1+1))\r' 'wait ALIVE_2\n[\s\S]*[$%] $' \
            'send \x04' 'send \x04' 'eof'
        if [[ "${PTY_STATUS}" -eq 0 ]] && grep -q '<<EXIT 0>>' "${PTY_LOG}"; then
            pass "zsh: Ctrl+D warns on empty line, resets on non-empty line, exits on second press"
        else
            fail "zsh: Ctrl+D behaviour: $(cat "${TMP_ROOT}/zsh-ctrl-d.err") $(tail -n 3 "${PTY_LOG}" | tr '\n' ' ')"
        fi
        pty_run zsh zsh-ctrl-d-edit "${READY[@]}" 'send echo AB\x04' 'send \r' 'wait (^|\n)AB' "${DONE[@]}" 'send exit\r' 'eof'
        if [[ "${PTY_STATUS}" -eq 0 ]]; then
            pass "zsh: Ctrl+D on a non-empty line keeps editing (line still runs)"
        else
            fail "zsh: Ctrl+D on non-empty line: $(cat "${TMP_ROOT}/zsh-ctrl-d-edit.err")"
        fi
    else
        gap "zsh not installed on this runner: zsh hh<Tab>, transfer completion and Ctrl+D PTY checks not verified here"
    fi
else
    gap "python3 not available: PTY key tests not run"
fi

echo
echo "${failures} failure(s), ${gaps} verification gap(s)"
(( failures == 0 ))
