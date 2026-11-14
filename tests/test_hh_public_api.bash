#!/usr/bin/env bash
# Behaviour of the public hh_* helpers in interactive Bash and zsh.
#
# - every public helper/alias exists with the expected kind;
# - per-helper scenarios (help, success, usage errors, failure propagation,
#   quoted/spaced/empty/glob arguments, files written, argv reaching the
#   faked external commands, caller cwd/options/variables) run in a fresh
#   sandbox HOME; Bash results are checked against expected values;
# - zsh runs every scenario too and must produce the same status, stdout,
#   stderr, caller state, external calls and files as Bash;
# - shared aliases and the non-secret environment are identical in both;
# - real keys in isolated PTYs: `hh<Tab>` lists only the public helpers,
#   transfer option/host/path completion, zsh Ctrl+D.
#
# Sandbox: tests/lib/shell_fixture.bash (synthetic HOME, env -i, fakes).
# Missing zsh, python3 or bash-completion is a SKIP (a failure under CI /
# TESTS_STRICT=1).
#
# Usage: bash tests/test_hh_public_api.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"
tests_init_tmp hh-api
# shellcheck source=tests/lib/shell_fixture.bash
source "${REPO_ROOT}/tests/lib/shell_fixture.bash"
make_fakebin

PTY_DRIVER="${REPO_ROOT}/tests/pty_drive.py"
BASH_COMPLETION_ENTRY="/usr/share/bash-completion/bash_completion"
WS1_FILE="workspace_1-$(uname -n).json"

PUBLIC_FUNCS=(hh_colors hh_unar hh_tmux_restore hh_git_watch hh_git_cleanout
    hh_sshfsctl hh_gio_mount hh_gio_umount hh_upgrade_system hh_yay_no_cache
    hh_adb_pull_music hh_unzip_books hh_cut_video hh_gpg_decrypt hh_gpg_encrypt
    hh_rsync_ssh hh_rm_ssh hh_i3_save_chezmoi_ws hh_i3_save_ws hh_i3_restore_ws)
PUBLIC_ALIASES=(hh_cp_ssh)
# Non-secret environment both shells export (common.bash, rc exports,
# synthetic ~/bin/.env + job setup, dircolors, managed PATH).
ENV_KEYS=(JOB_MOUNT_DIR JOB_SETUP_FILE JOB_TEARDOWN_FILE PORT_SWAGGER_UI
    PORT_SWAGGER_EDITOR DESKTOP_BG LOCK_SCREEN_IMAGE TMUX_SESSION SINK_NAME
    EDITOR VISUAL PIPENV_VENV_IN_PROJECT JAVA_HOME VBOX_USB
    USE_GKE_GCLOUD_AUTH_PLUGIN PYTHONWARNINGS FIXTURE_JOB_SENTINEL LS_COLORS PATH)

have_zsh=0
require_cmd "zsh parity (every scenario)" zsh && have_zsh=1

# --- Scenario harness ---------------------------------------------------------
# A scenario is a snippet run in ~/work of a fresh sandbox HOME after real
# interactive startup. Optional setup_<name> <home> prepares the HOME;
# check_<name> asserts the Bash results. The caller's cwd, a shell variable,
# an exported variable and the shell options are recorded around the call.
declare -A CASE_SNIPPET=() CASE_PWD=()
CASE_NAMES=()
def_case() { CASE_NAMES+=("$1"); CASE_SNIPPET["$1"]="$2"; }

case_script() {
    local shell="$1" snippet="$2" state='"$-|$(set +o)"'
    [[ "${shell}" == zsh ]] && state='"$-|$(setopt)"'
    printf '%s\n' \
        'cd "${HOME}/work" || exit 90' \
        'cmd=CALLER_CMD' \
        'export CALLER_ENV=keep' \
        "state_before=${state}" \
        ': > "${FAKE_LOG}"' \
        '{' "${snippet}" '} > "${HOME}/case.out" 2> "${HOME}/case.err"' \
        'echo "$?" > "${HOME}/case.status"' \
        "state_after=${state}" \
        'if [ "${state_before}" = "${state_after}" ]; then opts=unchanged; else opts=changed; fi' \
        'echo "pwd=${PWD} cmd=${cmd} env=${CALLER_ENV-} options=${opts}" > "${HOME}/case.caller"' \
        'echo CASE_DONE'
}

# run_case <shell> <name>: sets CASE_HOME; returns 1 (after a FAIL) if the
# scenario did not run to completion.
run_case() {
    local shell="$1" name="$2"
    CASE_HOME="$(new_home "${shell}-${name}")" || return 1
    mkdir -p "${CASE_HOME}/work"
    if declare -F "setup_${name}" > /dev/null; then
        "setup_${name}" "${CASE_HOME}"
    fi
    "run_${shell}" "${CASE_HOME}" "$(case_script "${shell}" "${CASE_SNIPPET[${name}]}")"
    if [[ "${RUN_STDOUT}" != *CASE_DONE* || ! -f "${CASE_HOME}/case.status" ]]; then
        fail "${shell} ${name}: scenario did not complete (status ${RUN_STATUS}): $(startup_noise_filtered | head -n 3)"
        return 1
    fi
}

c_status() { cat "${CASE_HOME}/case.status"; }
c_out() { home_normalise "${CASE_HOME}" < "${CASE_HOME}/case.out"; }
c_err() { home_normalise "${CASE_HOME}" < "${CASE_HOME}/case.err"; }
c_log() { home_normalise "${CASE_HOME}" < "${CASE_HOME}/fake.log" | LC_ALL=C sort; }
c_caller() { home_normalise "${CASE_HOME}" < "${CASE_HOME}/case.caller"; }
# Files the helpers may create or remove, with checksums.
c_files() {
    (cd "${CASE_HOME}" && find work .config .local/share -type f 2> /dev/null | LC_ALL=C sort \
        | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "${f}")" "${f}"; done)
}
c_work_files() { (cd "${CASE_HOME}/work" && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort | tr '\n' '|'); }
case_signature() {
    printf 'status=%s\n--out\n%s\n--err\n%s\n--caller\n%s\n--calls\n%s\n--files\n%s\n' \
        "$(c_status)" "$(c_out)" "$(c_err)" "$(c_caller)" "$(c_log)" "$(c_files)"
}

# Assertions on the current scenario (label prefix: "bash <name>").
L() { printf 'bash %s: %s' "${CUR}" "$1"; }
expect_status() { assert_status "$1" "$(c_status)" "$(L "exit status $1")"; }
expect_out() { assert_contains "$(c_out)" "$1" "$(L "stdout has [$1]")"; }
expect_err() { assert_contains "$(c_err)" "$1" "$(L "stderr has [$1]")"; }
expect_out_empty() { assert_eq "" "$(c_out)" "$(L "stdout empty")"; }
expect_err_empty() { assert_eq "" "$(c_err)" "$(L "stderr empty")"; }
expect_call() { assert_contains "$(c_log)" "$1" "$(L "calls $1")"; }
expect_no_call() { assert_not_contains "$(c_log)" "$1" "$(L "does not call [$1]")"; }
expect_no_calls() { assert_eq "" "$(c_log)" "$(L "no external command called")"; }

# --- Scenarios: hh_rsync_ssh / hh_cp_ssh -----------------------------------------
def_case rsync_help 'hh_rsync_ssh -h'
check_rsync_help() { expect_status 0; expect_out "Usage: hh_rsync_ssh [OPTIONS]"; expect_err_empty; expect_no_calls; }
def_case rsync_no_args 'hh_rsync_ssh'
check_rsync_no_args() { expect_status 1; expect_err "Usage: hh_rsync_ssh"; expect_out_empty; expect_no_calls; }
def_case rsync_extra_arg 'hh_rsync_ssh a b c'
check_rsync_extra_arg() { expect_status 1; expect_err "Usage: hh_rsync_ssh"; expect_no_calls; }
def_case rsync_bad_option 'hh_rsync_ssh -x a b'
check_rsync_bad_option() { expect_status 1; expect_err "Error: unknown option -x"; expect_out_empty; expect_no_calls; }
def_case rsync_missing_value 'hh_rsync_ssh -p'
check_rsync_missing_value() { expect_status 1; expect_err "Error: option -p requires an argument"; expect_no_calls; }
def_case rsync_spaced 'hh_rsync_ssh -n -p 2222 "src dir/" "bob@alpha:/dst path/"'
check_rsync_spaced() {
    expect_status 0
    expect_call "rsync [-aH] [--info=progress2] [--dry-run] [-e] [ssh -c aes128-gcm@openssh.com -p 2222] [src dir/] [bob@alpha:/dst path/]"
}
def_case cp_alias 'hh_cp_ssh -z "" "beta:*.log"'
check_cp_alias() {
    expect_status 0
    expect_call "rsync [-aH] [--info=progress2] [-z] [-e] [ssh -c aes128-gcm@openssh.com -p 22] [] [beta:*.log]"
}
setup_rsync_failure() { fake_set "$1" rsync status 23; fake_set "$1" rsync stderr "rsync: connection lost"; }
def_case rsync_failure 'hh_rsync_ssh a b'
check_rsync_failure() { expect_status 23; expect_err "rsync: connection lost"; }

# --- hh_rm_ssh -------------------------------------------------------------------
def_case rm_help 'hh_rm_ssh -h'
check_rm_help() { expect_status 0; expect_out "Usage: hh_rm_ssh [OPTIONS]"; expect_no_calls; }
def_case rm_no_args 'hh_rm_ssh'
check_rm_no_args() { expect_status 1; expect_err "Usage: hh_rm_ssh"; expect_no_calls; }
def_case rm_dry_run 'hh_rm_ssh -n -p 2200 bob@alpha "/tmp/a b" "*.tmp"'
check_rm_dry_run() { expect_status 0; expect_call 'ssh [-p] [2200] [bob@alpha] [find /tmp/a\ b \*.tmp  -ls'; expect_no_call "rm -rf"; }
def_case rm_cancel 'printf "n\n" | hh_rm_ssh bob@alpha /tmp/x'
check_rm_cancel() { expect_status 0; expect_out "Cancelled."; expect_no_calls; }
def_case rm_confirm 'printf "y\n" | hh_rm_ssh bob@alpha "/tmp/x y"'
check_rm_confirm() { expect_status 0; expect_call 'ssh [-p] [22] [bob@alpha] [rm -rf -- /tmp/x\ y ]'; }
def_case rm_force 'hh_rm_ssh -f beta "/tmp/y z"'
check_rm_force() { expect_status 0; expect_call 'ssh [-p] [22] [beta] [rm -rf -- /tmp/y\ z ]'; }
setup_rm_failure() { fake_set "$1" ssh status 255; }
def_case rm_failure 'hh_rm_ssh -f beta /tmp/x'
check_rm_failure() { expect_status 255; }

# --- hh_unar ---------------------------------------------------------------------
setup_unar_zip() { touch "$1/work/x.zip"; }
def_case unar_zip 'hh_unar x.zip'
check_unar_zip() { expect_status 0; expect_call "unzip [-q] [x.zip]"; expect_err_empty; }
setup_unar_spaced() { touch "$1/work/a b.zip"; }
def_case unar_spaced 'hh_unar "a b.zip"'
check_unar_spaced() { expect_status 0; expect_call "unzip [-q] [a b.zip]"; expect_err_empty; }
setup_unar_tar_gz() { touch "$1/work/arc.tar.gz"; }
def_case unar_tar_gz 'hh_unar arc.tar.gz'
check_unar_tar_gz() { expect_status 0; expect_call "tar [xzf] [arc.tar.gz]"; }
setup_unar_7z() { touch "$1/work/my arc.7z"; }
def_case unar_7z 'hh_unar "my arc.7z"'
check_unar_7z() { expect_status 0; expect_call "7z [x] [my arc.7z]"; }
def_case unar_missing 'hh_unar missing.zip'
check_unar_missing() {
    expect_status 1
    assert_eq "hh_unar: 'missing.zip': no such file" "$(c_err)" "$(L "stderr names the missing file")"
    expect_out_empty; expect_no_calls
}
setup_unar_directory() { mkdir "$1/work/dir.zip"; }
def_case unar_directory 'hh_unar dir.zip'
check_unar_directory() { expect_status 1; expect_err "hh_unar: 'dir.zip': not a regular file"; expect_no_calls; }
setup_unar_unsupported() { touch "$1/work/notes.txt"; }
def_case unar_unsupported 'hh_unar notes.txt'
check_unar_unsupported() {
    expect_status 1
    assert_eq "hh_unar: 'notes.txt': unsupported archive type" "$(c_err)" "$(L "stderr names the unsupported file")"
    expect_out_empty; expect_no_calls
}
def_case unar_usage 'hh_unar'
check_unar_usage() { expect_status 1; expect_err "Usage: hh_unar <archive>"; expect_no_calls; }
setup_unar_failure() { touch "$1/work/x.zip"; fake_set "$1" unzip status 9; }
def_case unar_failure 'hh_unar x.zip'
check_unar_failure() { expect_status 9; }

# --- hh_unzip_books --------------------------------------------------------------
setup_books() { touch "$1/work/a.fb2.zip" "$1/work/b c.fb2.zip" "$1/work/Title.author_x.123.fb2" "$1/work/Other Book.fb2"; }
def_case books 'hh_unzip_books'
check_books() {
    expect_status 0; expect_err_empty
    expect_call "unzip [-q] [a.fb2.zip]"
    expect_call "unzip [-q] [b c.fb2.zip]"
    assert_eq "Other Book.fb2|Title.fb2|" "$(c_work_files)" "$(L "archives removed after extraction, book renamed")"
}
def_case books_none 'hh_unzip_books'
check_books_none() {
    expect_status 1
    expect_err "hh_unzip_books: no *.fb2.zip or *.fb2 files in <HOME>/work"
    expect_no_calls
}
setup_books_unzip_fails() { touch "$1/work/a.fb2.zip"; fake_set "$1" unzip status 1; }
def_case books_unzip_fails 'hh_unzip_books'
check_books_unzip_fails() {
    expect_status 1
    expect_err "hh_unzip_books: failed to extract 'a.fb2.zip' (archive kept)"
    assert_eq "a.fb2.zip|" "$(c_work_files)" "$(L "archive kept when extraction fails")"
}

# --- media, gpg, adb ---------------------------------------------------------------
def_case cut_video 'hh_cut_video "in put.mp4" 00:01 5 "out put.mp4"'
check_cut_video() {
    expect_status 0
    expect_call "ffmpeg [-ss] [00:01] [-i] [in put.mp4] [-t] [5] [-vcodec] [copy] [-acodec] [copy] [out put.mp4]"
}
setup_cut_video_failure() { fake_set "$1" ffmpeg status 1; }
def_case cut_video_failure 'hh_cut_video in.mp4 0 1 out.mp4'
check_cut_video_failure() { expect_status 1; }
def_case gpg_encrypt 'hh_gpg_encrypt rcpt < /dev/null'
check_gpg_encrypt() {
    expect_status 0
    expect_call "gpg [--local-user] [Vadim_signature] [--sign] [--encrypt] [--armor] [--recipient] [rcpt]"
}
def_case gpg_encrypt_usage 'hh_gpg_encrypt'
check_gpg_encrypt_usage() { expect_status 1; expect_err "Usage: hh_gpg_encrypt <recipient>"; expect_no_calls; }
setup_gpg_decrypt() { fake_set "$1" gpg@--decrypt stdout "plain text"; }
def_case gpg_decrypt 'hh_gpg_decrypt "in put.asc" out.txt'
check_gpg_decrypt() {
    expect_status 0
    expect_call "gpg [--decrypt] [in put.asc]"
    expect_call "gpg [--verify]"
    assert_file_contains "${CASE_HOME}/work/out.txt" "plain text" "$(L "decrypted text written to <out>")"
}
setup_gpg_decrypt_failure() { fake_set "$1" gpg@--decrypt status 2; }
def_case gpg_decrypt_failure 'hh_gpg_decrypt in.asc out.txt'
check_gpg_decrypt_failure() { expect_status 2; }
setup_gpg_verify_failure() { fake_set "$1" gpg@--verify status 1; }
def_case gpg_verify_failure 'hh_gpg_decrypt in.asc out.txt'
check_gpg_verify_failure() { expect_status 1; }
def_case gpg_decrypt_usage 'hh_gpg_decrypt in.asc'
check_gpg_decrypt_usage() { expect_status 1; expect_err "Usage: hh_gpg_decrypt <in.asc> <out>"; expect_no_calls; }
def_case adb 'hh_adb_pull_music'
check_adb() { expect_status 0; expect_call "adb [pull] [/sdcard/Vk/Vkontakte/] [/Data/vkDownloads/Music/]"; }
setup_adb_failure() { fake_set "$1" adb status 1; }
def_case adb_failure 'hh_adb_pull_music'
check_adb_failure() { expect_status 1; }

# --- package upgrades --------------------------------------------------------------
YAY_FLAGS="[--noconfirm] [--nodiffmenu] [--nocleanmenu] [--noeditmenu] [--noupgrademenu] [--cleanafter] [--removemake]"
def_case upgrade 'hh_upgrade_system'
check_upgrade() {
    expect_status 0
    expect_call "sudo [pacman] [-Syu]"
    expect_call "sudo [npm] [install] [-g] [@anthropic-ai/claude-code@latest]"
    expect_call "sudo [npm] [install] [-g] [@openai/codex@latest]"
    expect_call "yay [-Syu] ${YAY_FLAGS}"
    expect_call "sudo [paccache] [-rk1]"
}
setup_upgrade_pacman_fails() { fake_set "$1" sudo@pacman status 1; }
def_case upgrade_pacman_fails 'hh_upgrade_system'
check_upgrade_pacman_fails() { expect_status 1; expect_no_call "yay"; expect_no_call "paccache"; }
def_case yay 'hh_yay_no_cache'
check_yay() { expect_status 0; expect_call "yay ${YAY_FLAGS}"; expect_call "sudo [paccache] [-rk1]"; }
setup_yay_fails() { fake_set "$1" yay status 1; }
def_case yay_fails 'hh_yay_no_cache'
check_yay_fails() { expect_status 1; expect_no_call "paccache"; }

# --- git, tmux ---------------------------------------------------------------------
def_case git_watch 'hh_git_watch'
check_git_watch() { expect_status 0; expect_call "watch [git branch --show-current; git status --short]"; }
setup_git_cleanout() { fake_set "$1" git@branch stdout $'feature-x\nmain\n\nmaintenance-fix'; }
def_case git_cleanout "PATH=\"${FAKE_GIT_DIR}:\${PATH}\" hh_git_cleanout"
check_git_cleanout() {
    expect_status 0
    expect_call "git [gc]"
    expect_call "git [fetch] [--prune] [--all]"
    expect_call "git [pull]"
    expect_call "git [remote] [prune] [origin]"
    expect_call "git [branch] [-d] [feature-x] [maintenance-fix]"
}
setup_git_cleanout_nothing_merged() { fake_set "$1" git@branch stdout ""; }
def_case git_cleanout_nothing_merged "PATH=\"${FAKE_GIT_DIR}:\${PATH}\" hh_git_cleanout"
check_git_cleanout_nothing_merged() { expect_status 0; expect_no_call "[-d]"; }
setup_git_cleanout_fetch_fails() { fake_set "$1" git@fetch status 1; fake_set "$1" git@branch stdout "feature-x"; }
def_case git_cleanout_fetch_fails "PATH=\"${FAKE_GIT_DIR}:\${PATH}\" hh_git_cleanout"
check_git_cleanout_fetch_fails() {
    expect_status 1
    expect_call "git [pull]"
    expect_call "git [branch] [-d] [feature-x]"
}
def_case tmux_restore_nested 'TMUX=/tmp/fixture,1,0 hh_tmux_restore'
check_tmux_restore_nested() { expect_status 1; expect_err "hh_tmux_restore: already inside tmux"; expect_no_calls; }
def_case tmux_restore_attach 'hh_tmux_restore'
check_tmux_restore_attach() { expect_status 0; expect_call "tmux [attach]"; expect_no_call "systemctl"; }
setup_tmux_restore_service_fails() { fake_set "$1" tmux@list-sessions status 1; fake_set "$1" systemctl status 5; }
def_case tmux_restore_service_fails 'hh_tmux_restore'
check_tmux_restore_service_fails() {
    expect_status 5
    expect_call "systemctl [--user] [start] [tmux.service]"
    expect_no_call "tmux [attach]"
}
def_case colors 'hh_colors'
check_colors() { expect_status 0; expect_out "Color escapes are"; expect_out "BOLD"; expect_err_empty; }

# --- i3 ----------------------------------------------------------------------------
def_case i3_save_help 'hh_i3_save_ws -h'
check_i3_save_help() { expect_status 0; expect_out "Usage: hh_i3_save_ws <ws_num>"; expect_no_calls; }
def_case i3_save_one 'hh_i3_save_ws 1'
check_i3_save_one() {
    local f
    expect_status 0
    expect_call "i3-save-tree [--workspace] [1]"
    for f in ".config/i3/workspaces/${WS1_FILE}" ".local/share/chezmoi/dot_config/i3/workspaces/${WS1_FILE}"; do
        assert_file_contains "${CASE_HOME}/${f}" '"class": "^Fixture$",' "$(L "writes cleaned layout to ~/${f%/*}")"
        assert_file_not_contains "${CASE_HOME}/${f}" '//' "$(L "comment markers removed in ~/${f%/*}")"
    done
}
def_case i3_save_bad_number 'hh_i3_save_ws 0'
check_i3_save_bad_number() {
    expect_status 1
    expect_err "Error: workspace number must be 1-9, got '0'"
    expect_no_calls
}
setup_i3_save_empty() { fake_set "$1" i3-save-tree stdout ""; }
def_case i3_save_empty 'hh_i3_save_ws 1'
check_i3_save_empty() { expect_status 1; expect_err "Workspace 1: empty (no windows)"; }
def_case i3_save_all 'hh_i3_save_chezmoi_ws'
check_i3_save_all() {
    expect_status 0
    expect_out "Done. 1 workspace(s) saved"
    assert_file_contains "${CASE_HOME}/.local/share/chezmoi/dot_config/i3/workspaces/${WS1_FILE}" \
        '"class": "^Fixture$",' "$(L "saves every active workspace into the chezmoi repo")"
}
setup_i3_restore() { mkdir -p "$1/.config/i3/workspaces"; printf '{}\n' > "$1/.config/i3/workspaces/${WS1_FILE}"; }
def_case i3_restore 'hh_i3_restore_ws 1 2'
check_i3_restore() {
    expect_status 0
    expect_call "i3-msg [workspace 2; append_layout <HOME>/.config/i3/workspaces/${WS1_FILE}]"
}
def_case i3_restore_missing 'hh_i3_restore_ws 7'
check_i3_restore_missing() { expect_status 1; expect_err "workspace_7-$(uname -n).json not found"; expect_no_calls; }
setup_i3_restore_fails() { setup_i3_restore "$1"; fake_set "$1" i3-msg status 2; }
def_case i3_restore_fails 'hh_i3_restore_ws 1'
check_i3_restore_fails() { expect_status 1; expect_err "Error: i3-msg failed"; expect_out_empty; }

# --- gio ---------------------------------------------------------------------------
def_case gio_mount 'hh_gio_mount'
CASE_PWD[gio_mount]="<HOME>/mnt/phone"
check_gio_mount() { expect_status 0; expect_no_call "gio [mount] [mtp://fakephone/]"; }
setup_gio_mount_fails() { fake_set "$1" gio@info status 1; fake_set "$1" gio@mount status 2; }
def_case gio_mount_fails 'hh_gio_mount'
check_gio_mount_fails() { expect_status 2; expect_call "gio [mount] [mtp://fakephone/]"; }
setup_gio_mount_no_device() { fake_set "$1" gio@mount stdout ""; }
def_case gio_mount_no_device 'hh_gio_mount'
check_gio_mount_no_device() { expect_status 1; expect_err "hh_gio_mount: no device found"; expect_no_call "[info]"; }
setup_gio_mount_bad_path() { fake_set "$1" gio@info stdout "local path: /nonexistent/fixture mount"; }
def_case gio_mount_bad_path 'hh_gio_mount'
check_gio_mount_bad_path() {
    expect_status 1
    assert_eq "hh_gio_mount: mount point /nonexistent/fixture mount is not a directory" "$(c_err)" \
        "$(L "stderr names the unusable mount point")"
}
def_case gio_umount_inside 'cd "${HOME}/mnt/phone" && hh_gio_umount'
CASE_PWD[gio_umount_inside]="<HOME>"
check_gio_umount_inside() { expect_status 0; expect_call "gio [mount] [-u] [mtp://fakephone/]"; }
def_case gio_umount_elsewhere 'hh_gio_umount'
check_gio_umount_elsewhere() { expect_status 0; expect_call "gio [mount] [-u] [mtp://fakephone/]"; }
setup_gio_umount_not_mounted() { fake_set "$1" gio@info status 1; }
def_case gio_umount_not_mounted 'hh_gio_umount'
check_gio_umount_not_mounted() { expect_status 1; expect_err "mtp://fakephone/ is not mounted"; expect_no_call "[-u]"; }

# --- hh_sshfsctl -------------------------------------------------------------------
def_case sshfs_help 'hh_sshfsctl help'
# sshfs.bash prints its help on stderr even for `help`; either stream is fine.
check_sshfs_help() {
    expect_status 0
    assert_contains "$(c_out)$(c_err)" "Interactive SSHFS mount manager" "$(L "shows the sshfs.bash help")"
}
def_case sshfs_no_terminal 'hh_sshfsctl'
check_sshfs_no_terminal() { expect_status 1; expect_err "Usage: sshfs.bash [COMMAND]"; }
def_case sshfs_unknown 'hh_sshfsctl bogus_cmd'
check_sshfs_unknown() { expect_status 1; expect_err "Unknown command: bogus_cmd"; }
setup_sshfs_forwards() { ln -sf "${FAKEBIN}/fake-cmd" "$1/bin/sshfs.bash"; fake_set "$1" sshfs.bash status 4; }
def_case sshfs_forwards 'hh_sshfsctl mount "a b" ""'
check_sshfs_forwards() { expect_status 4; expect_call "sshfs.bash [mount] [a b] []"; }

# --- Run every scenario in Bash (checks) and zsh (parity) --------------------------
echo "== Public helper scenarios"
for CUR in "${CASE_NAMES[@]}"; do
    run_case bash "${CUR}" || continue
    "check_${CUR}"
    assert_eq "pwd=${CASE_PWD[${CUR}]:-<HOME>/work} cmd=CALLER_CMD env=keep options=unchanged" \
        "$(c_caller)" "$(L "caller cwd, variables and options")"
    bash_signature="$(case_signature)"
    if ((have_zsh)); then
        run_case zsh "${CUR}" || continue
        zsh_signature="$(case_signature)"
        if [[ "${zsh_signature}" == "${bash_signature}" ]]; then
            pass "zsh = bash: ${CUR}"
        else
            fail "zsh differs from bash: ${CUR}: $(diff <(printf '%s\n' "${bash_signature}") \
                <(printf '%s\n' "${zsh_signature}") | head -n 6 | tr '\n' ' ')"
        fi
    fi
done

# --- API surface: kinds, aliases, environment ---------------------------------------
SURFACE_BASH='
kind() { type -t "$1"; }
for a in $(compgen -a); do printf "alias:%s=%s\n" "${a}" "${BASH_ALIASES[${a}]}"; done'
SURFACE_ZSH='
kind() { local w="$(whence -w "$1")"; print -r -- "${w#*: }"; }
for a in ${(k)aliases}; do print -r -- "alias:${a}=${aliases[${a}]}"; done'
SURFACE_COMMON='
for n in '"${PUBLIC_FUNCS[*]} ${PUBLIC_ALIASES[*]}"'; do echo "kind:${n}=$(kind "${n}")"; done
for k in '"${ENV_KEYS[*]}"'; do printf "%s\n" "env:${k}=$(printenv "${k}")"; done
echo SURFACE_DONE'

# surface <shell>: sets SURFACE (sorted kind/alias/env lines, HOME normalised).
surface() {
    local shell="$1" home prelude="${SURFACE_BASH}"
    [[ "${shell}" == zsh ]] && prelude="${SURFACE_ZSH}"
    home="$(new_home "${shell}-surface")" || return 1
    "run_${shell}" "${home}" "${prelude}${SURFACE_COMMON}"
    if [[ "${RUN_STDOUT}" != *SURFACE_DONE* ]]; then
        fail "${shell} surface probe did not complete (status ${RUN_STATUS})"
        return 1
    fi
    SURFACE="$(printf '%s\n' "${RUN_STDOUT}" | grep -E '^(kind|alias|env):' \
        | sed -E 's/^(kind:[^=]*)=(shell function|function)$/\1=function/' \
        | home_normalise "${home}" | LC_ALL=C sort)"
}
# lines_of <prefix>: matching SURFACE lines.
lines_of() { printf '%s\n' "${SURFACE}" | grep "^$1" || true; }

echo "== API surface"
if surface bash; then
    bash_surface="${SURFACE}"
    expected_kinds="$( (printf 'kind:%s=function\n' "${PUBLIC_FUNCS[@]}"
        printf 'kind:%s=alias\n' "${PUBLIC_ALIASES[@]}") | LC_ALL=C sort)"
    assert_eq "${expected_kinds}" "$(lines_of kind:)" "bash: every public helper is a function, hh_cp_ssh an alias"
    assert_contains "${bash_surface}" "alias:hh_cp_ssh=hh_rsync_ssh" "bash: hh_cp_ssh expands to hh_rsync_ssh"
    assert_contains "${bash_surface}" "alias:claude_wrapper=~/ai-wrapper/bin/claude_wrapper.bash" \
        "bash: claude_wrapper alias targets the deployed wrapper"
    if ((have_zsh)) && surface zsh; then
        assert_eq "${expected_kinds}" "$(lines_of kind:)" "zsh: every public helper is a function, hh_cp_ssh an alias"
        missing=""
        while IFS= read -r line; do
            [[ -z "${line}" || "${SURFACE}" == *"${line}"* ]] || missing+="${line} "
        done <<< "$(printf '%s\n' "${bash_surface}" | grep '^alias:')"
        assert_eq "" "${missing}" "zsh = bash: every Bash alias exists in zsh with the same value"
        assert_eq "$(printf '%s\n' "${bash_surface}" | grep '^env:')" "$(lines_of env:)" \
            "zsh = bash: non-secret environment"
    fi
fi

# --- PTY: real keys ----------------------------------------------------------------
# pty_run <shell> <home> <name> <step...>: run steps against an interactive
# shell in an isolated PTY; sets PTY_LOG (transcript), PTY_ERR, PTY_STATUS.
pty_run() {
    local shell="$1" home="$2" name="$3" steps
    shift 3
    steps="${home}/${name}.steps"
    printf '%s\n' "$@" > "${steps}"
    PTY_LOG="${home}/${name}.log"
    PTY_ERR="${home}/${name}.err"
    local -a cmd=(bash --noprofile -i)
    [[ "${shell}" == zsh ]] && cmd=(zsh -i)
    sandbox_env "${home}"
    (cd "${home}" && env -i "${SANDBOX_ENV[@]}" timeout "${SHELL_TIMEOUT_SECONDS}" \
        python3 -I "${PTY_DRIVER}" "${steps}" "${PTY_LOG}" -- "${cmd[@]}") 2> "${PTY_ERR}"
    PTY_STATUS=$?
}
# Text between <<MARK a>> and <<MARK b>> in the last transcript.
pty_section() { sed -n "/<<MARK $1>>/,/<<MARK $2>>/p" "${PTY_LOG}"; }
# Each marker waits for the next prompt ("$ " bash, "% " zsh), so keys are
# typed only once the line editor is reading. pty_drive.py polls for every
# wait regex (no fixed sleeps).
READY=('wait [$%] $' 'send echo READY_$((1+1))\r' 'wait READY_2\n[\s\S]*[$%] $')
DONE=('send \x15' 'send echo DONE_$((2+2))\r' 'wait DONE_4\n[\s\S]*[$%] $')
external_hh() {
    local dir
    for dir in "${FAKEBIN}" /usr/bin /bin; do
        find "${dir}/" -maxdepth 1 -name 'hh*' \( -type f -o -type l \) -printf '%f\n' 2> /dev/null
    done
}
EXPECTED_HH="$(printf '%s\n' "${PUBLIC_FUNCS[@]}" "${PUBLIC_ALIASES[@]}" "$(external_hh)" | sed '/^$/d' | sort -u)"

# check_completion <shell>: hh<Tab> discovery and transfer completions.
check_completion() {
    local shell="$1" home listed options probe
    home="$(new_home "${shell}-completion")" || return
    touch "${home}/fixturefile.txt"
    pty_run "${shell}" "${home}" tab "${READY[@]}" 'mark tab' 'send hh' 'wait hh' \
        'tabuntil hh_yay_no_cache' "${DONE[@]}" 'mark end' 'send exit\r' 'eof'
    if [[ "${PTY_STATUS}" -ne 0 ]]; then
        fail "${shell}: hh<Tab> PTY session failed: $(cat "${PTY_ERR}")"
        return
    fi
    listed="$(pty_section tab end | grep -oE '(^|[^A-Za-z0-9_])hh[A-Za-z0-9_]*' | sed -E 's/^[^h]//' \
        | grep -vxE 'hh_?' | sort -u)"
    assert_eq "${EXPECTED_HH}" "${listed}" "${shell}: hh<Tab> lists exactly the public helpers"

    if [[ "${shell}" == bash && ! -r "${BASH_COMPLETION_ENTRY}" ]]; then
        skip "bash transfer argument completion: bash-completion not installed (${BASH_COMPLETION_ENTRY})"
        return
    fi
    pty_run "${shell}" "${home}" opts "${READY[@]}" \
        'mark rsync' 'send hh_rsync_ssh -' 'wait ssh -' 'tabuntil -z' "${DONE[@]}" \
        'mark rm' 'send hh_rm_ssh -' 'wait ssh -' 'tabuntil -f' "${DONE[@]}" \
        'mark cipher' 'send hh_rsync_ssh -c aes' 'wait c aes' 'tabuntil aes128-gcm@openssh\.com' "${DONE[@]}" \
        'mark end' 'send exit\r' 'eof'
    if [[ "${PTY_STATUS}" -ne 0 ]]; then
        fail "${shell}: option completion PTY session failed: $(cat "${PTY_ERR}")"
        return
    fi
    options="$(pty_section rsync rm | grep -oE '(^|[[:space:]])-[a-z]\b' | tr -d ' \t' | sort -u | tr '\n' ' ')"
    assert_eq "-c -h -n -p -z " "${options}" "${shell}: hh_rsync_ssh -<Tab> offers its options"
    options="$(pty_section rm cipher | grep -oE '(^|[[:space:]])-[a-z]\b' | tr -d ' \t' | sort -u | tr '\n' ' ')"
    assert_eq "-f -h -n -p " "${options}" "${shell}: hh_rm_ssh -<Tab> offers its options"
    assert_contains "$(pty_section cipher end)" "aes128-gcm@openssh.com" "${shell}: hh_rsync_ssh -c <Tab> offers ciphers"
    for probe in 'hh_rsync_ssh be|hh_rsync_ssh +beta' 'hh_cp_ssh be|hh_cp_ssh +beta' \
        'hh_rm_ssh be|hh_rm_ssh +beta' 'hh_rsync_ssh fixturef|hh_rsync_ssh +fixturefile\.txt'; do
        # One Tab completes the unique word; Ctrl+L then redraws prompt and
        # line buffer, so the match reads the buffer itself.
        pty_run "${shell}" "${home}" word "${READY[@]}" "send ${probe%%|*}" "wait ${probe%%|*}" 'tab' \
            'send \x0c' "wait ${probe#*|}" "${DONE[@]}" 'send exit\r' 'eof'
        if [[ "${PTY_STATUS}" -eq 0 ]]; then
            pass "${shell}: '${probe%%|*}<Tab>' completes (${probe#*|})"
        else
            fail "${shell}: '${probe%%|*}<Tab>' did not complete: $(cat "${PTY_ERR}")"
        fi
    done
}

# Empty-line ^D warns once; a ^D on a non-empty line resets the count (the
# next empty ^D warns again instead of exiting); two empty ^D exit.
check_zsh_ctrl_d() {
    local home
    home="$(new_home zsh-ctrl-d)" || return
    pty_run zsh "${home}" ctrl-d "${READY[@]}" \
        'send \x04' 'wait Press Ctrl\+D again' \
        'send echo x\x04' 'send \x15' 'send \x04' 'wait Press Ctrl\+D again' \
        'send echo ALIVE_$((1+1))\r' 'wait ALIVE_2\n[\s\S]*[$%] $' \
        'send \x04' 'send \x04' 'eof'
    if [[ "${PTY_STATUS}" -eq 0 ]] && grep -q '<<EXIT 0>>' "${PTY_LOG}"; then
        pass "zsh: Ctrl+D warns on empty line, resets on non-empty line, exits on second press"
    else
        fail "zsh: Ctrl+D behaviour: $(cat "${PTY_ERR}") $(tail -n 3 "${PTY_LOG}" | tr '\n' ' ')"
    fi
    pty_run zsh "${home}" ctrl-d-edit "${READY[@]}" 'send echo AB\x04' 'send \r' 'wait (^|\n)AB' \
        "${DONE[@]}" 'send exit\r' 'eof'
    if [[ "${PTY_STATUS}" -eq 0 ]]; then
        pass "zsh: Ctrl+D on a non-empty line keeps editing (line still runs)"
    else
        fail "zsh: Ctrl+D on non-empty line: $(cat "${PTY_ERR}")"
    fi
}

echo "== PTY: completion and keys"
if require_cmd "PTY key tests" python3; then
    check_completion bash
    if ((have_zsh)); then
        check_completion zsh
        check_zsh_ctrl_d
    else
        skip "zsh PTY completion and Ctrl+D: zsh not installed"
    fi
fi

tests_finish
