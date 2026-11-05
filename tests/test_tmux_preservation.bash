#!/usr/bin/env bash
# Regression test for issue #61: tmux session preservation (tmux-resurrect /
# tmux-continuum snapshots, last-command prefill, per-pane history) and the
# boot script that the systemd unit / LaunchAgent run.
#
# Layers, each labelled in its PASS/GAP lines:
# - prefill: bin/tmux_prefill_last_cmd.bash against a logging fake tmux
#   (argv and the bytes tmux would deliver), then those exact bytes typed
#   into a real interactive Bash (and zsh when installed) through a PTY with
#   a side-effect sentinel. The pre-fix script is replayed from git
#   (F_PRE_FIX_REF) to reproduce the old failures;
# - post-restore hook: the configured hook value run through the same
#   `eval "$hook $args"` contract tmux-resurrect's restore.sh uses
#   (emulation, not a plugin run);
# - boot script: both server branches and both restore outcomes with a fake
#   tmux routed through an exported shell function (the script resets PATH,
#   so a PATH wrapper alone would not contain it). The fake applies the
#   kill-session command-alias read from the real tmux.conf.tmpl;
# - per-pane history recorder file modes and release ownership rules;
# - static contracts: systemd unit, enable script, LaunchAgent, clipboard
#   commands rendered for Linux and (simulated) darwin;
# - socket guard: the guard used by the native layer, checked against a
#   fake real tmux (option ordering/clusters, -S/-L/$TMUX precedence, the
#   boot script's PATH reset routed through the exported function);
# - native: real tmux + real tpm/tmux-resurrect/tmux-continuum on a private
#   socket under a fresh TMUX_TMPDIR with synthetic HOME/XDG:
#   save -> stop the verified test-owned server -> boot -> restore. Needs
#   `tmux` on PATH and F_TMUX_PLUGIN_ROOT=<dir with the three clean git
#   checkouts; tpm at the pin in run_once_install-tpm-plugins.bash>. The
#   checkouts are copied into the test tree (full SHAs recorded, sources
#   fingerprinted before and after); the host's runtime plugin dirs are
#   refused as input; nothing is downloaded. Every tmux call goes through
#   the guard, which refuses any socket outside the test root; the owner's
#   default socket is never listed, probed, attached, killed or restarted.
#   A server is stopped only after it reports the test socket and a tmux
#   PID, on the normal path and in the exit trap.
#
# Not covered here (always reported as GAP): systemd user-manager lifecycle
# (cgroup ownership, active/dead semantics, linger, logout) — see
# docs/systemd-services.md for the owner-side verification method.
#
# Input-mode assumption for the PTY checks: default Readline/ZLE emacs
# keymaps in a UTF-8 locale. Safety under arbitrary user-rebound printable
# keys is not claimed.
#
# Usage: bash tests/test_tmux_preservation.bash
#        F_TMUX_PLUGIN_ROOT=/path/to/plugins bash tests/test_tmux_preservation.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRE_FIX_REF="${F_PRE_FIX_REF:-6aacb61ffafc0983ef71e08e706509b999dfac78}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/f-tmux.XXXXXX")"
# Symlink-free, as tmux reports socket paths (it resolves TMUX_TMPDIR).
TMP_ROOT="$(cd "${TMP_ROOT}" && pwd -P)"
PTY_DRIVER="${REPO_ROOT}/tests/pty_drive.py"
PREFILL_PATH="bin/executable_tmux_prefill_last_cmd.bash"
BOOT_PATH="bin/executable_tmux_boot.bash"
RELEASE_PATH="bin/executable_tmux_pane_hist_release.bash"
RECORDER_PATH="bin/helper/tmux_last_cmd.bash"
CONF_PATH="dot_config/tmux/tmux.conf.tmpl"
SERVICE_PATH="dot_config/systemd/user/tmux.service"
ENABLE_PATH="run_onchange_enable-tmux-service.bash.tmpl"
PLIST_PATH="Library/LaunchAgents/local.tmux.plist.tmpl"
PLUGINS=(tpm tmux-resurrect tmux-continuum)
GUARD_DENY_STATUS=97
# tmux global options that take a value (getopt "2c:CDdf:lL:NqS:T:uUvV").
TMUX_VALUE_FLAGS="cfLST"
TPM_PIN=$(sed -n 's/^TPM_TAG_SHA="\([0-9a-f]\{40\}\)"$/\1/p' "${REPO_ROOT}/run_once_install-tpm-plugins.bash")
NATIVE_TIMEOUT_TENTHS=150
PANE="f_sess:0.0"
NATIVE_SOCKET=""
NATIVE_GUARD=""
NATIVE_ENV=()
PLUGIN_SOURCES=()

failures=0
gaps=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }
gap() { printf 'GAP: %s\n' "$1"; gaps=$((gaps + 1)); }
info() { printf 'INFO: %s\n' "$1"; }

# Exit trap, also reached from every early return and on INT/TERM/HUP:
# stop the private test server only after it proves its identity
# (stop_native_server); if that fails, keep the tree for inspection.
cleanup() {
    local status=$? stop_status=0
    if [[ -S "${NATIVE_SOCKET}" ]]; then
        stop_native_server
        stop_status=$?
    fi
    if ((stop_status == 1)); then
        printf 'FAIL: cleanup: test tmux server on %s not verified/stopped; %s kept\n' \
            "${NATIVE_SOCKET}" "${TMP_ROOT}"
        exit 1
    fi
    rm -rf "${TMP_ROOT}"
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        pass "${label}"
    else
        fail "${label}: expected [${expected}] got [${actual}]"
    fi
}

assert_file_absent() {
    local path="$1" label="$2"
    if [[ -e "${path}" ]]; then
        fail "${label}: ${path##*/} exists"
    else
        pass "${label}"
    fi
}

assert_mode() {
    local expected="$1" path="$2" label="$3"
    assert_eq "${expected}" "$(stat -c '%a' "${path}" 2>/dev/null)" "${label}"
}

# pre_fix_file <repo path> <dest>: the file as it was before the #61 fixes.
pre_fix_file() {
    git -C "${REPO_ROOT}" show "${PRE_FIX_REF}:$1" > "$2" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Fake tmux: logs argv, serves list-panes/list-sessions from state files and
# records what send-keys would type into each pane. Without -l, a whole
# argument that is a tmux key name becomes that key (tmux key lookup).
# ---------------------------------------------------------------------------
FAKEBIN="${TMP_ROOT}/fakebin"
mkdir -p "${FAKEBIN}"
cat > "${FAKEBIN}/tmux" <<'FAKE'
#!/bin/bash
state="${F_STATE:?F_STATE must be set}"
{ printf '%q ' "$@"; printf '\n'; } >> "${state}/argv.log"
cmd="${1:-}"
shift || true

# command-alias entries come from the real tmux.conf when the case supplies
# it; tmux appends the caller's arguments to the expansion.
if [[ -r "${state}/tmux.conf" ]]; then
    expansion=$(sed -n "s/^set -s command-alias\[[0-9]*\] \"${cmd}=\(.*\)\"$/\1/p" \
        "${state}/tmux.conf" | head -n 1)
    if [[ -n "${expansion}" ]]; then
        if [[ "${expansion}" == confirm-before* && $# -gt 0 ]]; then
            echo "command confirm-before: too many arguments" >&2
        else
            echo "no current client" >&2
        fi
        exit 1
    fi
fi

target=""
literal=0
case "${cmd}" in
    list-panes)
        if [[ "${*: -1}" == *pane_id* ]]; then
            cat "${state}/live_panes" 2>/dev/null
        else
            cat "${state}/panes" 2>/dev/null
        fi
        ;;
    send-keys)
        while (($#)); do
            case "$1" in
                -l) literal=1; shift ;;
                -t) target="$2"; shift 2 ;;
                --) shift; break ;;
                *) break ;;
            esac
        done
        if grep -qxF -- "${target}" "${state}/closed_panes" 2>/dev/null; then
            echo "can't find pane: ${target}" >&2
            exit 1
        fi
        for arg in "$@"; do
            if ((literal)); then
                printf '%s' "${arg}"
                continue
            fi
            case "${arg}" in
                Enter|C-m) printf '\r' ;;
                C-j) printf '\n' ;;
                C-o) printf '\017' ;;
                BSpace) printf '\177' ;;
                Tab) printf '\t' ;;
                Escape) printf '\033' ;;
                *) printf '%s' "${arg}" ;;
            esac
        done >> "${state}/delivered.${target}"
        ;;
    list-sessions|has-session)
        [[ -s "${state}/sessions" ]] || { echo "no server running" >&2; exit 1; }
        [[ "${cmd}" == list-sessions ]] && cat "${state}/sessions"
        ;;
    new-session)
        while (($#)); do
            [[ "$1" == -s ]] && { echo "$2" >> "${state}/sessions"; shift; }
            shift
        done
        ;;
    kill-ses)
        [[ "${1:-}" == -t ]] || exit 1
        grep -qxF -- "$2" "${state}/sessions" || { echo "can't find session: $2" >&2; exit 1; }
        grep -vxF -- "$2" "${state}/sessions" > "${state}/sessions.new"
        mv "${state}/sessions.new" "${state}/sessions"
        ;;
    run-shell)
        /bin/sh -c "$*"
        ;;
    display-message)
        while (($#)); do
            case "$1" in
                -p) shift ;;
                -t) target="$2"; shift 2 ;;
                *) break ;;
            esac
        done
        # No -t: the client's active pane, not necessarily the caller's.
        # With a pane map, -t resolves like tmux: pane IDs, and session
        # names to that session's active pane; anything else fails.
        if [[ -z "${target}" ]]; then
            printf '%s\n' "${F_ACTIVE_POSITION:-${F_PANE_POSITION:-}}"
        elif [[ -r "${state}/pane_map" ]]; then
            position=$(awk -v t="${target}" '$1 == t { print $2 }' "${state}/pane_map")
            [[ -n "${position}" ]] || { echo "can't find pane: ${target}" >&2; exit 1; }
            printf '%s\n' "${position}"
        else
            printf '%s\n' "${F_PANE_POSITION:-}"
        fi
        ;;
esac
exit 0
FAKE
chmod +x "${FAKEBIN}/tmux"

# new_case: fresh synthetic HOME + fake state; sets CASE/CASE_HOME/CASE_STATE.
new_case() {
    CASE="$(mktemp -d "${TMP_ROOT}/case.XXXXXX")"
    CASE_HOME="${CASE}/home"
    CASE_STATE="${CASE}/state"
    mkdir -p "${CASE_HOME}/bin" "${CASE_HOME}/.local/state/tmux/panes" "${CASE_STATE}"
    printf '%s\t0\t0\tbash\n' "${PANE%%:*}" > "${CASE_STATE}/panes"
}

case_env() {
    CASE_ENV=(HOME="${CASE_HOME}" XDG_STATE_HOME="${CASE_HOME}/.local/state"
        PATH="${FAKEBIN}:/usr/bin:/bin" LANG=C.UTF-8 F_STATE="${CASE_STATE}")
}

# run_prefill <script>: sets RUN_STATUS; stderr in ${CASE}/stderr.
run_prefill() {
    case_env
    env -i "${CASE_ENV[@]}" bash "$1" > /dev/null 2> "${CASE}/stderr"
    RUN_STATUS=$?
}

# write_last <text with printf %b escapes>: the recorder file for ${PANE}.
write_last() {
    printf '%b' "$1" > "${CASE_HOME}/.local/state/tmux/panes/${PANE}.last"
}

delivered_file() { printf '%s/delivered.%s' "${CASE_STATE}" "${PANE}"; }

# ---------------------------------------------------------------------------
# PTY side-effect check: type <pretype> then the delivered bytes into a real
# interactive shell, clear the line with Ctrl+U (in-order, unlike a signal),
# optionally press Enter, and report whether the sentinel was written.
# Sets PTY_EXECUTED (yes/no) and PTY_TRANSCRIPT. Returns 1 on driver error.
# ---------------------------------------------------------------------------
escape_bytes() {
    od -An -v -tx1 "$1" | tr -s ' \n' ' ' | sed 's/ \([0-9a-f][0-9a-f]\)/\\x\1/g; s/ //g'
}

pty_side_effect() {
    local shell="$1" payload_file="$2" pretype="$3" press_enter="$4" sentinel="$5"
    local steps="${CASE}/steps.${shell}" prompt
    PTY_TRANSCRIPT="${CASE}/transcript.${shell}"
    case "${shell}" in
        bash) prompt='\$ $' ;;
        zsh) prompt='% $' ;;
    esac
    {
        printf 'wait %s\n' "${prompt}"
        [[ -n "${pretype}" ]] && printf 'send %s\n' "${pretype}"
        [[ -s "${payload_file}" ]] && printf 'send %s\n' "$(escape_bytes "${payload_file}")"
        if [[ "${press_enter}" == 1 ]]; then
            printf 'send \\r\n'
            printf 'wait %s\n' "${prompt}"
        fi
        printf 'send \\x15echo MARK'"''"'ER_DONE\\r\n'
        printf 'wait MARKER_DONE\n'
    } > "${steps}"
    local cmd=(bash --noprofile --norc -i)
    [[ "${shell}" == zsh ]] && cmd=(zsh -f -i)
    env -i HOME="${CASE_HOME}" TERM=xterm PATH=/usr/bin:/bin LANG=C.UTF-8 \
        HISTFILE=/dev/null timeout 60 python3 "${PTY_DRIVER}" "${steps}" \
        "${PTY_TRANSCRIPT}" -- "${cmd[@]}" 2> "${CASE}/pty.err" || return 1
    if [[ -e "${sentinel}" ]]; then PTY_EXECUTED=yes; else PTY_EXECUTED=no; fi
}

PTY_SHELLS=()
if command -v python3 >/dev/null 2>&1; then
    PTY_SHELLS+=(bash)
    if command -v zsh >/dev/null 2>&1; then
        PTY_SHELLS+=(zsh)
    else
        gap "zsh not installed: ZLE side-effect checks not run (Bash only)"
    fi
else
    gap "python3 not installed: real-shell PTY side-effect checks not run"
fi

PRE_FIX_PREFILL="${TMP_ROOT}/prefill.pre_fix.bash"
if ! pre_fix_file "${PREFILL_PATH}" "${PRE_FIX_PREFILL}"; then
    gap "pre-fix ref ${PRE_FIX_REF} unavailable: old prefill failures not replayed"
    PRE_FIX_PREFILL=""
fi

# side_effect_case <label> <script> <payload printf format> <pretype> <expect yes|no>
# Payload commands write ${CASE}/sentinel; {S} in the format is that path.
side_effect_case() {
    local label="$1" script="$2" format="$3" pretype="$4" expect="$5" shell
    for shell in "${PTY_SHELLS[@]}"; do
        new_case
        local sentinel="${CASE}/sentinel"
        write_last "${format//\{S\}/${sentinel}}"
        run_prefill "${script}"
        if ! pty_side_effect "${shell}" "$(delivered_file)" "${pretype//\{S\}/${sentinel}}" 0 "${sentinel}"; then
            fail "${label} [${shell}]: PTY driver error: $(head -n 1 "${CASE}/pty.err")"
            continue
        fi
        assert_eq "${expect}" "${PTY_EXECUTED}" "${label} [${shell}]: executed=${expect}"
    done
}

PREFILL="${REPO_ROOT}/${PREFILL_PATH}"
EXEC_CMD='printf EXECUTED > {S}'

echo "== prefill: real-shell side effects (pre-fix replay vs current) =="
if ((${#PTY_SHELLS[@]})); then
    if [[ -n "${PRE_FIX_PREFILL}" ]]; then
        side_effect_case "pre-fix reproduces: embedded LF without final newline runs" \
            "${PRE_FIX_PREFILL}" "${EXEC_CMD}\\necho second" "" yes
        side_effect_case "pre-fix reproduces: trailing Ctrl+O runs the line" \
            "${PRE_FIX_PREFILL}" "${EXEC_CMD}\\017\\n" "" yes
        side_effect_case "pre-fix reproduces: text 'Enter' is sent as the Enter key" \
            "${PRE_FIX_PREFILL}" 'Enter\n' "${EXEC_CMD}" yes
    fi
    side_effect_case "embedded LF without final newline is rejected" \
        "${PREFILL}" "${EXEC_CMD}\\necho second" "" no
    side_effect_case "embedded LF with final newline is rejected" \
        "${PREFILL}" "${EXEC_CMD}\\necho second\\n" "" no
    side_effect_case "trailing Ctrl+O is rejected" "${PREFILL}" "${EXEC_CMD}\\017\\n" "" no
    side_effect_case "embedded CR is rejected" "${PREFILL}" "${EXEC_CMD}\\r\\n" "" no
    side_effect_case "embedded Ctrl+J/Ctrl+M bytes after text are rejected" \
        "${PREFILL}" "${EXEC_CMD}\\012\\015" "" no
    side_effect_case "text 'Enter' is typed literally" "${PREFILL}" 'Enter\n' "${EXEC_CMD}" no
    side_effect_case "text 'C-m' is typed literally" "${PREFILL}" 'C-m\n' "${EXEC_CMD}" no

    # Positive control: the accepted command is typed, visible, not run until
    # the test presses Enter.
    for shell in "${PTY_SHELLS[@]}"; do
        new_case
        sentinel="${CASE}/sentinel"
        write_last "${EXEC_CMD//\{S\}/${sentinel}}\\n"
        run_prefill "${PREFILL}"
        if pty_side_effect "${shell}" "$(delivered_file)" "" 0 "${sentinel}"; then
            assert_eq no "${PTY_EXECUTED}" "positive control [${shell}]: accepted command not run before Enter"
            if grep -qF "printf EXECUTED > ${sentinel}" "${PTY_TRANSCRIPT}"; then
                pass "positive control [${shell}]: accepted command visible in the line buffer"
            else
                fail "positive control [${shell}]: command not visible in transcript"
            fi
        else
            fail "positive control [${shell}]: PTY driver error: $(head -n 1 "${CASE}/pty.err")"
        fi
        rm -f "${sentinel}"
        if pty_side_effect "${shell}" "$(delivered_file)" "" 1 "${sentinel}"; then
            assert_eq yes "${PTY_EXECUTED}" "positive control [${shell}]: command runs after explicit Enter"
        else
            fail "positive control [${shell}]: PTY driver error: $(head -n 1 "${CASE}/pty.err")"
        fi
    done
fi

echo "== prefill: send-keys argv and delivered bytes (fake tmux) =="
# Accepted text, shell punctuation, quoted paths and Unicode go out as one
# literal argument, without the recorder's trailing line separator.
ACCEPTED_TEXT=$(cat <<'TEXT'
printf "%s\n" "a b" | grep -E 'x|y' > "/tmp/dir with space/ö" && echo $HOME; ls ~ # ✓
TEXT
)
new_case
printf '%s\n' "${ACCEPTED_TEXT}" > "${CASE_HOME}/.local/state/tmux/panes/${PANE}.last"
run_prefill "${PREFILL}"
assert_eq 0 "${RUN_STATUS}" "accepted text: exit 0"
assert_eq "send-keys -l -t ${PANE} -- $(printf '%q' "${ACCEPTED_TEXT}") " \
    "$(grep '^send-keys' "${CASE_STATE}/argv.log")" "accepted text: one literal send-keys -l argument"
assert_eq "${ACCEPTED_TEXT}" "$(cat "$(delivered_file)")" "accepted text: delivered bytes match exactly"

# rejected_case <label> <printf format>: nothing is sent, exit 0.
rejected_case() {
    new_case
    write_last "$2"
    run_prefill "${PREFILL}"
    if [[ "${RUN_STATUS}" == 0 && ! -e "$(delivered_file)" ]] \
        && ! grep -q '^send-keys' "${CASE_STATE}/argv.log"; then
        pass "rejected: $1"
    else
        fail "rejected: $1: status=${RUN_STATUS} argv=$(grep '^send-keys' "${CASE_STATE}/argv.log")"
    fi
}

rejected_case "empty file" ''
rejected_case "separator only" '\n'
rejected_case "spaces only" '   \n'
rejected_case "tabs only" '\t\t\n'
rejected_case "mixed whitespace" ' \t \n'
rejected_case "terminated multi-line" 'echo a\necho b\n'
rejected_case "unterminated multi-line" 'echo a\necho b'
rejected_case "NUL byte (would be silently dropped into a different command)" 'echo a\000; rm x\n'
rejected_case "ESC sequence" 'echo a\033[A\n'
rejected_case "DEL" 'echo ab\177\n'
for byte in $(seq 1 31); do
    [[ "${byte}" == 10 ]] && continue
    rejected_case "C0 control 0x$(printf '%02x' "${byte}")" "echo a\\$(printf '%03o' "${byte}")b\\n"
done

# Named key strings go through -l: the bytes are the text, not a key.
for key in Enter C-m BSpace; do
    new_case
    write_last "${key}\\n"
    run_prefill "${PREFILL}"
    assert_eq "${key}" "$(cat "$(delivered_file)" 2>/dev/null)" "key name '${key}' delivered as literal text"
done
if [[ -n "${PRE_FIX_PREFILL}" ]]; then
    new_case
    write_last 'BSpace\n'
    run_prefill "${PRE_FIX_PREFILL}"
    assert_eq "7f" "$(od -An -tx1 "$(delivered_file)" | tr -d ' \n')" \
        "pre-fix reproduces: 'BSpace' sent as the Backspace key"
fi

new_case
printf 'f_sess\t0\t0\tvim\nf_sess\t0\t1\tsleep\n' > "${CASE_STATE}/panes"
printf 'echo a\n' > "${CASE_HOME}/.local/state/tmux/panes/f_sess:0.0.last"
printf 'echo b\n' > "${CASE_HOME}/.local/state/tmux/panes/f_sess:0.1.last"
run_prefill "${PREFILL}"
assert_eq "0:0" "${RUN_STATUS}:$(grep -c "^send-keys" "${CASE_STATE}/argv.log")" \
    "non-shell panes (vim, sleep) receive nothing"

# Closed-pane race: a failing send-keys does not stop later panes.
new_case
printf 'f_sess\t0\t0\tbash\nf_sess\t0\t1\tzsh\nf_sess\t1\t0\tbash\n' > "${CASE_STATE}/panes"
printf 'echo gone\n' > "${CASE_HOME}/.local/state/tmux/panes/f_sess:0.0.last"
printf 'echo zsh_pane\n' > "${CASE_HOME}/.local/state/tmux/panes/f_sess:0.1.last"
printf 'f_sess:0.0\n' > "${CASE_STATE}/closed_panes"
run_prefill "${PREFILL}"
assert_eq 0 "${RUN_STATUS}" "closed pane: exit 0"
assert_eq "echo zsh_pane" "$(cat "${CASE_STATE}/delivered.f_sess:0.1" 2>/dev/null)" \
    "closed pane: later pane still prefilled"
assert_file_absent "${CASE_STATE}/delivered.f_sess:1.0" "pane without a .last file is skipped"

new_case
rm -rf "${CASE_HOME}/.local/state/tmux/panes"
run_prefill "${PREFILL}"
assert_eq "0:0" "${RUN_STATUS}:$(wc -l 2>/dev/null < "${CASE_STATE}/argv.log" || echo 0)" \
    "missing state dir: exit 0 without calling tmux"

echo "== post-restore hook (resurrect execute_hook contract, emulated) =="
HOOK_RE="s/^set -g @resurrect-hook-post-restore-all '\\(.*\\)'\$/\\1/p"
# run_hook <conf file>: eval "$hook $args" with no args, as restore.sh does.
run_hook() {
    local hook
    hook=$(sed -n "${HOOK_RE}" "$1")
    new_case
    cp "${PREFILL}" "${CASE_HOME}/bin/tmux_prefill_last_cmd.bash"
    chmod +x "${CASE_HOME}/bin/tmux_prefill_last_cmd.bash"
    write_last 'echo hooked\n'
    case_env
    # \${1} is expanded by the inner bash, like restore.sh.
    env -i "${CASE_ENV[@]}" bash -c "eval \"\${1} \"" _ "${hook}" > /dev/null 2> "${CASE}/stderr"
    RUN_STATUS=$?
}
run_hook "${REPO_ROOT}/${CONF_PATH}"
assert_eq "0:echo hooked" "${RUN_STATUS}:$(cat "$(delivered_file)" 2>/dev/null)" \
    "configured hook runs the prefill script"
PRE_FIX_CONF="${TMP_ROOT}/tmux.conf.pre_fix"
if pre_fix_file "${CONF_PATH}" "${PRE_FIX_CONF}"; then
    run_hook "${PRE_FIX_CONF}"
    if [[ "${RUN_STATUS}" == 127 ]] && grep -q 'run-shell: command not found' "${CASE}/stderr"; then
        pass "pre-fix reproduces: hook fails with run-shell: command not found"
    else
        fail "pre-fix hook replay: status=${RUN_STATUS} $(head -n 1 "${CASE}/stderr")"
    fi
    assert_eq "$(grep 'command-alias\[100\] "kill-session=' "${PRE_FIX_CONF}")" \
        "$(grep 'command-alias\[100\] "kill-session=' "${REPO_ROOT}/${CONF_PATH}")" \
        "interactive kill-session confirmation alias unchanged"
fi

echo "== boot script branches (fake tmux via exported function) =="
# run_boot <script> [restore fixture body]: the real script with PATH reset
# inside it; tmux resolves to the exported function, which calls the fake.
run_boot() {
    local script="$1" restore_body="${2:-}"
    cp "${REPO_ROOT}/${CONF_PATH}" "${CASE_STATE}/tmux.conf"
    if [[ -n "${restore_body}" ]]; then
        mkdir -p "${CASE_HOME}/.tmux/plugins/tmux-resurrect/scripts"
        printf '#!/bin/bash\n%s\n' "${restore_body}" \
            > "${CASE_HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
        chmod +x "${CASE_HOME}/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
    fi
    env -i HOME="${CASE_HOME}" TMUX_TMPDIR="${CASE}/tmuxtmp" PATH=/usr/bin:/bin \
        F_STATE="${CASE_STATE}" F_FAKE_TMUX="${FAKEBIN}/tmux" \
        "BASH_FUNC_tmux%%=() { \"\${F_FAKE_TMUX}\" \"\$@\"; }" \
        bash "${script}" > "${CASE}/stdout" 2> "${CASE}/stderr"
    RUN_STATUS=$?
}
boot_sessions() { tr '\n' ' ' < "${CASE_STATE}/sessions" 2>/dev/null | sed 's/_tmux_boot_[0-9]*/_tmux_boot_PID/g'; }
# \${F_FAKE_TMUX} is expanded by the fixture, not here.
RESTORE_REAL="\"\${F_FAKE_TMUX}\" new-session -d -s restored"

BOOT="${REPO_ROOT}/${BOOT_PATH}"
new_case
printf 'work\n' > "${CASE_STATE}/sessions"
run_boot "${BOOT}" "${RESTORE_REAL}"
assert_eq "0:work :list-sessions" \
    "${RUN_STATUS}:$(boot_sessions):$(sed 's/ $//' "${CASE_STATE}/argv.log" | tr '\n' ' ' | sed 's/ $//')" \
    "existing server: exit 0, only list-sessions, sessions unchanged"

new_case
run_boot "${BOOT}"
assert_eq "0:_tmux_boot_PID " "${RUN_STATUS}:$(boot_sessions)" \
    "no server, no restore script: bootstrap session kept"

new_case
run_boot "${BOOT}" ":"
assert_eq "0:_tmux_boot_PID " "${RUN_STATUS}:$(boot_sessions)" \
    "no server, restore brings nothing back: bootstrap session kept"

new_case
run_boot "${BOOT}" "${RESTORE_REAL}"
assert_eq "0:restored " "${RUN_STATUS}:$(boot_sessions)" \
    "no server, restore succeeds: bootstrap session dropped"
if grep -q '^kill-ses -t _tmux_boot_' "${CASE_STATE}/argv.log"; then
    pass "bootstrap cleanup bypasses the interactive kill-session alias"
else
    fail "bootstrap cleanup call: $(grep '^kill' "${CASE_STATE}/argv.log")"
fi
PRE_FIX_BOOT="${TMP_ROOT}/boot.pre_fix.bash"
if pre_fix_file "${BOOT_PATH}" "${PRE_FIX_BOOT}"; then
    new_case
    run_boot "${PRE_FIX_BOOT}" "${RESTORE_REAL}"
    assert_eq "0:_tmux_boot_PID restored " "${RUN_STATUS}:$(boot_sessions)" \
        "pre-fix reproduces: alias turns cleanup into confirm-before, bootstrap leaks"
fi

echo "== per-pane history recorder modes and release ownership =="
new_case
recorder_state="${CASE_HOME}/.local/state/tmux/panes"
rm -rf "${recorder_state}"
case_env
# Real Bash sourcing the real recorder; umask 022 so modes come from the code.
# \$ marks what the inner bash expands.
env -i "${CASE_ENV[@]}" TMUX=/fake,1,0 TMUX_PANE=%7 F_PANE_POSITION=rec:0.0 \
    bash --noprofile --norc -c "umask 022; HISTFILE=\${HOME}/.bash_history; set -o history
        history -s 'echo REC_TOKEN'; source \"\${1}\"; _tmux_log_last_cmd" _ \
    "${REPO_ROOT}/${RECORDER_PATH}" 2> "${CASE}/stderr"
assert_mode 700 "${recorder_state}" "recorder: panes dir mode 0700"
assert_mode 600 "${recorder_state}/rec:0.0.last" "recorder: .last mode 0600"
assert_mode 600 "${recorder_state}/rec:0.0.bash_history" "recorder: per-pane history mode 0600"
assert_mode 600 "${recorder_state}/.owner.%7" "recorder: owner claim mode 0600"
assert_eq "echo REC_TOKEN|0a" \
    "$(head -n 1 "${recorder_state}/rec:0.0.last" 2>/dev/null)|$(tail -c 1 "${recorder_state}/rec:0.0.last" | od -An -tx1 | tr -d ' \n')" \
    "recorder: .last is the command plus one line separator"
PANE="rec:0.0"
printf 'rec\t0\t0\tbash\n' > "${CASE_STATE}/panes"
run_prefill "${PREFILL}"
assert_eq "echo REC_TOKEN" "$(cat "$(delivered_file)" 2>/dev/null)" \
    "recorder output is accepted by the prefill script"
PANE="f_sess:0.0"

echo "== last-command logger resolves the calling pane (Bash, Zsh) =="
# Two sessions, three windows; the client's active pane is f_dev:0.0 while
# the logging shell runs elsewhere. f_ops is a session name tmux would also
# accept as a target (it resolves to that session's active pane).
LOGGER_MAP=$'%1 f_dev:0.0\n%2 f_dev:1.0\n%3 f_dev:1.1\n%4 f_ops:0.0\nf_ops f_ops:0.0'
LOGGER_ACTIVE="f_dev:0.0"
LOGGER_SENTINEL="SENTINEL_UNTOUCHED"
declare -A LOGGER_SRC=([bash]="${REPO_ROOT}/${RECORDER_PATH}"
    [zsh]="${REPO_ROOT}/bin/helper/tmux_last_cmd.zsh")
declare -A LOGGER_REC=([bash]="history -s" [zsh]="print -s --")

# logger_case <shell> <source file> <TMUX_PANE or UNSET> <body>: real shell
# sources the logger module; `rec <cmd>` adds <cmd> to its history. Every
# map position starts with a sentinel .last. Sets LS (state dir).
logger_setup() {
    local pos
    new_case
    LS="${CASE_HOME}/.local/state/tmux/panes"
    printf '%s\n' "${LOGGER_MAP}" > "${CASE_STATE}/pane_map"
    for pos in $(awk '{ print $2 }' "${CASE_STATE}/pane_map" | sort -u); do
        printf '%s\n' "${LOGGER_SENTINEL}" > "${LS}/${pos}.last"
    done
}
logger_case() {
    local shell="$1" src="$2" pane_id="$3" body="$4" pane_env=()
    logger_setup
    [[ "${pane_id}" == UNSET ]] || pane_env=(TMUX_PANE="${pane_id}")
    case_env
    local script="umask 022; HISTFILE=\${HOME}/.hist; rec() { ${LOGGER_REC[${shell}]} \"\$1\"; }
        source \"\${1}\"; ${body}"
    if [[ "${shell}" == bash ]]; then
        env -i "${CASE_ENV[@]}" TMUX=/fake,1,0 "${pane_env[@]}" F_ACTIVE_POSITION="${LOGGER_ACTIVE}" \
            bash --noprofile --norc -c "set -o history; ${script}" _ "${src}" 2> "${CASE}/stderr"
    else
        env -i "${CASE_ENV[@]}" TMUX=/fake,1,0 "${pane_env[@]}" F_ACTIVE_POSITION="${LOGGER_ACTIVE}" \
            zsh -f -i -c "${script}" _ "${src}" 2> "${CASE}/stderr" < /dev/null
    fi
    RUN_STATUS=$?
}
# logger_pty_case <shell> <source file> <TMUX_PANE> <command...>: like
# logger_case, but a real interactive shell on a PTY sources the logger and
# runs each command as typed input, so the logger fires from the shell's
# own prompt hook (PROMPT_COMMAND / precmd) once per command, not from a
# scripted call after synthetic history seeding.
# Startup order matches dot_zshrc: it sets precmd_functions before it
# sources the module (zsh -f starts with the array unset, and the module's
# (ie) guard registers nothing then). LOGGER_PTY_INIT=skip leaves the
# array unset (negative control). Right after the source a probe prints
# HOOK_STATE_1 when _tmux_log_last_cmd is a registered prompt hook,
# HOOK_STATE_0 when not; HOOK_STATE holds the value seen (empty: no probe
# output).
declare -A LOGGER_HOOK_INIT=([bash]="" [zsh]="precmd_functions=()")
declare -A LOGGER_HOOK_PROBE=(
    [bash]='[[ ${PROMPT_COMMAND-} == *_tmux_log_last_cmd* ]]; echo HOOK_STATE_$(( ! $? ))'
    [zsh]='echo HOOK_STATE_$(( ${precmd_functions[(Ie)_tmux_log_last_cmd]:-0} > 0 ))')
logger_pty_case() {
    local shell="$1" src="$2" pane_id="$3" prompt cmd steps init
    shift 3
    logger_setup
    steps="${CASE}/steps.logger"
    case "${shell}" in
        bash) prompt='\$ $' ;;
        zsh) prompt='% $' ;;
    esac
    init="${LOGGER_HOOK_INIT[${shell}]}"
    [[ "${LOGGER_PTY_INIT:-}" == skip ]] && init=""
    {
        printf 'wait %s\n' "${prompt}"
        for cmd in ${init:+"${init}"} ". '${src}'" "${LOGGER_HOOK_PROBE[${shell}]}" "$@" exit; do
            printf 'send %s\\r\n' "${cmd}"
            [[ "${cmd}" == exit ]] || printf 'wait %s\n' "${prompt}"
        done
        printf 'eof\n'
    } > "${steps}"
    local sh_cmd=(bash --noprofile --norc -i)
    [[ "${shell}" == zsh ]] && sh_cmd=(zsh -f -i)
    case_env
    env -i "${CASE_ENV[@]}" TERM=xterm TMUX=/fake,1,0 TMUX_PANE="${pane_id}" \
        F_ACTIVE_POSITION="${LOGGER_ACTIVE}" timeout 60 python3 "${PTY_DRIVER}" "${steps}" \
        "${CASE}/transcript.logger" -- "${sh_cmd[@]}" 2> "${CASE}/pty.err"
    RUN_STATUS=$?
    HOOK_STATE=$(sed -n 's/^HOOK_STATE_\([01]\)$/\1/p' "${CASE}/transcript.logger" 2>/dev/null)
}
last_of() { cat "${LS}/$1.last" 2>/dev/null; }
# Positions whose .last no longer holds the sentinel, space-separated.
changed_lasts() {
    local f out=""
    for f in "${LS}"/*.last; do
        [[ "$(cat "${f}")" == "${LOGGER_SENTINEL}" ]] || out+="${f##*/} "
    done
    printf '%s' "${out% }"
}

LOGGER_SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
    LOGGER_SHELLS+=(zsh)
else
    gap "zsh not installed: Zsh last-command logger target resolution not run"
fi
for sh in "${LOGGER_SHELLS[@]}"; do
    src="${LOGGER_SRC[${sh}]}"
    logger_case "${sh}" "${src}" %3 "rec 'echo FROM_INACTIVE'; _tmux_log_last_cmd"
    assert_eq "0|echo FROM_INACTIVE|f_dev:1.1.last" \
        "${RUN_STATUS}|$(last_of f_dev:1.1)|$(changed_lasts)" \
        "${sh} logger: inactive calling pane writes its own .last only"
    # argv.log is printf %q: the format's leading # is escaped.
    if ! grep -qxF -- 'display-message -p \#S:#I.#P ' "${CASE_STATE}/argv.log" \
        && grep -qxF -- 'display-message -p -t %3 \#S:#I.#P ' "${CASE_STATE}/argv.log"; then
        pass "${sh} logger: no untargeted lookup, only -t \$TMUX_PANE"
    else
        fail "${sh} logger: display-message calls: $(grep display "${CASE_STATE}/argv.log" | tr '\n' ';')"
    fi

    logger_case "${sh}" "${src}" %4 "rec 'echo OTHER_SESSION'; _tmux_log_last_cmd"
    assert_eq "0|echo OTHER_SESSION|f_ops:0.0.last" \
        "${RUN_STATUS}|$(last_of f_ops:0.0)|$(changed_lasts)" \
        "${sh} logger: pane in another session writes that session's .last"

    # Pane move between two prompts: the shell's own prompt hook logs each
    # typed command. The move command itself is logged at the new position
    # and then overwritten by AFTER_MOVE.
    printf '%s\n' "sed -i 's/^%3 f_dev:1.1\$/%3 f_ops:2.1/' \"\${F_STATE}/pane_map\"" \
        > "${TMP_ROOT}/move_pane.sh"
    if [[ -z "${PTY_SHELLS[*]}" ]]; then
        gap "${sh} logger: pane-move case needs python3 for the PTY driver"
    else
        logger_pty_case "${sh}" "${src}" %3 "echo BEFORE_MOVE" "sh '${TMP_ROOT}/move_pane.sh'" "echo AFTER_MOVE"
        assert_eq "0|1" "${RUN_STATUS}|${HOOK_STATE}" \
            "${sh} logger fixture: the interactive shell registered _tmux_log_last_cmd as a prompt hook"
        assert_eq "0|echo BEFORE_MOVE|echo AFTER_MOVE|f_dev:1.1.last f_ops:2.1.last" \
            "${RUN_STATUS}|$(last_of f_dev:1.1)|$(last_of f_ops:2.1)|$(changed_lasts)" \
            "${sh} logger: after a pane move (interactive prompts) the next command goes to the new position"
        assert_mode 600 "${LS}/f_ops:2.1.last" "${sh} logger: new .last mode 0600"
        if [[ "${sh}" == zsh ]]; then
            # Probe controls: membership must hold whatever else is
            # registered beside the logger, and be absent otherwise.
            for hooks in "_tmux_log_last_cmd|1" \
                "_tmux_log_last_cmd _tmux_pane_hist_detect _tmux_pane_hist_sync|1" \
                "_tmux_pane_hist_detect _tmux_log_last_cmd _tmux_pane_hist_sync|1" \
                "_tmux_pane_hist_detect _tmux_pane_hist_sync|0" "|0" "UNSET|0"; do
                probe_init="precmd_functions=(${hooks%|*})"
                [[ "${hooks%|*}" == UNSET ]] && probe_init="unset precmd_functions"
                assert_eq "HOOK_STATE_${hooks#*|}" \
                    "$(zsh -f -c "${probe_init}; ${LOGGER_HOOK_PROBE[zsh]}" 2>&1)" \
                    "zsh hook probe: precmd_functions=[${hooks%|*}]"
            done
            # Negative control: without the dotfile's array init the same
            # fixture registers no hook; the probe and the untouched
            # sentinels both show it, although the shell still exits 0.
            LOGGER_PTY_INIT=skip logger_pty_case zsh "${src}" %3 "echo BEFORE_MOVE"
            assert_eq "0|0|" "${RUN_STATUS}|${HOOK_STATE}|$(changed_lasts)" \
                "zsh logger fixture control: unset precmd_functions -> no hook, no .last written"
        fi
    fi

    for bad in UNSET "" %99 f_ops 3 "%3x"; do
        logger_case "${sh}" "${src}" "${bad}" "rec 'echo SHOULD_SKIP'; _tmux_log_last_cmd"
        assert_eq "0|" "${RUN_STATUS}|$(changed_lasts)" \
            "${sh} logger: TMUX_PANE=[${bad}] skipped, no .last written"
    done
done

# Pre-fix control: the same probe shows the untargeted lookup writing the
# active pane's file.
PRE_FIX_RECORDER="${TMP_ROOT}/recorder.pre_fix.bash"
if pre_fix_file "${RECORDER_PATH}" "${PRE_FIX_RECORDER}"; then
    logger_case bash "${PRE_FIX_RECORDER}" %3 "rec 'echo FROM_INACTIVE'; _tmux_log_last_cmd"
    assert_eq "f_dev:0.0.last" "$(changed_lasts)" \
        "pre-fix reproduces: inactive pane's command lands in the active pane's .last"
    if [[ -n "${PTY_SHELLS[*]}" ]]; then
        logger_pty_case bash "${PRE_FIX_RECORDER}" %3 "echo BEFORE_MOVE" "sh '${TMP_ROOT}/move_pane.sh'" "echo AFTER_MOVE"
        assert_eq "0|1|echo AFTER_MOVE|f_dev:0.0.last" \
            "${RUN_STATUS}|${HOOK_STATE}|$(last_of f_dev:0.0)|$(changed_lasts)" \
            "pre-fix reproduces (interactive prompts): the moved pane's commands land in the active pane's .last"
    fi
fi

RELEASE="${REPO_ROOT}/${RELEASE_PATH}"
# release_case: dead %1 at d:0.0, live %2 at d:0.1, stale claim %3 at d:1.0.
release_case() {
    new_case
    RS="${CASE_HOME}/.local/state/tmux/panes"
    local id pos
    for id_pos in %1=d:0.0 %2=d:0.1 %3=d:1.0; do
        id="${id_pos%%=*}" pos="${id_pos#*=}"
        printf 'h\n' > "${RS}/${pos}.bash_history"
        printf 'echo x\n' > "${RS}/${pos}.last"
        printf '%s' "${RS}/${pos}.bash_history" > "${RS}/.owner.${id}"
    done
    printf '%%2\n' > "${CASE_STATE}/live_panes"
}
run_release() {
    case_env
    env -i "${CASE_ENV[@]}" bash "${RELEASE}" "$@" 2> "${CASE}/stderr"
    RUN_STATUS=$?
}
release_case
run_release %1
if [[ "${RUN_STATUS}" == 0 && ! -e "${RS}/d:0.0.bash_history" && ! -e "${RS}/d:0.0.last" \
    && ! -e "${RS}/.owner.%1" && -e "${RS}/d:0.1.bash_history" && -e "${RS}/d:0.1.last" \
    && -e "${RS}/.owner.%2" ]]; then
    pass "release: exited pane files removed, live pane files kept"
else
    fail "release: exited pane: status=${RUN_STATUS} files=$(find "${RS}" -mindepth 1 -printf '%f ')"
fi
assert_file_absent "${RS}/.owner.%3" "release: stale claim of a killed pane dropped"
release_case
run_release %1 "${RS}/d:0.1.bash_history"
if [[ -e "${RS}/d:0.1.bash_history" && -e "${RS}/d:0.1.last" ]]; then
    pass "release: file still claimed by a live pane is kept"
else
    fail "release: live-claimed file removed"
fi
release_case
printf 'x' > "${CASE}/outside.last"
run_release %2 "${CASE}/outside.bash_history"
if [[ -e "${CASE}/outside.last" && -e "${RS}/.owner.%2" ]]; then
    pass "release: path outside the state dir is never removed"
else
    fail "release: outside path handling"
fi

echo "== static contracts (rendered/static, not a service-manager run) =="
# render_conf <os>: minimal renderer for the template constructs used in
# tmux.conf.tmpl; fails on any construct it does not know.
render_conf() {
    python3 -I - "$1" "${REPO_ROOT}/${CONF_PATH}" "${CASE_HOME}/.local/state" <<'PY'
import re, sys
target_os, path, state_home = sys.argv[1:4]
values, active, out, in_comment = {}, [True], [], False
for line in open(path, encoding="utf-8"):
    s = line.strip()
    if in_comment or s.startswith("{{- /*"):
        in_comment = "*/" not in s
        continue
    m = re.fullmatch(r'\{\{-\s*if eq \.chezmoi\.os "(\w+)"\s*-?\}\}', s)
    if m:
        active.append(active[-1] and m.group(1) == target_os)
        continue
    if re.fullmatch(r'\{\{-\s*end\s*-?\}\}', s):
        active.pop()
        continue
    m = re.fullmatch(r'\{\{-\s*\$(\w+)\s*:?=\s*"([^"]*)"\s*-\}\}', s)
    if m:
        if active[-1]:
            values[m.group(1)] = m.group(2)
        continue
    if not active[-1]:
        continue
    line = re.sub(r'\{\{ \$(\w+) \}\}', lambda v: values[v.group(1)], line)
    line = re.sub(r'\{\{ env "XDG_STATE_HOME" \| default \(joinPath \.chezmoi\.homeDir "\.local/state"\) \}\}', state_home, line)
    if "{{" in line:
        sys.exit("unrendered template construct: " + line)
    out.append(line)
sys.stdout.write("".join(out))
PY
}
LINUX_PASTE_BIND=$(cat <<'BIND'
bind C-v run "tmux set-buffer \"$(xclip -o -sel clipboard)\"; tmux paste-buffer"
BIND
)
new_case
if command -v python3 >/dev/null 2>&1; then
    linux_conf=$(render_conf linux) && darwin_conf=$(render_conf darwin)
    if [[ -n "${linux_conf}" && -n "${darwin_conf}" ]]; then
        if grep -q 'copy-pipe-and-cancel "xclip -i -sel clipboard"' <<<"${linux_conf}" \
            && grep -qxF "${LINUX_PASTE_BIND}" <<<"${linux_conf}" \
            && ! grep -q 'pbcopy' <<<"${linux_conf}"; then
            pass "clipboard (Linux render): xclip copy/paste, no pbcopy"
        else
            fail "clipboard (Linux render)"
        fi
        if grep -q 'copy-pipe-and-cancel "pbcopy"' <<<"${darwin_conf}" \
            && grep -q 'tmux_osc52_pbcopy.py' <<<"${darwin_conf}" \
            && ! grep -q 'xclip' <<<"${darwin_conf}"; then
            pass "clipboard (darwin render, static simulation only): pbcopy + OSC 52 pipe-pane"
        else
            fail "clipboard (darwin render)"
        fi
        assert_eq "set -g @resurrect-save-command-strategy 'linux_procfs'" \
            "$(grep 'save-command-strategy' <<<"${linux_conf}")" "Linux render: linux_procfs save strategy"
        assert_eq "" "$(grep 'save-command-strategy' <<<"${darwin_conf}")" \
            "darwin render: default save strategy"
    else
        fail "tmux.conf.tmpl render"
    fi
else
    gap "python3 not installed: tmux.conf.tmpl render checks not run"
fi
service_conf="${REPO_ROOT}/${SERVICE_PATH}"
for want in 'Type=forking' 'ExecStart=%h/bin/tmux_boot.bash' 'Restart=no' 'WantedBy=default.target'; do
    if grep -qxF "${want}" "${service_conf}"; then
        pass "tmux.service: ${want}"
    else
        fail "tmux.service: ${want} missing"
    fi
done
if head -n 1 "${REPO_ROOT}/${ENABLE_PATH}" | grep -qF '{{- if eq .chezmoi.os "linux" -}}' \
    && grep -qF 'systemctl --user is-active tmux.service' "${REPO_ROOT}/${ENABLE_PATH}"; then
    pass "enable script: Linux-only, never restarts an active unit"
else
    fail "enable script guard"
fi
if grep -qF '<string>{{ .chezmoi.homeDir }}/bin/tmux_boot.bash</string>' "${REPO_ROOT}/${PLIST_PATH}" \
    && grep -A1 'KeepAlive' "${REPO_ROOT}/${PLIST_PATH}" | grep -q '<false/>'; then
    pass "LaunchAgent (static only, macOS untested): runs tmux_boot.bash, KeepAlive false"
else
    fail "LaunchAgent contract"
fi
gap "systemd user-manager lifecycle (cgroup ownership, active/dead state, linger, logout) not exercised: needs a service-manager sandbox (docs/systemd-services.md)"

echo "== tmux socket guard (fake real tmux, no server) =="
# The guard every native tmux call goes through. It works out the socket the
# real tmux would use the way tmux does: the last -S wins, else the last -L
# label under ${TMUX_TMPDIR:-/tmp}/tmux-UID, else $TMUX, else the "default"
# label. Global options are parsed with tmux's getopt value flags, so
# clusters (-uS path, -Spath) and options before -S/-L (-f conf, -2) count;
# arguments after the command name do not. A socket outside the test root
# is refused. Allowed calls are logged with the calling process, and the real
# tmux runs with the guard first on PATH: the server and everything it
# spawns (pane shells, run-shell children such as the resurrect scripts,
# even under a /bin/sh that drops exported Bash functions) resolve `tmux`
# to the guard as well.
write_guard() {
    mkdir -p "$1"
    cat > "$1/tmux" <<GUARD
#!/bin/bash
sock="" label=""
args=("\$@")
i=0
while ((i < \${#args[@]})); do
    arg="\${args[i]}"
    [[ "\${arg}" == -- || "\${arg}" != -?* ]] && break
    for ((j = 1; j < \${#arg}; j++)); do
        flag="\${arg:j:1}"
        [[ "${TMUX_VALUE_FLAGS}" == *"\${flag}"* ]] || continue
        value="\${arg:j+1}"
        if [[ -z "\${value}" ]]; then
            i=\$((i + 1))
            value="\${args[i]:-}"
        fi
        [[ "\${flag}" == S ]] && sock="\${value}"
        [[ "\${flag}" == L ]] && label="\${value}"
        break
    done
    i=\$((i + 1))
done
if [[ -z "\${sock}" && -z "\${label}" && -n "\${TMUX:-}" ]]; then
    sock="\${TMUX%%,*}"
fi
[[ -n "\${sock}" ]] || sock="\${TMUX_TMPDIR:-/tmp}/tmux-\$(id -u)/\${label:-default}"
sock=\$(realpath -m -- "\${sock}")
if [[ "\${sock}" != "\$(realpath -m -- "\${F_ROOT:?}")/"* ]]; then
    printf '%s %s\n' "\${sock}" "\$*" >> "\${F_ROOT}/denied.log"
    echo "f-guard: refused tmux socket outside the test root" >&2
    exit ${GUARD_DENY_STATUS}
fi
caller=\$(tr '\\0' ' ' < "/proc/\${PPID}/cmdline" 2>/dev/null || ps -o args= -p "\${PPID}" 2>/dev/null)
printf '%s %s <- %s\n' "\${sock}" "\$*" "\${caller}" >> "\${F_ROOT}/calls.log"
export PATH="\${0%/*}:\${PATH}"
exec "\${F_REAL_TMUX:?}" "\$@"
GUARD
    chmod +x "$1/tmux"
}

G_ROOT="${TMP_ROOT}/guardcheck"
G_IN="${G_ROOT}/tmuxtmp/sock"
G_OUT="${TMP_ROOT}/outside/sock"
write_guard "${G_ROOT}/guardbin"
cat > "${G_ROOT}/real-tmux" <<'REAL'
#!/bin/bash
printf 'RAN %s\n' "${PATH}"
REAL
chmod +x "${G_ROOT}/real-tmux"
# guard_case <allow|deny> <label> [VAR=value...] -- <tmux args...>
guard_case() {
    local expect="$1" label="$2" status ran
    shift 2
    local vars=()
    while [[ "$1" != -- ]]; do vars+=("$1"); shift; done
    shift
    env -i PATH=/usr/bin:/bin F_ROOT="${G_ROOT}" F_REAL_TMUX="${G_ROOT}/real-tmux" "${vars[@]}" \
        "${G_ROOT}/guardbin/tmux" "$@" > "${G_ROOT}/out" 2> /dev/null
    status=$?
    ran=$(cat "${G_ROOT}/out")
    if [[ "${expect}" == allow ]]; then
        assert_eq "0:RAN ${G_ROOT}/guardbin:/usr/bin:/bin" "${status}:${ran}" \
            "guard allows ${label} (real tmux runs with the guard first on PATH)"
    else
        assert_eq "${GUARD_DENY_STATUS}:" "${status}:${ran}" "guard refuses ${label}"
    fi
}
guard_case allow "-S inside the root" -- -S "${G_IN}" list-sessions
guard_case deny "-S outside the root" -- -S "${G_OUT}" list-sessions
# G_TMP: the default socket would be allowed, so only the parsed -S refuses.
G_TMP="TMUX_TMPDIR=${G_ROOT}/tmuxtmp"
guard_case deny "-S outside after -f/-2 global options" "${G_TMP}" -- -f /dev/null -2 -S "${G_OUT}" list-sessions
guard_case deny "clustered -uS outside" "${G_TMP}" -- -uS "${G_OUT}" list-sessions
guard_case deny "attached -S<path> outside" "${G_TMP}" -- "-S${G_OUT}" list-sessions
guard_case deny "last -S outside (inside given first)" "${G_TMP}" -- -S "${G_IN}" -S "${G_OUT}" list-sessions
guard_case allow "last -S inside (outside given first)" -- -S "${G_OUT}" -S "${G_IN}" list-sessions
guard_case deny "-S path leaving the root through .." "${G_TMP}" -- -S "${G_ROOT}/../outside/sock" list-sessions
guard_case allow "-L label under the test TMUX_TMPDIR" TMUX_TMPDIR="${G_ROOT}/tmuxtmp" -- -L lab list-sessions
guard_case deny "-L label under an outside TMUX_TMPDIR" TMUX_TMPDIR="${TMP_ROOT}/outside" -- -L lab list-sessions
guard_case allow "-S over -L" TMUX_TMPDIR="${TMP_ROOT}/outside" -- -L lab -S "${G_IN}" list-sessions
guard_case deny "-L over \$TMUX" TMUX="${G_IN},1,0" TMUX_TMPDIR="${TMP_ROOT}/outside" -- -L lab list-sessions
guard_case deny "\$TMUX outside without socket options" TMUX="${G_OUT},1,0" TMUX_TMPDIR="${G_ROOT}/tmuxtmp" -- list-sessions
guard_case allow "\$TMUX inside without socket options" TMUX="${G_IN},1,0" -- list-sessions
guard_case deny "the default socket without TMUX_TMPDIR" -- list-sessions
guard_case allow "the default socket under the test TMUX_TMPDIR" TMUX_TMPDIR="${G_ROOT}/tmuxtmp" -- list-sessions
guard_case deny "-S after the command name (a command argument, not the socket)" -- list-sessions -S "${G_IN}"
# The real boot script resets PATH; its tmux still reaches the guard through
# the exported function, and the guard decides on the boot environment.
boot_through_guard() {
    rm -f "${G_ROOT}/calls.log" "${G_ROOT}/denied.log"
    env -i HOME="${G_ROOT}" PATH=/usr/bin:/bin F_ROOT="${G_ROOT}" F_REAL_TMUX="${G_ROOT}/real-tmux" "$@" \
        "BASH_FUNC_tmux%%=() { \"\${F_ROOT}/guardbin/tmux\" \"\$@\"; }" \
        bash "${REPO_ROOT}/${BOOT_PATH}" > /dev/null 2>&1
}
boot_through_guard TMUX_TMPDIR="${G_ROOT}/tmuxtmp"
assert_eq "0:1:absent" "$?:$(wc -l < "${G_ROOT}/calls.log" 2>/dev/null):$([[ -e "${G_ROOT}/denied.log" ]] && echo present || echo absent)" \
    "boot script (PATH reset) reaches tmux only through the guard: one allowed call"
boot_through_guard
if [[ -s "${G_ROOT}/denied.log" && ! -e "${G_ROOT}/calls.log" ]]; then
    pass "boot script without the test TMUX_TMPDIR: every tmux call refused, none run"
else
    fail "boot script outside the root: calls=$(cat "${G_ROOT}/calls.log" 2>/dev/null) denied=$(cat "${G_ROOT}/denied.log" 2>/dev/null)"
fi

# native_socket <tmux tmpdir>: create <tmpdir>/tmux-UID (0700, owned by
# us, not a link) and print the default socket path inside it. tmux does not
# create the parents of an explicit -S path, so the first native call failed
# with "error creating .../tmux-UID/default (No such file or directory)".
# Refuses a pre-existing parent that is not exactly that.
native_socket() {
    local dir
    dir="$1/tmux-$(id -u)"
    mkdir -m 700 -- "$1" 2>/dev/null
    mkdir -m 700 -- "${dir}" 2>/dev/null
    [[ -d "${dir}" && ! -L "${dir}" && -O "${dir}" ]] || return 1
    [[ "$(stat -c '%a' -- "${dir}")" == 700 ]] || return 1
    printf '%s/default\n' "${dir}"
}
S_ROOT="${TMP_ROOT}/socketcheck"
mkdir -p "${S_ROOT}"
if s_sock=$(native_socket "${S_ROOT}/fresh"); then
    assert_eq "${S_ROOT}/fresh/tmux-$(id -u)/default" "${s_sock}" "native socket: path under the test tmpdir"
    assert_mode 700 "${S_ROOT}/fresh/tmux-$(id -u)" "native socket: parent created 0700 before first tmux call"
else
    fail "native socket: could not create the private socket parent"
fi
mkdir -p "${S_ROOT}/loose/tmux-$(id -u)" && chmod 755 "${S_ROOT}/loose/tmux-$(id -u)"
if native_socket "${S_ROOT}/loose" > /dev/null; then
    fail "native socket: accepted a 0755 socket parent"
else
    pass "native socket: refuses a pre-existing socket parent that is not 0700"
fi
mkdir -p "${S_ROOT}/linked" "${S_ROOT}/elsewhere" && chmod 700 "${S_ROOT}/elsewhere"
ln -s "${S_ROOT}/elsewhere" "${S_ROOT}/linked/tmux-$(id -u)"
if native_socket "${S_ROOT}/linked" > /dev/null; then
    fail "native socket: accepted a symlinked socket parent"
else
    pass "native socket: refuses a symlinked socket parent"
fi

echo "== native inventory comparison (layout normalisation) =="
# normalize_inventory: inventory() output with only the ephemeral parts of
# each window_layout replaced. tmux allocates fresh %N IDs on restore (the
# bootstrap session takes %0). Two layout formats:
# - legacy string "csum,WxH,X,Y{...}": the 4-hex checksum (it covers the
#   IDs) and each leaf's trailing pane ID;
# - JSON v2 ({"V":2,...}, tmux 3.8): only each "I":"%N" pane ID value; it
#   has no checksum.
# Everything else is kept: pane index "i", cell sizes, offsets, nesting,
# split orientation, active flags, every other field and line order.
normalize_inventory() {
    sed -E '/^W [^ ]+ [01] \{[[:space:]]*"V"[[:space:]]*:/{
        s/("I"[[:space:]]*:[[:space:]]*)"%[0-9]+"/\1"ID"/g
        b
    }
    /^W /{
        s/^(W [^ ]+ [01] )[0-9a-f]{4},/\1/
        s/([0-9]+x[0-9]+,[0-9]+,[0-9]+),[0-9]+/\1,ID/g
    }'
}
# inventory_case <label> <same|differs> <before> <after>
inventory_case() {
    local actual=differs
    [[ "$(normalize_inventory <<<"$3")" == "$(normalize_inventory <<<"$4")" ]] && actual=same
    assert_eq "$2" "${actual}" "inventory normalisation: $1"
}
INV_PANES='P f_dev:1.0 1 40x24 /h/project beta
P f_dev:1.1 0 39x24 /h/project beta'
INV_DUP_PANE="${INV_PANES}"$'\n''P f_dev:1.1 0 39x24 /h/project beta'
# inventory_controls <format> <window line before> <after: new IDs only>
#   <after: pane size> <after: split orientation> <after: duplicated leaf>
#   <after: lost leaf>
inventory_controls() {
    local fmt="$1" before="$2"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: new pane IDs only" same "${before}" "$3"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: changed pane size" differs "${before}" "$4"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: changed split orientation" differs "${before}" "$5"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: duplicated layout leaf" differs "${before}" "$6"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: lost layout leaf" differs "${before}" "$7"$'\n'"${INV_PANES}"
    inventory_case "${fmt}: changed window active flag" differs "${before}" "${before/W f_dev:1 1/W f_dev:1 0}"
    inventory_case "${fmt}: changed pane active flag" differs "${before}" "${before/P f_dev:1.0 1/P f_dev:1.0 0}"
    inventory_case "${fmt}: changed pane cwd" differs "${before}" "${before/1.1 0 39x24 \/h\/project beta/1.1 0 39x24 /h}"
    inventory_case "${fmt}: changed window name" differs "${before}" "${before/ term$'\n'/ shell$'\n'}"
    inventory_case "${fmt}: duplicated pane" differs "${before}" "$2"$'\n'"${INV_DUP_PANE}"
    inventory_case "${fmt}: lost pane" differs "${before}" "${before%$'\n'*}"
}
inventory_controls legacy \
    'W f_dev:1 1 b2a1,80x24,0,0{40x24,0,0,1,39x24,41,0,2} term' \
    'W f_dev:1 1 3c4f,80x24,0,0{40x24,0,0,2,39x24,41,0,3} term' \
    'W f_dev:1 1 b2a1,80x24,0,0{41x24,0,0,1,38x24,42,0,2} term' \
    'W f_dev:1 1 b2a1,80x24,0,0[80x12,0,0,1,80x11,0,13,2] term' \
    'W f_dev:1 1 b2a1,80x24,0,0{40x24,0,0,1,39x24,41,0,2,39x24,41,0,2} term' \
    'W f_dev:1 1 b2a1,80x24,0,0{40x24,0,0,1} term'
# JSON v2 window_layout: "V":2, "L" and the leaf keys "I" (%N pane ID)
# and "i" (pane index) are as tmux 3.8 prints them; the other keys ("T"
# split, "C" children, "A" active) are illustrative. The normaliser only
# touches "I" values, so any other field compares verbatim.
inv_json() {
    printf 'W f_dev:1 1 {"V":2,"L":"80x24,0,0","T":"%s","C":[%s]} term' "$1" "$2"
}
inv_leaf() { printf '{"L":"%s","i":%s,"I":"%%%s","A":%s}' "$1" "$2" "$3" "$4"; }
INV_JSON_LEAVES="$(inv_leaf 40x24,0,0 0 1 1),$(inv_leaf 39x24,41,0 1 2 0)"
inventory_controls json-v2 \
    "$(inv_json lr "${INV_JSON_LEAVES}")" \
    "$(inv_json lr "$(inv_leaf 40x24,0,0 0 2 1),$(inv_leaf 39x24,41,0 1 3 0)")" \
    "$(inv_json lr "$(inv_leaf 41x24,0,0 0 1 1),$(inv_leaf 38x24,42,0 1 2 0)")" \
    "$(inv_json tb "$(inv_leaf 80x12,0,0 0 1 1),$(inv_leaf 80x11,0,13 1 2 0)")" \
    "$(inv_json lr "${INV_JSON_LEAVES},$(inv_leaf 39x24,41,0 1 2 0)")" \
    "$(inv_json lr "$(inv_leaf 40x24,0,0 0 1 1)")"
inventory_case "json-v2: changed layout pane index" differs "$(inv_json lr "${INV_JSON_LEAVES}")" \
    "$(inv_json lr "$(inv_leaf 40x24,0,0 1 1 1),$(inv_leaf 39x24,41,0 0 2 0)")"
inventory_case "json-v2: changed layout active pane" differs "$(inv_json lr "${INV_JSON_LEAVES}")" \
    "$(inv_json lr "$(inv_leaf 40x24,0,0 0 1 0),$(inv_leaf 39x24,41,0 1 2 1)")"

echo "== native tmux + real plugins (private socket) =="
# wait_until <command...>: poll every 0.1s up to NATIVE_TIMEOUT_TENTHS.
wait_until() {
    local tries=0
    until "$@"; do
        ((tries++ >= NATIVE_TIMEOUT_TENTHS)) && return 1
        sleep 0.1
    done
}

# nt <tmux args...>: the guarded real tmux on the private test socket.
nt() { env -i "${NATIVE_ENV[@]}" "${NATIVE_GUARD}" -S "${NATIVE_SOCKET}" "$@"; }
server_gone() { ! kill -0 "$1" 2>/dev/null; }

# stop_native_server: stop the server on NATIVE_SOCKET only once it proves
# to be the test's own: the socket is inside the test root, the server
# reports that socket path and its PID, and that PID is a tmux process.
# Then wait for that PID to exit. Status 2: no server answers there.
stop_native_server() {
    local reported pid
    [[ -n "${NATIVE_SOCKET}" && "${NATIVE_SOCKET}" == "${TMP_ROOT}/"* ]] || return 1
    reported=$(nt display-message -p '#{pid} #{socket_path}' 2>/dev/null) || return 2
    pid="${reported%% *}"
    [[ "${pid}" =~ ^[0-9]+$ && "${reported#* }" == "${NATIVE_SOCKET}" ]] || return 1
    [[ "$(cat "/proc/${pid}/comm" 2>/dev/null || ps -o comm= -p "${pid}" 2>/dev/null)" == *tmux* ]] || return 1
    nt kill-server || return 1
    wait_until server_gone "${pid}"
}

# tree_fingerprint <dir>: hash of every path's type, mode, size, mtime and
# link target plus every file's bytes.
tree_fingerprint() {
    (cd "$1" && find . -printf '%p %y %m %s %T@ %l\n' | LC_ALL=C sort \
        && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum) \
        | sha256sum | cut -d ' ' -f 1
}

# stage_plugins <dest>: copy the authorised plugin inputs into the test
# tree. Each source must be a clean git checkout outside the host's runtime
# plugin dirs (tpm at the pin run_once_install-tpm-plugins.bash enforces).
# Copies, not links: nothing tpm or the plugins do at runtime can write to
# the source. Records each source's fingerprint for the after-run check.
stage_plugins() {
    local dest="$1" p src sha print link host
    local host_dirs=("${HOME}/.tmux/plugins" "${XDG_CONFIG_HOME:-${HOME}/.config}/tmux/plugins")
    for p in "${PLUGINS[@]}"; do
        if ! src=$(realpath -e -- "${F_TMUX_PLUGIN_ROOT}/${p}" 2>/dev/null); then
            gap "plugin ${p}: missing under F_TMUX_PLUGIN_ROOT; native run skipped"
            return 1
        fi
        for host in "${host_dirs[@]}"; do
            if [[ "${src}/" == "$(realpath -m -- "${host}")/"* ]]; then
                gap "plugin ${p}: ${src} is a host runtime plugin dir, not a test input; native run skipped"
                return 1
            fi
        done
        print=$(tree_fingerprint "${src}")
        if ! sha=$(git -C "${src}" rev-parse --verify HEAD 2>/dev/null) || [[ ! "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
            gap "plugin ${p}: not a git checkout; native run skipped"
            return 1
        fi
        if [[ -n "$(git --no-optional-locks -C "${src}" status --porcelain --ignored --untracked-files=all 2>&1)" ]]; then
            gap "plugin ${p}: checkout at ${sha} is not clean; native run skipped"
            return 1
        fi
        if [[ "${p}" == tpm && "${sha}" != "${TPM_PIN}" ]]; then
            gap "plugin tpm: ${sha} is not the pinned ${TPM_PIN}; native run skipped"
            return 1
        fi
        info "plugin ${p} ${sha} (copied from ${src})"
        PLUGIN_SOURCES+=("${src}|${print}")
        cp -a -- "${src}" "${dest}/${p}" || { fail "native: copy plugin ${p}"; return 1; }
        while IFS= read -r -d '' link; do
            if [[ "$(realpath -m -- "${link}")" != "${dest}/${p}/"* ]]; then
                gap "plugin ${p}: symlink ${link#"${dest}/"} points outside the copy; native run skipped"
                return 1
            fi
        done < <(find "${dest}/${p}" -type l -print0)
        if [[ "$(git -C "${dest}/${p}" rev-parse HEAD 2>/dev/null)" != "${sha}" ]]; then
            fail "native: plugin ${p} copy is not at ${sha}"
            return 1
        fi
    done
}

native_tests() {
    local root home state guardbin
    F_REAL_TMUX=$(command -v tmux) || { gap "tmux not installed: native save/restore not run"; return; }
    if [[ -z "${F_TMUX_PLUGIN_ROOT:-}" ]]; then
        gap "F_TMUX_PLUGIN_ROOT unset: real tpm/resurrect/continuum save/restore not run"
        return
    fi
    info "$("${F_REAL_TMUX}" -V) at ${F_REAL_TMUX}"

    root="${TMP_ROOT}/native"
    home="${root}/home"
    state="${home}/.local/state"
    guardbin="${root}/guardbin"
    mkdir -p "${root}"
    NATIVE_SOCKET=$(native_socket "${root}/tmuxtmp") || {
        fail "native: could not create the private socket parent under ${root}/tmuxtmp"; return; }
    mkdir -p "${home}/bin/helper" "${home}/.config/tmux" "${home}/.tmux/plugins" \
        "${home}/project_alpha" "${home}/project beta"
    stage_plugins "${home}/.tmux/plugins" || return
    cp "${REPO_ROOT}/${BOOT_PATH}" "${home}/bin/tmux_boot.bash"
    cp "${PREFILL}" "${home}/bin/tmux_prefill_last_cmd.bash"
    cp "${RELEASE}" "${home}/bin/tmux_pane_hist_release.bash"
    chmod +x "${home}/bin/"*.bash
    cp "${REPO_ROOT}/${RECORDER_PATH}" "${home}/bin/helper/tmux_last_cmd.bash"
    CASE_HOME="${home}" render_conf linux > "${home}/.config/tmux/tmux.conf" || {
        fail "native: config render"; return; }
    # tmux-continuum's documented halt file: the boot script's restore is
    # the path under test, not continuum's racing background auto-restore.
    touch "${home}/tmux_no_auto_restore"
    # Pane shells: only the real recorder module, a fixed prompt.
    cat > "${home}/.bashrc" <<'RC'
HISTFILE="${HOME}/.bash_history"
PS1='F$ '
. "${HOME}/bin/helper/tmux_last_cmd.bash"
RC
    cat > "${home}/.bash_profile" <<'RC'
. "${HOME}/.bashrc"
RC
    write_guard "${guardbin}"

    # GIT_ALLOW_PROTOCOL=file: a stray tpm install/update cannot fetch.
    NATIVE_ENV=(HOME="${home}" XDG_STATE_HOME="${state}" XDG_CONFIG_HOME="${home}/.config"
        TMUX_TMPDIR="${root}/tmuxtmp" PATH="${guardbin}:/usr/bin:/bin" SHELL=/bin/bash
        TERM=xterm-256color LANG=C.UTF-8 F_ROOT="${root}" F_REAL_TMUX="${F_REAL_TMUX}"
        GIT_ALLOW_PROTOCOL=file GIT_CONFIG_NOSYSTEM=1
        "BASH_FUNC_tmux%%=() { \"\${F_ROOT}/guardbin/tmux\" \"\$@\"; }")
    NATIVE_GUARD="${guardbin}/tmux"
    inventory() {
        nt list-windows -a -F 'W #{session_name}:#{window_index} #{window_active} #{window_layout} #{window_name}'
        nt list-panes -a -F 'P #{session_name}:#{window_index}.#{pane_index} #{pane_active} #{pane_width}x#{pane_height} #{pane_current_path}'
    }
    # Last logical line: -J joins lines the pane width wrapped (a long
    # prefilled command spans several rows); -J keeps trailing spaces.
    last_line() { nt capture-pane -p -J -t "$1" | sed 's/[[:space:]]*$//; /^$/d' | tail -n 1; }
    prompt_ready() { [[ "$(last_line "$1")" == 'F$' ]]; }
    has_last() { [[ -s "${state}/tmux/panes/$1.last" ]]; }
    prefilled() { [[ "$(last_line "$1")" == "F\$ $2" ]]; }

    # Before: two sessions, a split window, distinct cwds; each pane runs a
    # command that writes its own sentinel, so .last and history are real.
    nt new-session -d -s f_dev -n editor -c "${home}/project_alpha" || { fail "native: start"; return; }
    nt new-window -d -t f_dev -n term -c "${home}/project beta"
    nt split-window -d -h -t f_dev:term -c "${home}/project beta"
    nt new-session -d -s f_ops -n monitor -c "${home}"
    local panes pane cmd
    mapfile -t panes < <(nt list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
    for pane in "${panes[@]}"; do
        wait_until prompt_ready "${pane}" || { fail "native: no prompt in ${pane}"; return; }
        nt send-keys -t "${pane}" -l -- "printf EXECUTED > ${root}/sentinel.${pane}"
        nt send-keys -t "${pane}" Enter
        wait_until has_last "${pane}" || { fail "native: ${pane} .last not recorded"; return; }
    done
    local before
    before=$(inventory)
    info "before: $(tr '\n' ';' <<<"${before}")"
    nt run-shell "${home}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
    assert_eq "0" "$?" "native: resurrect save.sh via run-shell"
    if [[ -e "${state}/tmux/resurrect/last" ]]; then
        pass "native: snapshot written under synthetic XDG_STATE_HOME"
    else
        fail "native: no snapshot"; return
    fi
    if grep -q 'tmux-resurrect/scripts/save.sh' "${root}/calls.log"; then
        pass "native: save.sh's own tmux calls went through the guard"
    else
        fail "native: no guarded tmux call from save.sh"
    fi
    rm -f "${root}"/sentinel.*
    stop_native_server || { fail "native: could not verify and stop the test server"; return; }
    pass "native: verified test-owned server stopped"

    # No-server branch: the real boot script, PATH reset inside, restore.
    env -i "${NATIVE_ENV[@]}" bash "${home}/bin/tmux_boot.bash" > "${root}/boot.out" 2>&1
    assert_eq 0 "$?" "native: boot (no server) exit 0"
    for pane in "${panes[@]}"; do
        cmd="printf EXECUTED > ${root}/sentinel.${pane}"
        if wait_until prefilled "${pane}" "${cmd}"; then
            pass "native: ${pane} prefilled with its last command"
        else
            fail "native: ${pane} last line [$(last_line "${pane}")]"
        fi
        assert_file_absent "${root}/sentinel.${pane}" "native: ${pane} prefill not executed"
        assert_mode 600 "${state}/tmux/panes/${pane}.bash_history" "native: ${pane} history file kept, mode 0600"
        if grep -qF "${cmd}" "${state}/tmux/panes/${pane}.bash_history" 2>/dev/null; then
            pass "native: ${pane} history contains its command"
        else
            fail "native: ${pane} history lost"
        fi
    done
    assert_eq "$(normalize_inventory <<<"${before}")" "$(inventory | normalize_inventory)" \
        "native: sessions/windows/layout/geometry/active/cwd restored"
    assert_eq "" "$(nt list-sessions -F '#{session_name}' | grep '^_tmux_boot_')" \
        "native: bootstrap session dropped after a successful restore"
    if grep -q 'tmux-resurrect/scripts/restore.sh' "${root}/calls.log"; then
        pass "native: restore.sh's own tmux calls went through the guard"
    else
        fail "native: no guarded tmux call from restore.sh"
    fi
    nt send-keys -t "${panes[0]}" Enter
    sentinel_written() { [[ -e "${root}/sentinel.${panes[0]}" ]]; }
    if wait_until sentinel_written; then
        pass "native: prefilled command runs only after explicit Enter"
    else
        fail "native: positive control Enter did not run the command"
    fi

    # Existing-server branch: no change to the session inventory.
    local sessions_before
    sessions_before=$(nt list-sessions -F '#{session_name}')
    env -i "${NATIVE_ENV[@]}" bash "${home}/bin/tmux_boot.bash" > "${root}/boot2.out" 2>&1
    assert_eq "0:${sessions_before}" "$?:$(nt list-sessions -F '#{session_name}')" \
        "native: boot with a running server is a no-op"
    nt kill-session -t f_ops 2>/dev/null
    assert_eq "${sessions_before}" "$(nt list-sessions -F '#{session_name}')" \
        "native: interactive kill-session still requires confirmation"

    # Restore-empty branch: no snapshot, bootstrap keeps the server alive.
    stop_native_server || { fail "native: could not verify and stop the test server"; return; }
    mv "${state}/tmux/resurrect" "${state}/tmux/resurrect.off"
    env -i "${NATIVE_ENV[@]}" bash "${home}/bin/tmux_boot.bash" > "${root}/boot3.out" 2>&1
    assert_eq "0:_tmux_boot_" "$?:$(nt list-sessions -F '#{session_name}' | sed 's/[0-9]*$//')" \
        "native: boot with no snapshot keeps only the bootstrap session"
    stop_native_server || fail "native: final verified stop of the test server"

    if [[ -e "${root}/denied.log" ]]; then
        fail "native: guard refused calls: $(head -n 3 "${root}/denied.log")"
    else
        pass "native: every guarded tmux call stayed on the private socket ($(wc -l < "${root}/calls.log") calls)"
    fi
}
native_tests
# Runs whatever native_tests returned through: every staged source must be
# byte-for-byte and metadata-identical to before.
for entry in "${PLUGIN_SOURCES[@]}"; do
    assert_eq "${entry##*|}" "$(tree_fingerprint "${entry%|*}")" \
        "native: plugin source ${entry%|*} unchanged (bytes, modes, mtimes)"
done

echo
echo "failures=${failures} gaps=${gaps}"
[[ "${failures}" == 0 ]]
