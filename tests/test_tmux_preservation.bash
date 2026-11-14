#!/usr/bin/env bash
# tmux session preservation (#55/#61): boot script, bootstrap cleanup,
# tmux_main_session, post-restore prefill, post-save snapshot filter,
# per-pane last-command/history files, and the rendered tmux.conf that
# wires them together — run against a REAL tmux server on a private socket
# (tests/lib/tmux_fixture.bash: own TMUX_TMPDIR per scenario, every tmux
# call through a socket guard; the host's default socket is never touched).
#
# Default layer: real tmux + the tmux.conf rendered by `chezmoi
# execute-template`, a no-op tpm, and a stand-in restore.sh that creates
# sessions and runs the configured post-restore hook the way
# tmux-resurrect's restore.sh does (eval "$hook").
# Native layer (section `native`): real tpm/tmux-resurrect/tmux-continuum
# at pinned SHAs, copied from F_TMUX_PLUGIN_ROOT or a cache that is
# filled with `git fetch` on first use (TMUX_TEST_OFFLINE=1: no fetch;
# missing plugins are then a counted SKIP).
#
# Simulated, and labelled so: tmux missing (the boot script's tmux lookup
# is made to fail; /usr/bin/tmux cannot be hidden without a namespace),
# the macOS lsof branch of the save filter (readlink hidden, Linux lsof),
# the darwin render (chezmoi --override-data). Not covered: systemd
# user-manager lifecycle (only `systemd-analyze verify`).
#
# Usage: bash tests/test_tmux_preservation.bash
#        TMUX_TEST_ONLY="boot main" bash tests/test_tmux_preservation.bash
# Sections: prefill boot main cleanup filter history config units native bash32

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"
# shellcheck source=tests/lib/tmux_fixture.bash
source "${REPO_ROOT}/tests/lib/tmux_fixture.bash"

BOOT="${REPO_ROOT}/bin/executable_tmux_boot.bash"
T=$'\t'
EXEC_CMD='printf EXECUTED > {S}'
# Plugin pins for the native layer. tpm: the installer's pin.
TPM_PIN=$(sed -n 's/^TPM_TAG_SHA="\([0-9a-f]\{40\}\)"$/\1/p' "${REPO_ROOT}/run_once_install-tpm-plugins.bash")
PLUGIN_PINS=("tpm ${TPM_PIN}"
    "tmux-resurrect cff343cf9e81983d3da0c8562b01616f12e8d548"
    "tmux-continuum 0698e8f4b17d6454c71bf5212895ec055c578da0")

section_enabled() {
    [[ -z "${TMUX_TEST_ONLY:-}" || " ${TMUX_TEST_ONLY//,/ } " == *" $1 "* ]]
}

panes_dir() { printf '%s/tmux/panes' "${TS_STATE}"; }

# write_last <pane position> <printf %b format>
write_last() {
    mkdir -p "$(panes_dir)"
    printf '%b' "$2" > "$(panes_dir)/$1.last"
}

pane_line_is() { [[ "$(tmuxf_last_line "$1")" == "$2" ]]; }
file_exists() { [[ -e "$1" ]]; }
file_absent() { [[ ! -e "$1" ]]; }
file_has() { grep -qF -- "$2" "$1" 2> /dev/null; }

# stub_restore <run hook: 0|1> [name<TAB>dir...]: the stand-in restore.sh.
stub_restore() {
    local hook="$1" scripts="${TS_HOME}/.tmux/plugins/tmux-resurrect/scripts"
    shift
    mkdir -p "${scripts}"
    printf '%s\n' "$@" > "${TS_HOME}/restore.sessions"
    [[ "${hook}" == 1 ]] && : > "${TS_HOME}/restore.hook"
    cat > "${scripts}/restore.sh" <<'STUB'
#!/bin/bash
# Stand-in for tmux-resurrect's restore.sh (run by `tmux run-shell`):
# creates the sessions in ~/restore.sessions, waits for each shell prompt,
# then runs the configured post-restore hook as restore.sh's execute_hook
# does: eval "$hook $args".
: > "${HOME}/restore.ran"
while IFS=$'\t' read -r name dir; do
    [[ -n "${name}" ]] || continue
    tmux new-session -d -s "${name}" -c "${dir}" -x 200 -y 50
    for _ in $(seq 100); do
        line=$(tmux capture-pane -p -t "=${name}:" | sed 's/[[:space:]]*$//; /^$/d' | tail -n 1)
        [[ "${line}" == 'F$' ]] && break
        sleep 0.1
    done
done < "${HOME}/restore.sessions"
if [[ -e "${HOME}/restore.hook" ]]; then
    hook=$(tmux show-option -gqv @resurrect-hook-post-restore-all)
    eval "${hook} "
fi
STUB
    chmod +x "${scripts}/restore.sh"
}

snapshot_on_disk() {
    mkdir -p "${TS_STATE}/tmux/resurrect"
    : > "${TS_STATE}/tmux/resurrect/last"
}

run_boot() { tmuxf_run_in / bash "${BOOT}"; }

run_main_session() {
    tmuxf_run_in "${TS_HOME}" TMUX_SESSION=i3-tmux-0 \
        bash -c '. "${HOME}/bin/helper/tmux.bash"; tmux_main_session' < /dev/null
}

# continuum gate: off and the owner flag dropped (boot-started server).
assert_boot_owned_restore() {
    assert_eq off "$(tx show -gv @continuum-restore 2> /dev/null)" \
        "$1: continuum auto-restore off (boot owns the restore)"
    assert_eq "" "$(tx show-environment -g 2> /dev/null | grep '^TMUX_BOOT_RESTORE=')" \
        "$1: TMUX_BOOT_RESTORE not left in the global environment"
}

# ===========================================================================
# prefill: bin/tmux_prefill_last_cmd.bash typing into real pane shells
# ===========================================================================
ACCEPTED_TEXT=$(cat <<'TEXT'
printf "%s\n" "a b" | grep -E 'x|y' > "/tmp/dir with space/ö" && echo $HOME; ls ~ # ✓
TEXT
)
P_KIND=() P_LABEL=() P_TEXT=() P_SHELL=()
# pcase <ok|rejected> <label> <.last printf %b format> [shell]
pcase() { P_KIND+=("$1") P_LABEL+=("$2") P_TEXT+=("$3") P_SHELL+=("${4:-bash}"); }
pcase ok "shell punctuation, quoted paths and Unicode" "${ACCEPTED_TEXT//\\/\\\\}\\n"
pcase ok "accepted command [bash]" "${EXEC_CMD}\\n"
pcase ok "accepted command [zsh]" "${EXEC_CMD}\\n" zsh
pcase ok "text 'Enter' typed literally" 'Enter\n'
pcase ok "text 'C-m' typed literally" 'C-m\n'
pcase ok "text 'BSpace' typed literally" 'BSpace\n'
pcase rejected "empty file" ''
pcase rejected "separator only" '\n'
pcase rejected "spaces only" '   \n'
pcase rejected "tabs only" '\t\t\n'
pcase rejected "terminated multi-line" "${EXEC_CMD}\\necho b\\n"
pcase rejected "unterminated multi-line [bash]" "${EXEC_CMD}\\necho b"
pcase rejected "unterminated multi-line [zsh]" "${EXEC_CMD}\\necho b" zsh
pcase rejected "NUL byte" "${EXEC_CMD}\\x00; echo b\\n"
pcase rejected "ESC sequence" 'echo a\x1b[A\n'
pcase rejected "C0 0x01" "${EXEC_CMD}\\x01b\\n"
pcase rejected "CR (0x0d)" "${EXEC_CMD}\\r\\n"
pcase rejected "Ctrl+O (0x0f)" "${EXEC_CMD}\\x0f\\n"
pcase rejected "Ctrl+O (0x0f) [zsh]" "${EXEC_CMD}\\x0f\\n" zsh
pcase rejected "C0 0x1f" "${EXEC_CMD}\\x1fb\\n"
pcase rejected "DEL (0x7f)" "${EXEC_CMD}\\x7f\\n"

test_prefill_cases() {
    local i n="${#P_KIND[@]}" win sentinel text label nonshell noconf
    tmuxf_scenario prefill || return
    tx new-session -d -s pf -x 200 -y 50
    for ((i = 0; i < n; i++)); do
        win=$((i + 1))
        if [[ "${P_SHELL[i]}" == zsh ]]; then
            tx new-window -d -t "pf:${win}" 'exec zsh -i'
        else
            tx new-window -d -t "pf:${win}"
        fi
    done
    nonshell=$((n + 1)) noconf=$((n + 2))
    tx new-window -d -t "pf:${nonshell}" 'exec sleep 300'
    tx new-window -d -t "pf:${noconf}"
    for ((win = 1; win <= n; win++)); do
        wait_until 10 tmuxf_prompt_ready "pf:${win}" || { fail "prefill: no prompt in pf:${win}"; return; }
    done
    wait_until 10 tmuxf_prompt_ready "pf:${noconf}" || { fail "prefill: no prompt in pf:${noconf}"; return; }
    # After the first prompt: the shells' recorder rewrites .last there.
    for ((i = 0; i < n; i++)); do
        win=$((i + 1))
        write_last "pf:${win}.0" "${P_TEXT[i]//\{S\}/${TS_ROOT}/sentinel.${win}}"
    done
    write_last "pf:${nonshell}.0" 'echo nonshell\n'

    tmuxf_run "${TS_HOME}/bin/tmux_prefill_last_cmd.bash"
    assert_status 0 "${RUN_STATUS}" "prefill: exit 0"
    assert_eq "" "${RUN_STDERR}" "prefill: no stderr"

    for ((i = 0; i < n; i++)); do
        win=$((i + 1)) label="prefill ${P_KIND[i]}: ${P_LABEL[i]}"
        sentinel="${TS_ROOT}/sentinel.${win}"
        if [[ "${P_KIND[i]}" == ok ]]; then
            text=$(printf '%b' "${P_TEXT[i]//\{S\}/${sentinel}}")
            if wait_until 5 pane_line_is "pf:${win}" "F\$ ${text}"; then
                pass "${label}: typed into the pane"
            else
                fail "${label}: pane shows [$(tmuxf_last_line "pf:${win}")]"
            fi
        else
            # A marker typed after the prefill: once it shows, anything
            # sent before it has been read by the shell too.
            tx send-keys -l -t "pf:${win}" '#'
            if wait_until 5 pane_line_is "pf:${win}" "F\$ #"; then
                pass "${label}: nothing typed"
            else
                fail "${label}: pane shows [$(tmuxf_last_line "pf:${win}")]"
            fi
        fi
        assert_eq absent "$([[ -e "${sentinel}" ]] && echo present || echo absent)" \
            "${label}: nothing executed"
    done
    assert_eq "" "$(tx capture-pane -p -t "pf:${nonshell}" | tr -d ' \n')" \
        "prefill: non-shell pane (sleep) receives nothing"
    tx send-keys -l -t "pf:${noconf}" '#'
    wait_until 5 pane_line_is "pf:${noconf}" "F\$ #"
    assert_eq "F\$ #" "$(tmuxf_last_line "pf:${noconf}")" "prefill: pane without a .last file is skipped"

    # Positive control per shell: the accepted command runs on Enter only.
    for ((i = 0; i < n; i++)); do
        [[ "${P_LABEL[i]}" == "accepted command ["* ]] || continue
        win=$((i + 1))
        tx send-keys -t "pf:${win}" Enter
        if wait_until 5 file_exists "${TS_ROOT}/sentinel.${win}"; then
            pass "prefill positive control ${P_LABEL[i]#accepted command }: runs after an explicit Enter"
        else
            fail "prefill positive control ${P_LABEL[i]#accepted command }: Enter did not run it"
        fi
    done
}

# Closed-pane race: the pane is killed between list-panes and its
# send-keys (a wrapper before the guard kills it on that send-keys).
test_prefill_closed_pane_race() {
    tmuxf_scenario prefill-race || return
    tx new-session -d -s r -x 200 -y 50
    tx new-window -d -t r:1
    tx new-window -d -t r:2
    local w
    for w in 0 1 2; do
        wait_until 10 tmuxf_prompt_ready "r:${w}" || { fail "prefill race: no prompt in r:${w}"; return; }
    done
    write_last r:0.0 'echo gone\n'
    write_last r:1.0 'echo survivor\n'
    mkdir -p "${TS_ROOT}/racebin"
    cat > "${TS_ROOT}/racebin/tmux" <<'RACE'
#!/bin/bash
[[ "$1 $2 $3 $4" == "send-keys -l -t r:0.0" ]] && "${F_ROOT}/guardbin/tmux" kill-pane -t r:0.0
exec "${F_ROOT}/guardbin/tmux" "$@"
RACE
    chmod +x "${TS_ROOT}/racebin/tmux"
    tmuxf_run "BASH_FUNC_tmux%%=() { \"\${F_ROOT}/racebin/tmux\" \"\$@\"; }" \
        "${TS_HOME}/bin/tmux_prefill_last_cmd.bash"
    assert_status 0 "${RUN_STATUS}" "prefill race: exit 0 although one send-keys failed"
    assert_eq "" "$(tx list-windows -t r -F '#{window_index}' | grep -x 0)" \
        "prefill race: fixture killed the first pane"
    wait_until 5 pane_line_is r:1 "F\$ echo survivor"
    assert_eq "F\$ echo survivor" "$(tmuxf_last_line r:1)" "prefill race: later pane still prefilled"
}

test_prefill_no_state_dir() {
    tmuxf_scenario prefill-nostate || return
    tx new-session -d -s n
    wait_until 10 tmuxf_prompt_ready n || { fail "prefill no-state: no prompt"; return; }
    rm -rf "$(panes_dir)"
    tmuxf_run "${TS_HOME}/bin/tmux_prefill_last_cmd.bash"
    assert_status 0 "${RUN_STATUS}" "prefill: missing state dir exits 0"
    assert_eq "" "${RUN_STDERR}" "prefill: missing state dir, no stderr"
}

# ===========================================================================
# boot: bin/tmux_boot.bash (systemd unit / LaunchAgent), started from `/`
# ===========================================================================
test_boot_no_restore_script() {
    tmuxf_scenario boot-norestore || return
    run_boot
    assert_status 0 "${RUN_STATUS}" "boot, no restore script: exit 0"
    assert_eq main "$(tmuxf_sessions)" "boot, no restore script: server kept alive in one session named main"
    assert_eq "${TS_HOME}" "$(tx display-message -p -t main '#{pane_current_path}')" \
        "boot from / (launchd): server and its session start in \$HOME"
    assert_boot_owned_restore "boot, no restore script"
}

test_boot_restore_success() {
    tmuxf_scenario boot-restore || return
    mkdir -p "${TS_HOME}/proj"
    # As saved: the pane's history and .last (its shell re-records .last
    # from the history at its first prompt).
    write_last work:0.0 'echo restored-cmd\n'
    printf 'echo restored-cmd\n' > "$(panes_dir)/work:0.0.bash_history"
    stub_restore 1 "work${T}${TS_HOME}/proj"
    run_boot
    assert_status 0 "${RUN_STATUS}" "boot, restore succeeds: exit 0"
    assert_eq work "$(tmuxf_sessions)" "boot, restore succeeds: only the restored session, bootstrap dropped"
    wait_until 5 pane_line_is work "F\$ echo restored-cmd"
    assert_eq "F\$ echo restored-cmd" "$(tmuxf_last_line work)" \
        "boot, restore succeeds: post-restore hook prefilled the restored pane"
    assert_boot_owned_restore "boot, restore succeeds"
}

# The post-restore cleanup hook usually drops the bootstrap; without it the
# boot script's own kill (kill-ses, not the aliased kill-session) must.
test_boot_restore_without_hook() {
    tmuxf_scenario boot-nohook || return
    stub_restore 0 "work${T}${TS_HOME}"
    run_boot
    assert_status 0 "${RUN_STATUS}" "boot, restore without hook: exit 0"
    assert_eq work "$(tmuxf_sessions)" "boot, restore without hook: boot script drops its own bootstrap"
}

test_boot_restore_empty() {
    tmuxf_scenario boot-empty || return
    stub_restore 1
    run_boot
    assert_status 0 "${RUN_STATUS}" "boot, restore brings nothing back: exit 0"
    assert_eq main "$(tmuxf_sessions)" "boot, restore brings nothing back: bootstrap renamed to main"
}

test_boot_restore_placeholder_only() {
    tmuxf_scenario boot-placeholder || return
    stub_restore 1 "_main_boot_77${T}${TS_HOME}"
    run_boot
    assert_eq "_main_boot_77 main" "$(tmuxf_sessions)" \
        "boot, restore brings back only a placeholder: own bootstrap renamed, not killed"
}

test_boot_existing_server() {
    tmuxf_scenario boot-existing || return
    stub_restore 1 "other${T}${TS_HOME}"
    tx new-session -d -s work
    run_boot
    assert_status 0 "${RUN_STATUS}" "boot, server running: exit 0"
    assert_eq work "$(tmuxf_sessions)" "boot, server running: sessions unchanged"
    assert_eq absent "$([[ -e "${TS_HOME}/restore.ran" ]] && echo present || echo absent)" \
        "boot, server running: no restore"
    assert_eq on "$(tx show -gv @continuum-restore)" \
        "server started without the boot owner flag: continuum auto-restore on"
}

# Simulated: /usr/bin/tmux cannot be hidden without a mount namespace, so
# the script's `command -v tmux` lookup is made to fail instead.
test_boot_tmux_missing() {
    tmuxf_scenario boot-notmux || return
    tmuxf_run_in / "BASH_FUNC_command%%=() { [[ \"\$*\" == '-v tmux' ]] && return 1; builtin command \"\$@\"; }" \
        bash "${BOOT}"
    assert_status 0 "${RUN_STATUS}" "boot, tmux missing (simulated lookup failure): exit 0, no restart loop"
    assert_eq "tmux not on PATH" "${RUN_STDOUT}" "boot, tmux missing (simulated): says so"
    assert_eq absent "$([[ -S "${TS_SOCK}" ]] && echo present || echo absent)" \
        "boot, tmux missing (simulated): no server started"
}

# ===========================================================================
# main: tmux_main_session (bin/helper/tmux.bash, i3 path)
# ===========================================================================
test_main_restore() {
    tmuxf_scenario main-restore || return
    snapshot_on_disk
    stub_restore 1 "work${T}${TS_HOME}"
    run_main_session
    assert_eq work "$(tmuxf_sessions)" "tmux_main_session, snapshot: restored, _main_boot_<pid> dropped"
    assert_boot_owned_restore "tmux_main_session, snapshot"
}

test_main_restore_without_hook() {
    tmuxf_scenario main-nohook || return
    snapshot_on_disk
    stub_restore 0 "work${T}${TS_HOME}"
    run_main_session
    assert_eq work "$(tmuxf_sessions)" \
        "tmux_main_session, restore without hook: drops its own bootstrap (kill-ses)"
}

# Snapshot restores nothing: the bootstrap is dropped (the server exits)
# and the default layout is built on a fresh server.
test_main_restore_empty() {
    tmuxf_scenario main-empty || return
    mkdir -p "${TS_HOME}/.local/share/chezmoi"
    snapshot_on_disk
    stub_restore 1
    run_main_session
    assert_eq present "$([[ -e "${TS_HOME}/restore.ran" ]] && echo present || echo absent)" \
        "tmux_main_session, empty restore: restore ran"
    assert_eq i3-tmux-0 "$(tmuxf_sessions)" "tmux_main_session, empty restore: default layout built instead"
}

test_main_default_layout() {
    local chezmoi_dir
    tmuxf_scenario main-layout || return
    chezmoi_dir="${TS_HOME}/.local/share/chezmoi"
    mkdir -p "${chezmoi_dir}"
    run_main_session
    assert_eq i3-tmux-0 "$(tmuxf_sessions)" "tmux_main_session, no snapshot: session from TMUX_SESSION"
    assert_eq "chezmoi WorkSpace" "$(tx list-windows -t i3-tmux-0 -F '#{window_name}' | tr '\n' ' ' | sed 's/ $//')" \
        "tmux_main_session, no snapshot: windows chezmoi and WorkSpace"
    assert_eq "${chezmoi_dir} ${chezmoi_dir} ${chezmoi_dir}" \
        "$(tx list-panes -t i3-tmux-0:chezmoi -F '#{pane_index} #{pane_current_path}' | sed -n 's/^[123] //p' | tr '\n' ' ' | sed 's/ $//')" \
        "tmux_main_session, no snapshot: chezmoi window split into 4 panes, panes 1-3 in the chezmoi dir"
    assert_eq "chezmoi 0" "$(tx display-message -p -t i3-tmux-0 '#{window_name} #{pane_index}')" \
        "tmux_main_session, no snapshot: first pane of the chezmoi window selected"
    if wait_until 5 pane_line_is i3-tmux-0:chezmoi.0 "F\$ ${TS_HOME}/ai-wrapper/bin/claude_wrapper.bash"; then
        pass "tmux_main_session, no snapshot: claude_wrapper typed into pane 0, not run"
    else
        fail "tmux_main_session, no snapshot: pane 0 shows [$(tmuxf_last_line i3-tmux-0:chezmoi.0)]"
    fi
    assert_eq "${chezmoi_dir}" "$(tx display-message -p -t i3-tmux-0:chezmoi.0 '#{pane_current_path}')" \
        "tmux_main_session, no snapshot: pane 0 cd'd into the chezmoi dir"
    if wait_until 5 file_has "$(panes_dir)/i3-tmux-0:0.3.last" hh_git_watch; then
        pass "tmux_main_session, no snapshot: hh_git_watch run in pane 3"
    else
        fail "tmux_main_session, no snapshot: pane 3 did not run hh_git_watch"
    fi
}

test_main_existing_session() {
    tmuxf_scenario main-existing || return
    snapshot_on_disk
    stub_restore 1 "other${T}${TS_HOME}"
    tx new-session -d -s i3-tmux-0
    tx new-session -d -s side
    run_main_session
    assert_eq "i3-tmux-0 side" "$(tmuxf_sessions)" "tmux_main_session, session exists: sessions unchanged"
    assert_eq absent "$([[ -e "${TS_HOME}/restore.ran" ]] && echo present || echo absent)" \
        "tmux_main_session, session exists: no restore"
}

# The interactive kill-session alias (why every script uses kill-ses).
test_kill_session_alias() {
    tmuxf_scenario alias || return
    tx new-session -d -s a
    tx new-session -d -s b
    tx kill-session -t b 2> /dev/null
    assert_eq "a b" "$(tmuxf_sessions)" "tmux.conf: kill-session without a client still asks for confirmation"
    tx kill-ses -t =b
    assert_eq a "$(tmuxf_sessions)" "tmux.conf: kill-ses (unique prefix) kills"
}

# ===========================================================================
# cleanup: bin/tmux_bootstrap_cleanup.bash
# ===========================================================================
# test_cleanup [interpreter]
test_cleanup() {
    local sh="${1:-bash}" tag="${2:-}"
    tmuxf_scenario cleanup || return
    local s
    for s in work _tmux_boot_1 _main_boot_2 _main_boot_x my_main_boot_3; do
        tx new-session -d -s "${s}"
    done
    tmuxf_run "${sh}" "${TS_HOME}/bin/tmux_bootstrap_cleanup.bash"
    assert_status 0 "${RUN_STATUS}" "cleanup${tag}: exit 0"
    assert_eq "" "${RUN_STDERR}" "cleanup${tag}: no stderr"
    assert_eq "_main_boot_x my_main_boot_3 work" "$(tmuxf_sessions)" \
        "cleanup${tag}: every _tmux_boot_N/_main_boot_N killed, look-alike names kept"

    tmuxf_stop
    tx new-session -d -s _tmux_boot_1
    tx new-session -d -s _main_boot_2
    tmuxf_run "${sh}" "${TS_HOME}/bin/tmux_bootstrap_cleanup.bash"
    assert_eq "0:_main_boot_2 _tmux_boot_1" "${RUN_STATUS}:$(tmuxf_sessions)" \
        "cleanup${tag}: nothing killed while only bootstrap sessions keep the server alive"

    tmuxf_stop
    tmuxf_run "${sh}" "${TS_HOME}/bin/tmux_bootstrap_cleanup.bash"
    assert_eq "0:" "${RUN_STATUS}:${RUN_STDERR}" "cleanup${tag}: no server, exit 0 quietly"
}

# ===========================================================================
# filter: bin/tmux_resurrect_save_filter.bash (post-save-layout hook)
# ===========================================================================
snap_line() { printf '%s\n' "$1" | sed "s/|/${T}/g"; }

# run_filter <snapshot> [interpreter]: default: the configured hook value
# from the live server through `eval "$hook $args"` with the path
# %q-quoted, as resurrect's save.sh does; else <interpreter> <script>.
run_filter() {
    if [[ -z "${2:-}" ]]; then
        local hook
        hook=$(tx show -gv @resurrect-hook-post-save-layout)
        tmuxf_run bash -c 'printf -v args "%q " "$2"; eval "$1 $args"' _ "${hook}" "$1"
    else
        tmuxf_run "$2" "${TS_HOME}/bin/tmux_resurrect_save_filter.bash" "$1"
    fi
}

test_filter() {
    local sh="${1:-}" tag="${2:-}" snap cwd
    tmuxf_scenario filter || return
    snap="${TS_STATE}/tmux/resurrect"
    cwd="${TS_HOME}/cwd dir"
    mkdir -p "${snap}" "${cwd}"
    tx new-session -d -s work -c "${cwd}"
    wait_until 10 tmuxf_prompt_ready work || { fail "filter: no prompt"; return; }
    {
        snap_line 'pane|work|0|1|:*|0|t|:|1|bash|:'
        snap_line 'pane|work|1|0|:-|0||:/w/a|1|bash|:'
        snap_line 'pane|work|2|0|:-|0||:|1|bash|:'
        snap_line 'pane|_main_boot_9|0|1|:*|0|t|:/|1|bash|:'
        snap_line 'window|work|0|:ed|1|:*|c0de,80x24,0,0,0|on'
        snap_line 'window|_main_boot_9|0|:zsh|1|:*|c0de,80x24,0,0,1|:'
        snap_line 'grouped_session|_tmux_boot_5|work|:|:0'
        snap_line 'state|work|_main_boot_9'
    } > "${snap}/new.txt"
    run_filter "${snap}/new.txt" "${sh}"
    assert_status 0 "${RUN_STATUS}" "save filter${tag}: exit 0"
    {
        snap_line "pane|work|0|1|:*|0|t|:${cwd}|1|bash|:"
        snap_line 'pane|work|1|0|:-|0||:/w/a|1|bash|:'
        snap_line 'pane|work|2|0|:-|0||:|1|bash|:'
        snap_line 'window|work|0|:ed|1|:*|c0de,80x24,0,0,0|on'
        snap_line 'state|work|_main_boot_9'
    } > "${TS_ROOT}/want.txt"
    assert_eq "$(cat "${TS_ROOT}/want.txt")" "$(cat "${snap}/new.txt")" \
        "save filter${tag}: bootstrap lines dropped, empty path filled from the live pane's shell, unknown pane left empty"

    # Only bootstrap sessions: the previous snapshot's bytes come back, so
    # resurrect sees no change and keeps `last`.
    snap_line 'pane|work|0|1|:*|0|t|:/w/a|1|bash|:' > "${snap}/prev.txt"
    ln -sf prev.txt "${snap}/last"
    {
        snap_line 'pane|_tmux_boot_4|0|1|:*|0|t|:/|1|bash|:'
        snap_line 'window|_tmux_boot_4|0|:bash|1|:*|c0de,80x24,0,0,0|:'
        snap_line 'state|_tmux_boot_4|'
    } > "${snap}/new.txt"
    run_filter "${snap}/new.txt" "${sh}"
    assert_eq "0:$(cat "${snap}/prev.txt")" "${RUN_STATUS}:$(cat "${snap}/new.txt")" \
        "save filter${tag}: bootstrap-only snapshot replaced by the previous one (last kept)"

    [[ -z "${sh}" ]] || return 0
    # macOS branch, SIMULATED on Linux: readlink (the /proc answer) hidden,
    # Linux lsof answers instead of macOS lsof.
    require_cmd "save filter lsof branch (simulated macOS)" lsof || return 0
    mkdir -p "${TS_ROOT}/noproc"
    printf '#!/bin/sh\nexit 1\n' > "${TS_ROOT}/noproc/readlink"
    chmod +x "${TS_ROOT}/noproc/readlink"
    snap_line 'pane|work|0|1|:*|0|t|:|1|bash|:' > "${snap}/new.txt"
    tmuxf_run PATH="${TS_ROOT}/noproc:${TS_ROOT}/guardbin:/usr/bin:/bin" \
        bash "${TS_HOME}/bin/tmux_resurrect_save_filter.bash" "${snap}/new.txt"
    assert_eq "0::${cwd}" "${RUN_STATUS}:$(cut -f 8 "${snap}/new.txt")" \
        "save filter, lsof branch (macOS path SIMULATED with Linux lsof): empty path filled"
}

# ===========================================================================
# history: per-pane .last / history files, logger targeting, pane moves,
# pane-exited release
# ===========================================================================
# changed_lasts: .last files present, space-separated (state dir only).
lasts() { (cd "$(panes_dir)" 2> /dev/null && ls -- *.last 2> /dev/null | tr '\n' ' ' | sed 's/ $//'); }
pane_id() { tx display-message -p -t "$1" '#{pane_id}'; }

file_mode() { stat -c '%a' -- "$1" 2> /dev/null || stat -f '%Lp' -- "$1" 2> /dev/null; }

# Logger in a real pane shell: the command typed into an inactive pane of
# a session that is not the most recent one lands in that pane's own file.
test_logger_in_pane() {
    local sh="$1" id dir
    tmuxf_scenario "logger-${sh}" || return
    local cmd=""
    [[ "${sh}" == zsh ]] && cmd='exec zsh -i'
    tx new-session -d -s dev -x 200 -y 50 ${cmd:+"${cmd}"}
    tx new-window -d -t dev:1 ${cmd:+"${cmd}"}
    tx new-session -d -s ops ${cmd:+"${cmd}"}
    wait_until 10 tmuxf_prompt_ready dev:1 || { fail "${sh} logger: no prompt"; return; }
    wait_until 10 tmuxf_prompt_ready ops || { fail "${sh} logger: no prompt"; return; }
    rm -f "$(panes_dir)"/*.last
    tx send-keys -t dev:1 'echo FROM_INACTIVE' Enter
    wait_until 5 file_has "$(panes_dir)/dev:1.0.last" FROM_INACTIVE
    assert_eq "echo FROM_INACTIVE|dev:1.0.last" \
        "$(cat "$(panes_dir)/dev:1.0.last" 2> /dev/null)|$(lasts)" \
        "${sh} logger: inactive pane in an older session writes its own .last only"
    dir="$(panes_dir)"
    id=$(pane_id dev:1)
    assert_eq "700 600 600 600" \
        "$(file_mode "${dir}") $(file_mode "${dir}/dev:1.0.last") $(file_mode "${dir}/dev:1.0.${sh}_history") $(file_mode "${dir}/.owner.${id}")" \
        "${sh} recorder: panes dir 0700; .last, per-pane history, owner claim 0600"
}

# Logger called from a shell outside any pane, with $TMUX on the test
# server and a given TMUX_PANE: only a real pane ID may write.
test_logger_pane_ids() {
    local sh="$1" good bad
    tmuxf_scenario "logger-ids-${sh}" || return
    # No shells in the panes: nothing but the call under test writes.
    tx new-session -d -s dev 'exec sleep 600'
    tx new-window -d -t dev:1 'exec sleep 600'
    tx new-session -d -s ops 'exec sleep 600'
    good=$(pane_id dev:1)
    logger_call() {
        local pane_env=() script
        [[ "$1" == UNSET ]] || pane_env=(TMUX_PANE="$1")
        rm -rf "$(panes_dir)"
        if [[ "${sh}" == bash ]]; then
            script='HISTFILE=/dev/null; set -o history; history -s "echo LOGGED"; source "$1"; _tmux_log_last_cmd'
            tmuxf_run TMUX="${TS_SOCK},1,0" "${pane_env[@]}" bash --noprofile --norc -c "${script}" _ \
                "${TS_HOME}/bin/helper/tmux_last_cmd.bash"
        else
            script='HISTFILE=/dev/null; print -s -- "echo LOGGED"; precmd_functions=(); source "$1"; _tmux_log_last_cmd'
            tmuxf_run TMUX="${TS_SOCK},1,0" "${pane_env[@]}" zsh -f -i -c "${script}" _ \
                "${TS_HOME}/bin/helper/tmux_last_cmd.zsh" < /dev/null
        fi
    }
    logger_call "${good}"
    assert_eq "0|dev:1.0.last|echo LOGGED" "${RUN_STATUS}|$(lasts)|$(cat "$(panes_dir)/dev:1.0.last" 2> /dev/null)" \
        "${sh} logger: TMUX_PANE=${good} (real pane) writes that pane's .last (control)"
    for bad in UNSET "" %99 ops 3 "${good}x"; do
        logger_call "${bad}"
        assert_eq "0|" "${RUN_STATUS}|$(lasts)" "${sh} logger: TMUX_PANE=[${bad}] skipped, no .last written"
    done
}

# Pane moves between two prompts: the next command and the whole history
# follow the pane to its new position; the old position's files go.
test_pane_move() {
    local sh="$1" id dir cmd=""
    tmuxf_scenario "move-${sh}" || return
    [[ "${sh}" == zsh ]] && cmd='exec zsh -i'
    dir="$(panes_dir)"
    tx new-session -d -s m -x 200 -y 50 ${cmd:+"${cmd}"}
    tx new-window -d -t m:1 ${cmd:+"${cmd}"}
    wait_until 10 tmuxf_prompt_ready m:0 || { fail "${sh} move: no prompt"; return; }
    id=$(pane_id m:0)
    tx send-keys -t m:0 'echo BEFORE_MOVE' Enter
    wait_until 5 file_has "${dir}/m:0.0.${sh}_history" BEFORE_MOVE \
        || { fail "${sh} move: BEFORE_MOVE not in m:0.0 history"; return; }
    tx move-window -s m:0 -t m:5
    tx send-keys -t m:5 'echo AFTER_MOVE' Enter
    wait_until 5 file_has "${dir}/m:5.0.last" AFTER_MOVE
    assert_eq "echo AFTER_MOVE" "$(cat "${dir}/m:5.0.last" 2> /dev/null)" \
        "${sh} pane move: next command logged at the new position"
    if file_has "${dir}/m:5.0.${sh}_history" BEFORE_MOVE && file_has "${dir}/m:5.0.${sh}_history" AFTER_MOVE; then
        pass "${sh} pane move: history file follows the pane (old and new commands)"
    else
        fail "${sh} pane move: m:5.0.${sh}_history: [$(tr '\n' ';' < "${dir}/m:5.0.${sh}_history" 2> /dev/null)]"
    fi
    assert_eq "absent absent" \
        "$([[ -e "${dir}/m:0.0.${sh}_history" ]] && echo present || echo absent) $([[ -e "${dir}/m:0.0.last" ]] && echo present || echo absent)" \
        "${sh} pane move: old position's history and .last released"
    assert_eq "${dir}/m:5.0.${sh}_history" "$(cat "${dir}/.owner.${id}" 2> /dev/null)" \
        "${sh} pane move: owner claim points at the new file"
    assert_eq "600" "$(file_mode "${dir}/m:5.0.${sh}_history")" "${sh} pane move: new history file 0600"
}

# pane-exited hook (tmux.conf) -> tmux_pane_hist_release.bash.
test_pane_exit_releases() {
    local dir gone kept
    tmuxf_scenario pane-exit || return
    dir="$(panes_dir)"
    tx new-session -d -s x -x 200 -y 50
    tx split-window -d -t x:0
    wait_until 10 tmuxf_prompt_ready x:0.0 || { fail "pane exit: no prompt"; return; }
    wait_until 10 tmuxf_prompt_ready x:0.1 || { fail "pane exit: no prompt"; return; }
    kept=$(pane_id x:0.0) gone=$(pane_id x:0.1)
    tx send-keys -t x:0.0 'echo KEEP' Enter
    tx send-keys -t x:0.1 'echo GONE' Enter
    wait_until 5 file_has "${dir}/x:0.0.bash_history" KEEP
    wait_until 5 file_has "${dir}/x:0.1.bash_history" GONE \
        || { fail "pane exit: x:0.1 history not written"; return; }
    tx send-keys -t x:0.1 'exit' Enter
    if wait_until 5 file_absent "${dir}/.owner.${gone}"; then
        pass "pane exit: pane-exited hook ran the release script"
    else
        fail "pane exit: owner claim of the exited pane still there"
    fi
    wait_until 2 file_absent "${dir}/x:0.1.bash_history"
    assert_eq "absent absent" \
        "$([[ -e "${dir}/x:0.1.bash_history" ]] && echo present || echo absent) $([[ -e "${dir}/x:0.1.last" ]] && echo present || echo absent)" \
        "pane exit: exited pane's history and .last released"
    assert_eq "present present present" \
        "$([[ -e "${dir}/x:0.0.bash_history" ]] && echo present || echo absent) $([[ -e "${dir}/x:0.0.last" ]] && echo present || echo absent) $([[ -e "${dir}/.owner.${kept}" ]] && echo present || echo absent)" \
        "pane exit: the live pane's files kept"
    # kill-pane does not fire pane-exited: files stay for resurrect.
    tx kill-pane -t x:0.0
    tx new-session -d -s y
    tx run-shell 'true'
    assert_eq "present present" \
        "$([[ -e "${dir}/x:0.0.bash_history" ]] && echo present || echo absent) $([[ -e "${dir}/.owner.${kept}" ]] && echo present || echo absent)" \
        "pane killed (not exited): history kept for resurrect"
}

# Release ownership rules not reachable through the hook timing.
test_release_rules() {
    local rs live
    tmuxf_scenario release || return
    rs="$(panes_dir)"
    mkdir -p "${rs}"
    tx new-session -d -s d 'exec sleep 600'
    live=$(pane_id d)
    # Live pane claims d:0.1; %9999 (gone without pane-exited) claims d:1.0.
    printf 'h\n' > "${rs}/d:0.1.bash_history"
    printf '%s' "${rs}/d:0.1.bash_history" > "${rs}/.owner.${live}"
    printf 'h\n' > "${rs}/d:1.0.bash_history"
    printf '%s' "${rs}/d:1.0.bash_history" > "${rs}/.owner.%9999"
    tmuxf_run "${TS_HOME}/bin/tmux_pane_hist_release.bash" %1234 "${rs}/d:0.1.bash_history"
    assert_eq "0:present" "${RUN_STATUS}:$([[ -e "${rs}/d:0.1.bash_history" ]] && echo present || echo absent)" \
        "release: file still claimed by a live pane is kept"

    printf 'h\n' > "${rs}/d:2.0.bash_history"
    printf 'echo x\n' > "${rs}/d:2.0.last"
    tmuxf_run "${TS_HOME}/bin/tmux_pane_hist_release.bash" %1234 "${rs}/d:2.0.bash_history"
    assert_eq "0:absent absent" \
        "${RUN_STATUS}:$([[ -e "${rs}/d:2.0.bash_history" ]] && echo present || echo absent) $([[ -e "${rs}/d:2.0.last" ]] && echo present || echo absent)" \
        "release: unclaimed file and its .last removed"
    assert_eq "absent present" \
        "$([[ -e "${rs}/.owner.%9999" ]] && echo present || echo absent) $([[ -e "${rs}/.owner.${live}" ]] && echo present || echo absent)" \
        "release: stale claim of a killed pane dropped, live claim kept"

    printf 'x' > "${TS_ROOT}/outside.last"
    printf 'x' > "${TS_ROOT}/outside.bash_history"
    tmuxf_run "${TS_HOME}/bin/tmux_pane_hist_release.bash" %1234 "${TS_ROOT}/outside.bash_history"
    assert_eq "0:present present" \
        "${RUN_STATUS}:$([[ -e "${TS_ROOT}/outside.bash_history" ]] && echo present || echo absent) $([[ -e "${TS_ROOT}/outside.last" ]] && echo present || echo absent)" \
        "release: path outside the state dir is never removed"
}

# ===========================================================================
# config: rendered tmux.conf per OS, loaded into real tmux
# ===========================================================================
test_config_linux() {
    tmuxf_scenario config-linux || return
    tx new-session -d -s c
    assert_contains "$(tx list-keys -T copy-mode-vi Enter)" "xclip -i -sel clipboard" \
        "Linux render: copy goes to xclip"
    assert_not_contains "$(tx list-keys)" "pbcopy" "Linux render: no pbcopy"
    assert_eq linux_procfs "$(tx show -gv @resurrect-save-command-strategy)" \
        "Linux render: linux_procfs save strategy"
}

test_config_darwin() {
    tmuxf_scenario config-darwin || return
    tmuxf_render_conf darwin "${TS_HOME}/.config/tmux/tmux.conf" \
        || { fail "darwin render: chezmoi --override-data"; return; }
    tx new-session -d -s c
    assert_contains "$(tx list-keys -T copy-mode-vi Enter)" "pbcopy" \
        "darwin render (os SIMULATED via chezmoi --override-data): copy goes to pbcopy"
    assert_contains "$(tx show-hooks -g after-new-window)" "tmux_osc52_pbcopy.py" \
        "darwin render (simulated): OSC 52 pipe-pane hook on new windows"
    assert_eq "" "$(tx show -gqv @resurrect-save-command-strategy)" \
        "darwin render (simulated): default save strategy"
}

# ===========================================================================
# units: systemd unit and LaunchAgent as their managers would read them
# ===========================================================================
test_systemd_unit() {
    require_cmd "systemd-analyze verify tmux.service" systemd-analyze || return 0
    local root
    root="$(make_test_dir unit)"
    mkdir -p "${root}/home/bin" "${root}/units" "${root}/run"
    chmod 700 "${root}/run"
    cp "${BOOT}" "${root}/home/bin/tmux_boot.bash"
    chmod +x "${root}/home/bin/tmux_boot.bash"
    cp "${REPO_ROOT}/dot_config/systemd/user/tmux.service" "${root}/units/"
    run_capture env -i HOME="${root}/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="${root}/run" \
        systemd-analyze --user verify "${root}/units/tmux.service"
    assert_status 0 "${RUN_STATUS}" "tmux.service: systemd-analyze --user verify passes"
    assert_eq "" "${RUN_STDERR}" "tmux.service: no warnings"
}

test_launch_agent() {
    require_cmd "LaunchAgent plist" python3 chezmoi || return 0
    local root chezmoi_bin chezmoi_dir
    root="$(make_test_dir plist)"
    mkdir -p "${root}/home"
    chezmoi_bin="$(command -v chezmoi 2> /dev/null || echo "chezmoi")"
    chezmoi_dir="$(dirname "${chezmoi_bin}")"
    env -i HOME="${root}/home" PATH="${chezmoi_dir}:/usr/bin:/bin" "${chezmoi_bin}" --source "${REPO_ROOT}" execute-template \
        < "${REPO_ROOT}/Library/LaunchAgents/local.tmux.plist.tmpl" > "${root}/local.tmux.plist"
    run_capture python3 -I -c 'import plistlib, sys; p = plistlib.load(open(sys.argv[1], "rb")); print(p["ProgramArguments"][0], p["RunAtLoad"], p["KeepAlive"])' \
        "${root}/local.tmux.plist"
    assert_eq "0:${root}/home/bin/tmux_boot.bash True False" "${RUN_STATUS}:${RUN_STDOUT}" \
        "LaunchAgent (parsed, macOS untested): runs the boot script once at load, no KeepAlive restart"
    if [[ "$(uname -s)" == Darwin ]] && command -v plutil > /dev/null 2>&1; then
        run_capture plutil -lint "${root}/local.tmux.plist"
        assert_status 0 "${RUN_STATUS}" "LaunchAgent: plutil -lint"
    fi
}

# ===========================================================================
# native: real tpm / tmux-resurrect / tmux-continuum
# ===========================================================================
PLUGIN_SRC=""
PLUGIN_SKIP=""

# fetch_plugin <dir> <name> <sha>
fetch_plugin() {
    local dir="$1" name="$2" sha="$3" tmp="$1.tmp.$$"
    rm -rf "${tmp}"
    git init -q "${tmp}" \
        && timeout 120 git -C "${tmp}" fetch -q --depth 1 "https://github.com/tmux-plugins/${name}" "${sha}" \
        && git -C "${tmp}" -c advice.detachedHead=false checkout -q FETCH_HEAD \
        && rm -rf "${dir}" && mv "${tmp}" "${dir}"
    local status=$?
    rm -rf "${tmp}"
    return "${status}"
}

# Sets PLUGIN_SRC (dir with the three checkouts at their pins) or
# PLUGIN_SKIP (reason).
resolve_plugins() {
    local root="${F_TMUX_PLUGIN_ROOT:-${TMUX_TEST_PLUGIN_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/chezmoi-tests/tmux-plugins}}"
    local entry name sha have
    if ! command -v git > /dev/null 2>&1; then
        PLUGIN_SKIP="git not installed"
        return 1
    fi
    for entry in "${PLUGIN_PINS[@]}"; do
        name="${entry% *}" sha="${entry#* }"
        have=$(git -C "${root}/${name}" rev-parse --verify -q HEAD 2> /dev/null)
        [[ "${have}" == "${sha}" ]] && continue
        if [[ -n "${F_TMUX_PLUGIN_ROOT:-}" || "${TMUX_TEST_OFFLINE:-}" == 1 ]]; then
            PLUGIN_SKIP="${name} at ${root}/${name} is not at ${sha}${F_TMUX_PLUGIN_ROOT:+ (F_TMUX_PLUGIN_ROOT)}"
            return 1
        fi
        mkdir -p "${root}" && fetch_plugin "${root}/${name}" "${name}" "${sha}" || {
            PLUGIN_SKIP="could not fetch ${name}@${sha} into ${root} (offline?)"
            return 1
        }
    done
    PLUGIN_SRC="${root}"
}

NATIVE_PANES=()
NATIVE_BEFORE=""
native_inventory() {
    tx list-windows -a -F 'W #{session_name}:#{window_index} #{window_active} #{window_layout} #{window_name}'
    tx list-panes -a -F 'P #{session_name}:#{window_index}.#{pane_index} #{pane_active} #{pane_width}x#{pane_height} #{pane_current_path}'
}
# resurrect names snapshots by the second and deletes a new file that equals
# `last`; two saves in one second write the same file and delete `last`'s
# target. Each save therefore starts in a new second.
NATIVE_SAVED_AT=""
second_changed() { [[ "$(date +%s)" != "${NATIVE_SAVED_AT}" ]]; }
native_save() {
    wait_until 2 second_changed
    NATIVE_SAVED_AT=$(date +%s)
    tx run-shell "${TS_HOME}/.tmux/plugins/tmux-resurrect/scripts/save.sh"
}
native_cmd() { printf 'printf EXECUTED > %s/sentinel.%s' "${TS_ROOT}" "$1"; }
has_last() { [[ -s "$(panes_dir)/$1.last" ]]; }

# native_setup <name>: two sessions, a split window, distinct cwds; each
# pane runs a command that writes its own sentinel (so .last and history
# are real); two leaked placeholders; one resurrect save; server stopped.
native_setup() {
    local entry pane
    tmuxf_scenario "$1" plugins || return 1
    for entry in "${PLUGIN_PINS[@]}"; do
        cp -a "${PLUGIN_SRC}/${entry% *}" "${TS_HOME}/.tmux/plugins/" \
            || { fail "$1: copy plugin ${entry% *}"; return 1; }
    done
    mkdir -p "${TS_HOME}/project_alpha" "${TS_HOME}/project beta"
    # The setup server starts without the boot owner flag, so continuum
    # would arm its delayed background restore, which outlives the server
    # and hits the next one on the same socket path. Halted during setup
    # only: the boot runs with continuum armed.
    : > "${TS_HOME}/tmux_no_auto_restore"
    tx new-session -d -s f_dev -n editor -c "${TS_HOME}/project_alpha" || { fail "$1: start"; return 1; }
    tx new-window -d -t f_dev -n term -c "${TS_HOME}/project beta"
    tx split-window -d -h -t f_dev:term -c "${TS_HOME}/project beta"
    tx new-session -d -s f_ops -n monitor -c "${TS_HOME}"
    mapfile -t NATIVE_PANES < <(tx list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
    for pane in "${NATIVE_PANES[@]}"; do
        wait_until 15 tmuxf_prompt_ready "${pane}" || { fail "$1: no prompt in ${pane}"; return 1; }
        tx send-keys -t "${pane}" -l -- "$(native_cmd "${pane}")"
        tx send-keys -t "${pane}" Enter
        wait_until 10 has_last "${pane}" || { fail "$1: ${pane} .last not recorded"; return 1; }
    done
    NATIVE_BEFORE=$(native_inventory)
    tx new-session -d -s _main_boot_4242 -c "${TS_HOME}"
    tx new-session -d -s _tmux_boot_4343 -c "${TS_HOME}"
    native_save || { fail "$1: resurrect save.sh"; return 1; }
    rm -f "${TS_ROOT}"/sentinel.*
    tmuxf_stop || { fail "$1: could not verify and stop the test server"; return 1; }
    rm -f "${TS_HOME}/tmux_no_auto_restore"
}

test_native_save() {
    native_setup native-save || return
    local last="${TS_STATE}/tmux/resurrect/last"
    if [[ ! -e "${last}" ]]; then
        fail "native save: no snapshot under the synthetic XDG_STATE_HOME"
        return
    fi
    pass "native save: snapshot written under the synthetic XDG_STATE_HOME"
    assert_file_contains "${last}" "pane${T}f_dev${T}1${T}" "native save: f_dev panes saved"
    assert_eq "" "$(grep -E "^(pane|window)${T}_(main|tmux)_boot_" "${last}")" \
        "native save: leaked placeholder sessions not persisted (save filter)"
}

test_native_boot_restore() {
    local pane cmd dir
    native_setup native-boot || return
    dir="$(panes_dir)"
    run_boot
    assert_status 0 "${RUN_STATUS}" "native boot: exit 0"
    for pane in "${NATIVE_PANES[@]}"; do
        cmd=$(native_cmd "${pane}")
        if wait_until 10 pane_line_is "${pane}" "F\$ ${cmd}"; then
            pass "native boot: ${pane} prefilled with its last command"
        else
            fail "native boot: ${pane} shows [$(tmuxf_last_line "${pane}")]"
        fi
        assert_eq absent "$([[ -e "${TS_ROOT}/sentinel.${pane}" ]] && echo present || echo absent)" \
            "native boot: ${pane} prefill not executed"
        assert_file_contains "${dir}/${pane}.bash_history" "${cmd}" "native boot: ${pane} history kept"
    done
    assert_eq "$(tmuxf_normalize_inventory <<< "${NATIVE_BEFORE}")" "$(native_inventory | tmuxf_normalize_inventory)" \
        "native boot: sessions/windows/layout/geometry/active/cwd restored"
    assert_eq "f_dev f_ops" "$(tmuxf_sessions)" "native boot: no bootstrap or placeholder session left"
    assert_boot_owned_restore "native boot"
    tx send-keys -t "${NATIVE_PANES[0]}" Enter
    if wait_until 5 file_exists "${TS_ROOT}/sentinel.${NATIVE_PANES[0]}"; then
        pass "native boot: prefilled command runs only after explicit Enter"
    else
        fail "native boot: Enter did not run the prefilled command"
    fi
}

test_native_repeated_boots() {
    local cycle
    native_setup native-cycles || return
    run_boot
    for cycle in boot main boot main; do
        native_save
        tmuxf_stop || { fail "native cycles: could not verify and stop the test server"; return; }
        if [[ "${cycle}" == boot ]]; then run_boot; else run_main_session; fi
        assert_eq "f_dev f_ops" "$(tmuxf_sessions)" \
            "native repeated boot (${cycle}): same sessions, no placeholder left"
    done
}

# A pane saved with an empty path (what macOS saved when tmux could not
# read the foreground process) is restored in $HOME, not the boot cwd /.
test_native_empty_path() {
    local snap
    native_setup native-emptypath || return
    snap=$(readlink -f "${TS_STATE}/tmux/resurrect/last")
    awk -F '\t' -v OFS='\t' '$1 == "pane" && $2 == "f_dev" && $3 == "1" && $6 == "1" { $8 = ":" } { print }' \
        "${snap}" > "${snap}.new" && mv "${snap}.new" "${snap}"
    run_boot
    assert_eq "${TS_HOME}" "$(tx display-message -p -t f_dev:1.1 '#{pane_current_path}')" \
        "native: pane saved with an empty path restored in \$HOME, not /"
    assert_eq "${TS_HOME}/project beta" "$(tx display-message -p -t f_dev:1.0 '#{pane_current_path}')" \
        "native: neighbouring pane keeps its saved path"
}

test_native_no_snapshot() {
    native_setup native-nosnap || return
    rm -rf "${TS_STATE}/tmux/resurrect"
    run_boot
    assert_eq "0:main" "${RUN_STATUS}:$(tmuxf_sessions)" \
        "native boot, no snapshot: server kept alive in one session named main"
}

# ===========================================================================
# bash32: scripts that claim macOS /bin/bash 3.2 compatibility
# ===========================================================================
find_bash32() {
    local b
    for b in ${BASH32:-} bash3.2 bash-3.2 /bin/bash; do
        command -v "${b}" > /dev/null 2>&1 || continue
        [[ "$("${b}" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2> /dev/null)" == 3.2 ]] \
            && { command -v "${b}"; return 0; }
    done
    return 1
}

# ===========================================================================
TESTS_START=${SECONDS}
tests_init_tmp tmuxp
if require_cmd "real tmux layer" tmux chezmoi; then
    if section_enabled prefill; then
        echo "== prefill =="
        test_prefill_cases
        test_prefill_closed_pane_race
        test_prefill_no_state_dir
    fi
    if section_enabled boot; then
        echo "== boot =="
        test_boot_no_restore_script
        test_boot_restore_success
        test_boot_restore_without_hook
        test_boot_restore_empty
        test_boot_restore_placeholder_only
        test_boot_existing_server
        test_boot_tmux_missing
    fi
    if section_enabled main; then
        echo "== tmux_main_session =="
        test_main_restore
        test_main_restore_without_hook
        test_main_restore_empty
        test_main_default_layout
        test_main_existing_session
        test_kill_session_alias
    fi
    if section_enabled cleanup; then
        echo "== bootstrap cleanup =="
        test_cleanup
    fi
    if section_enabled filter; then
        echo "== save filter =="
        test_filter
    fi
    if section_enabled history; then
        echo "== per-pane history =="
        test_logger_in_pane bash
        test_logger_pane_ids bash
        test_pane_move bash
        if require_cmd "zsh pane logger/history" zsh; then
            test_logger_in_pane zsh
            test_logger_pane_ids zsh
            test_pane_move zsh
        fi
        test_pane_exit_releases
        test_release_rules
    fi
    if section_enabled config; then
        echo "== rendered tmux.conf =="
        test_config_linux
        test_config_darwin
    fi
    if section_enabled native; then
        echo "== native plugins =="
        if resolve_plugins; then
            test_native_save
            test_native_boot_restore
            test_native_repeated_boots
            test_native_empty_path
            test_native_no_snapshot
        else
            skip "native tpm/resurrect/continuum: ${PLUGIN_SKIP}"
        fi
    fi
    if section_enabled bash32; then
        echo "== bash 3.2 =="
        if BASH32_BIN=$(find_bash32); then
            test_cleanup "${BASH32_BIN}" " (bash 3.2)"
            test_filter "${BASH32_BIN}" " (bash 3.2)"
        else
            skip "bash 3.2 compatibility of cleanup/save filter: no bash 3.2 found (set BASH32=<path>)"
        fi
    fi
fi
if section_enabled units; then
    echo "== service units =="
    test_systemd_unit
    test_launch_agent
fi
printf 'runtime: %ds\n' "$((SECONDS - TESTS_START))"
tests_finish
