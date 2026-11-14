#!/usr/bin/env bash
# Interactive-shell sandbox for the shell helper tests. Source it after
# tests/lib/common.bash and tests_init_tmp; do not run it.
#
# Every shell runs against a synthetic HOME built from tracked files
# (deployed under their chezmoi target names), with `env -i` and a PATH whose
# first entry is a directory of fakes for every external command the
# exercised code reaches. No real startup file, ~/bin/.env, job setup file,
# client, mount, service or tmux server is touched.
#
# API
#   make_fakebin                     create FAKEBIN (fakes on PATH) and
#                                    FAKE_GIT_DIR (a fake git, opt-in on PATH)
#   new_home <prefix> [module...]    fresh sandbox HOME (make_test_dir +
#                                    deploy_tree); prints it; FAILs and
#                                    returns 1 if a tracked source is missing.
#                                    Listed modules (bin/helper/<m>.bash) are
#                                    left out, as chezmoi does on macOS.
#   fake_set <home> <key> <attr> <value>
#                                    configure a fake in that HOME. <key> is a
#                                    command name (any call) or name@arg1
#                                    (calls whose first argument is arg1; it
#                                    wins over the plain name). <attr>:
#                                      status  exit code
#                                      stdout  replaces the built-in output
#                                              (value + newline; "" = none)
#                                      stderr  written to stderr
#   run_bash <home> <script> [VAR=value...]
#   run_zsh  <home> <script> [VAR=value...]
#                                    real interactive startup (~/.bashrc or
#                                    ~/.zshrc) then <script>, cwd = HOME,
#                                    stdin /dev/null; sets RUN_STATUS,
#                                    RUN_STDOUT, RUN_STDERR (run_capture)
#   out_value <key> <home>           value of the first "key=value" line of
#                                    RUN_STDOUT, HOME shown as <HOME>; returns
#                                    1 if the key is absent
#   home_normalise <home>            stdin -> stdout with HOME as <HOME>
#   startup_noise_filtered           RUN_STDERR without the two job-control
#                                    lines bash -i prints without a terminal
#
# Fakes log one line per call to $FAKE_LOG: `name [arg1] [arg2] ...`.
# Concurrent pipeline stages may log in either order, so tests compare
# sorted logs or check single lines, never cross-process order.

: "${TEST_TMP_ROOT:?source tests/lib/common.bash and call tests_init_tmp first}"

FAKEBIN="${TEST_TMP_ROOT}/fakebin"
FAKE_GIT_DIR="${TEST_TMP_ROOT}/fakegit"
SHELL_TIMEOUT_SECONDS=30
TMUX_ID_INITIAL="main:1.0"
FIXTURE_SOURCE_ROOT="${REPO_ROOT:?REPO_ROOT must be set}"
# Fakes on PATH. git is not among them: the bash prompt and zsh vcs_info
# call git, so a test opts in with PATH="${FAKE_GIT_DIR}:${PATH}".
FAKE_COMMANDS=(xhost tmux gio fscrypt i3-msg i3-save-tree jq pactl dunstify
    dunstctl notify-send setxkbmap xset xinput pkill kbdd feh systemctl
    journalctl systemd-escape light rofi wmctrl xdotool xclip firefox
    firejail rclone ssh rsync scp pyenv ssh-agent docker i3lock i3-nagbar
    polybar launchctl yay pacman paccache npm node claude codex apt sudo adb
    ffmpeg gpg watch zenity unzip tar 7z xev xprop)

make_fakebin() {
    mkdir -p "${FAKEBIN}" "${FAKE_GIT_DIR}"
    cat > "${FAKEBIN}/fake-cmd" <<'FAKE'
#!/bin/bash
# Stand-in for an external command; never touches the host.
name="${0##*/}"
line="${name}"
for arg in "$@"; do line+=" [${arg}]"; done
# One small O_APPEND write per line: concurrent stages never interleave.
printf '%s\n' "${line}" >> "${FAKE_LOG:-/dev/null}"

# config <attr>: path of the most specific configured file, if any.
config() {
    local dir="${FAKE_CONFIG_DIR:-/nonexistent}" f
    for f in "${dir}/${name}@${first}.$1" "${dir}/${name}.$1"; do
        [[ -n "${first}" || "${f}" != *"@."* ]] || continue
        [[ -f "${f}" ]] && { printf '%s' "${f}"; return 0; }
    done
    return 1
}
first="${1-}"
[[ "${first}" == */* ]] && first=""

# Built-in output and status for commands whose callers parse output.
default() {
    case "${name}" in
        tmux)
            # display-message -p ... <format>: expands #{pane_id} to
            # $TMUX_PANE and #S:#I.#P to the id file; fails if it is empty.
            if [[ "${1:-}" == display-message ]]; then
                [[ -s "${FAKE_TMUX_ID_FILE:-}" ]] || return 1
                local format="${!#}" pane_pos
                pane_pos="$(< "${FAKE_TMUX_ID_FILE}")"
                format="${format//'#{pane_id}'/${TMUX_PANE:-}}"
                printf '%s\n' "${format//'#S:#I.#P'/${pane_pos}}"
            fi
            ;;
        gio)
            case "${1:-} ${2:-}" in
                "mount -li") echo "Volume(0): Phone"; echo "  activation_root=mtp://fakephone/" ;;
            esac
            [[ "${1:-}" == info ]] && echo "local path: ${FAKE_GIO_MOUNT:?}"
            ;;
        i3-msg) [[ "${1:-} ${2:-}" == "-t get_workspaces" ]] && echo '[{"num":1}]' ;;
        jq) cat > /dev/null; echo 1 ;;
        # Like the real one, `gpg --verify` with no file reads stdin to EOF;
        # exiting early would SIGPIPE the producer (flaky status 141).
        gpg) [[ "${1:-}" == --verify && $# == 1 ]] && cat > /dev/null ;;
        i3-save-tree) printf '// "class": "^Fixture$",\n{ "nodes": [] }\n' ;;
        pactl)
            case "${1:-}" in
                get-sink-volume) echo "Volume: front-left: 32768 / 50% / -18.06 dB" ;;
                get-sink-mute) echo "Mute: no" ;;
            esac
            ;;
        systemd-escape) printf '%s\n' "$1" ;;
        rofi) sed 's/^/rofi-menu: /' >> "${FAKE_LOG:-/dev/null}" ;;
    esac
    return 0
}

if out="$(config stdout)"; then
    cat -- "${out}"
    rc=0
else
    default "$@"
    rc=$?
fi
if err="$(config stderr)"; then cat -- "${err}" >&2; fi
if st="$(config status)"; then exit "$(< "${st}")"; fi
exit "${rc}"
FAKE
    chmod +x "${FAKEBIN}/fake-cmd"
    local cmd
    for cmd in "${FAKE_COMMANDS[@]}"; do
        ln -sf fake-cmd "${FAKEBIN}/${cmd}"
    done
    ln -sf "${FAKEBIN}/fake-cmd" "${FAKE_GIT_DIR}/git"
}

# _fixture_install <src> <dst> [mode]: copy a tracked file; a missing source is a
# fixture error, never a silently thinner sandbox.
_fixture_install() {
    if [[ ! -f "$1" ]]; then
        printf 'shell_fixture: tracked source file missing: %s\n' "$1" >&2
        return 1
    fi
    cp -- "$1" "$2" && { [[ -z "${3:-}" ]] || chmod "$3" "$2"; }
}

# deploy_tree <source_root> <home> [skipped helper module...]
deploy_tree() {
    local src="$1" home="$2" skip f mod
    shift 2
    mkdir -p "${home}/bin/helper" "${home}/.bash_completion.d" "${home}/.ssh" \
        "${home}/job" "${home}/mnt/phone" "${home}/.local/state" "${home}/fake.d" \
        "${home}/.mozilla/firefox/fixtureprofile" || return 1
    _fixture_install "${src}/dot_bashrc" "${home}/.bashrc" || return 1
    _fixture_install "${src}/dot_zshrc" "${home}/.zshrc" || return 1
    for f in helper.bash transfer.bash; do
        _fixture_install "${src}/dot_bash_completion.d/${f}" "${home}/.bash_completion.d/${f}" || return 1
    done
    _fixture_install "${src}/bin/executable_helper.bash" "${home}/bin/helper.bash" +x || return 1
    # Interactive SSHFS manager that hh_sshfsctl runs.
    _fixture_install "${src}/bin/executable_sshfs.bash" "${home}/bin/sshfs.bash" +x || return 1
    for f in common shell git storage transfer utils i3 system backup firefox \
        tmux tmux_commands tmux_last_cmd; do
        for skip in "$@"; do
            [[ "${f}" == "${skip}" ]] && continue 2
        done
        _fixture_install "${src}/bin/helper/${f}.bash" "${home}/bin/helper/${f}.bash" || return 1
    done
    for f in aliases.shrc bash_exec.zsh tmux_last_cmd.zsh; do
        _fixture_install "${src}/bin/helper/${f}" "${home}/bin/helper/${f}" || return 1
    done
    # system.bash sources ~/.xsessionrc; chezmoi skips both on macOS.
    if [[ " $* " != *" system "* ]]; then
        _fixture_install "${src}/dot_xsessionrc" "${home}/.xsessionrc" || return 1
    fi

    # Synthetic runtime inputs (the real ~/bin/.env and job setup are never read).
    printf 'export JOB_SETUP_FILE="${HOME}/job/add_exports.bash"\n' > "${home}/bin/.env"
    printf 'export FIXTURE_JOB_SENTINEL=loaded\n' > "${home}/job/add_exports.bash"
    ln -s "${FAKEBIN}/fake-cmd" "${home}/bin/tmux_pane_hist_release.bash"
    printf 'Host alpha\n    User bob\nHost beta\nHost *.wild\n' > "${home}/.ssh/config"
    printf '[Profile0]\nName=fixture\nPath=fixtureprofile\nDefault=1\n' \
        > "${home}/.mozilla/firefox/profiles.ini"
    # Third-party completion fixture: underscore vendor symbols must survive.
    printf '_vendor_fixture_complete() { :; }\ncomplete -F _vendor_fixture_complete vendor_cmd\n' \
        > "${home}/.bash_completion.d/zz_vendor_fixture"
    printf '%s\n' "${TMUX_ID_INITIAL}" > "${home}/tmux_id"
}

new_home() {
    local prefix="$1" home
    shift
    home="$(make_test_dir "${prefix}")" || { fail "${prefix}: make_test_dir"; return 1; }
    if ! deploy_tree "${FIXTURE_SOURCE_ROOT}" "${home}" "$@" 2> "${home}.deploy.err"; then
        fail "${prefix}: sandbox HOME not deployed: $(cat "${home}.deploy.err")"
        return 1
    fi
    printf '%s\n' "${home}"
}

fake_set() {
    local home="$1" key="$2" attr="$3" value="$4"
    case "${attr}" in
        status) printf '%s\n' "${value}" > "${home}/fake.d/${key}.status" ;;
        stdout|stderr)
            if [[ -z "${value}" ]]; then
                : > "${home}/fake.d/${key}.${attr}"
            else
                printf '%s\n' "${value}" > "${home}/fake.d/${key}.${attr}"
            fi
            ;;
        *) printf 'fake_set: unknown attribute %s\n' "${attr}" >&2; return 1 ;;
    esac
}

# Environment shared by every sandboxed shell: env -i plus these.
sandbox_env() {
    local home="$1"
    SANDBOX_ENV=(HOME="${home}" USER=fixtureuser HOSTNAME=fixturehost TERM=xterm
        PATH="${FAKEBIN}:/usr/bin:/bin" XDG_STATE_HOME="${home}/.local/state"
        ZDOTDIR="${home}" FAKE_LOG="${home}/fake.log" FAKE_CONFIG_DIR="${home}/fake.d"
        FAKE_TMUX_ID_FILE="${home}/tmux_id" FAKE_GIO_MOUNT="${home}/mnt/phone")
}

_sandbox_exec() {
    local shell="$1" home="$2" script="$3"
    shift 3
    local -a cmd=(bash --noprofile -i -c "${script}")
    [[ "${shell}" == zsh ]] && cmd=(zsh -i -c "${script}")
    sandbox_env "${home}"
    cd "${home}" || return 125
    env -i "${SANDBOX_ENV[@]}" "$@" timeout "${SHELL_TIMEOUT_SECONDS}" "${cmd[@]}" < /dev/null
}

run_bash() { run_capture _sandbox_exec bash "$@"; }
run_zsh() { run_capture _sandbox_exec zsh "$@"; }

out_value() {
    local key="$1" home="$2" line
    while IFS= read -r line; do
        if [[ "${line}" == "${key}="* ]]; then
            line="${line#"${key}="}"
            [[ -n "${home}" ]] && line="${line//"${home}"/<HOME>}"
            printf '%s\n' "${line}"
            return 0
        fi
    done <<< "${RUN_STDOUT}"
    return 1
}

home_normalise() {
    local home="$1" line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${home}" ]] && line="${line//"${home}"/<HOME>}"
        printf '%s\n' "${line}"
    done
}

startup_noise_filtered() {
    local line
    while IFS= read -r line; do
        case "${line}" in
            "bash: cannot set terminal process group ("*"): Inappropriate ioctl for device") ;;
            "bash: no job control in this shell") ;;
            *"not interactive and can't open terminal"*) ;;
            *) printf '%s\n' "${line}" ;;
        esac
    done <<< "${RUN_STDERR}"
}
