#!/usr/bin/env bash
# Real-tmux fixture for tests/test_tmux_*.bash. Source it after
# tests/lib/common.bash and tests_init_tmp; do not run it.
#
# Every tmux server a test starts lives on a private socket under the
# scenario's own TMUX_TMPDIR, and every tmux call (the test's own, the
# product scripts', the pane shells', the hooks' and plugins') goes through
# a guard that refuses any socket outside the scenario root. The host's
# default socket is never listed, probed, attached or killed.
#
# API
#   tmuxf_guard_write <dir>        write the guard as <dir>/tmux
#   tmuxf_socket_dir <tmux tmpdir> create <tmpdir>/tmux-UID (0700, ours, not a
#                                  link) and print the socket path inside it
#   tmuxf_scenario <name> [plugins] fresh scenario: sets TS_ROOT TS_HOME
#                                  TS_STATE TS_SOCK TS_ENV (env -i array); the
#                                  rendered Linux tmux.conf, the product
#                                  scripts in ~/bin, a no-op tpm stub unless
#                                  <plugins> is "plugins"; returns 1 (counted
#                                  FAIL) when the fixture cannot be built
#   tx <tmux args...>              guarded real tmux on TS_SOCK
#   tmuxf_run <cmd...>             run_capture cmd inside TS_ENV
#   tmuxf_stop                     stop TS_SOCK's server after it proves it
#                                  is the scenario's own (0 stopped/none)
#   tmuxf_last_line <pane>         last non-empty line of a pane
#   tmuxf_prompt_ready <pane>      the pane shows the fixture prompt `F$`
#   tmuxf_sessions                 session names, one line, sorted, spaces
#   tmuxf_render_conf <os> <out>   render tmux.conf.tmpl with chezmoi for the
#                                  scenario HOME (os: linux or darwin)

TMUXF_REAL="$(command -v tmux 2>/dev/null || true)"
TMUXF_UID="$(id -u)"
TMUXF_DENY_STATUS=97
# tmux global options that take a value (getopt "2c:CDdf:lL:NqS:T:uUvV").
TMUXF_VALUE_FLAGS="cfLST"
TMUXF_PROMPT='F$'

# The guard works out the socket the real tmux would use, the way tmux does:
# the last -S wins, else the last -L label under ${TMUX_TMPDIR:-/tmp}/tmux-UID,
# else $TMUX, else the "default" label. Global options are parsed with tmux's
# getopt value flags, so clusters (-uS path, -Spath) and options before -S/-L
# count; arguments after the command name do not. A socket outside F_ROOT is
# refused (exit 97, logged to F_ROOT/denied.log). The real tmux runs with the
# guard first on PATH, so the server and everything it spawns resolve `tmux`
# to the guard as well.
tmuxf_guard_write() {
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
        [[ "${TMUXF_VALUE_FLAGS}" == *"\${flag}"* ]] || continue
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
root=\$(realpath -m -- "\${F_ROOT:?}")
if [[ "\${root}" == / || "\${sock}" != "\${root}/"* ]]; then
    printf '%s %s\n' "\${sock}" "\$*" >> "\${F_ROOT}/denied.log"
    echo "tmux-guard: refused tmux socket outside the test root" >&2
    exit ${TMUXF_DENY_STATUS}
fi
printf '%s\n' "\$*" >> "\${F_ROOT}/calls.log"
export PATH="\${0%/*}:\${PATH}"
exec "\${F_REAL_TMUX:?}" "\$@"
GUARD
    chmod +x "$1/tmux"
}

tmuxf_socket_dir() {
    local dir="$1/tmux-${TMUXF_UID}"
    mkdir -m 700 -- "$1" 2> /dev/null
    mkdir -m 700 -- "${dir}" 2> /dev/null
    [[ -d "${dir}" && ! -L "${dir}" && -O "${dir}" ]] || return 1
    [[ "$(stat -c '%a' -- "${dir}" 2> /dev/null || stat -f '%Lp' -- "${dir}")" == 700 ]] || return 1
    printf '%s/default\n' "${dir}"
}

tmuxf_render_conf() {
    local os="$1" out="$2" data=()
    local chezmoi_bin chezmoi_dir
    chezmoi_bin="$(command -v chezmoi 2> /dev/null || echo "chezmoi")"
    chezmoi_dir="$(dirname "${chezmoi_bin}")"
    [[ "${os}" == darwin ]] && data=(--override-data '{"chezmoi":{"os":"darwin"}}')
    env -i HOME="${TS_HOME}" PATH="${chezmoi_dir}:/usr/bin:/bin" XDG_STATE_HOME="${TS_STATE}" \
        "${chezmoi_bin}" --source "${REPO_ROOT}" execute-template "${data[@]}" \
        < "${REPO_ROOT}/dot_config/tmux/tmux.conf.tmpl" > "${out}"
}

# Product scripts as chezmoi deploys them (name without executable_, +x).
_tmuxf_install_bin() {
    local f name
    mkdir -p "${TS_HOME}/bin/helper"
    for f in "${REPO_ROOT}"/bin/executable_tmux_*.bash; do
        name="${f##*/executable_}"
        cp "${f}" "${TS_HOME}/bin/${name}" && chmod +x "${TS_HOME}/bin/${name}"
    done
    cp "${REPO_ROOT}"/bin/helper/tmux*.bash "${REPO_ROOT}"/bin/helper/tmux*.zsh \
        "${TS_HOME}/bin/helper/"
}

tmuxf_scenario() {
    local name="$1" plugins="${2:-}"
    TS_ROOT="$(make_test_dir "${name}")" || { fail "${name}: fixture: make_test_dir"; return 1; }
    # Symlink-free, as tmux reports socket paths (it resolves TMUX_TMPDIR).
    TS_ROOT="$(cd "${TS_ROOT}" && pwd -P)"
    TS_HOME="${TS_ROOT}/home"
    TS_STATE="${TS_HOME}/.local/state"
    mkdir -p "${TS_HOME}/.config/tmux" "${TS_HOME}/.tmux/plugins" "${TS_STATE}"
    TS_SOCK="$(tmuxf_socket_dir "${TS_ROOT}/t")" || { fail "${name}: fixture: socket dir"; return 1; }
    tmuxf_guard_write "${TS_ROOT}/guardbin"
    _tmuxf_install_bin
    tmuxf_render_conf linux "${TS_HOME}/.config/tmux/tmux.conf" \
        || { fail "${name}: fixture: chezmoi execute-template tmux.conf.tmpl"; return 1; }
    if [[ "${plugins}" != plugins ]]; then
        # The config's last line runs tpm; a no-op stands in for it.
        mkdir -p "${TS_HOME}/.tmux/plugins/tpm"
        printf '#!/bin/sh\nexit 0\n' > "${TS_HOME}/.tmux/plugins/tpm/tpm"
        chmod +x "${TS_HOME}/.tmux/plugins/tpm/tpm"
    fi
    # Pane shells: the real recorder module and a fixed prompt; umask 022
    # so file modes come from the module.
    cat > "${TS_HOME}/.bashrc" <<'RC'
umask 022
HISTFILE="${HOME}/.bash_history"
PS1='F$ '
. "${HOME}/bin/helper/tmux_last_cmd.bash"
RC
    printf '. "${HOME}/.bashrc"\n' > "${TS_HOME}/.bash_profile"
    # zsh panes (ZDOTDIR): dot_zshrc's order, precmd_functions set before
    # the module is sourced.
    mkdir -p "${TS_HOME}/.zdot"
    printf 'skip_global_compinit=1\n' > "${TS_HOME}/.zdot/.zshenv"
    cat > "${TS_HOME}/.zdot/.zshrc" <<'RC'
umask 022
HISTFILE="${HOME}/.zsh_history"
SAVEHIST=100 HISTSIZE=100
PROMPT='F$ '
precmd_functions=()
. "${HOME}/bin/helper/tmux_last_cmd.zsh"
RC
    TS_ENV=(HOME="${TS_HOME}" XDG_STATE_HOME="${TS_STATE}" XDG_CONFIG_HOME="${TS_HOME}/.config"
        TMUX_TMPDIR="${TS_ROOT}/t" PATH="${TS_ROOT}/guardbin:/usr/bin:/bin" SHELL=/bin/bash
        ZDOTDIR="${TS_HOME}/.zdot" skip_global_compinit=1 TERM=xterm-256color LANG=C.UTF-8
        F_ROOT="${TS_ROOT}" F_REAL_TMUX="${TMUXF_REAL}"
        GIT_ALLOW_PROTOCOL=file GIT_CONFIG_NOSYSTEM=1
        # The boot script resets PATH; its `tmux` still reaches the guard.
        "BASH_FUNC_tmux%%=() { \"\${F_ROOT}/guardbin/tmux\" \"\$@\"; }")
    add_cleanup "TS_ROOT='${TS_ROOT}' TS_SOCK='${TS_SOCK}' F_ROOT='${TS_ROOT}' tmuxf_stop_at_exit"
}

tx() {
    env -i "${TS_ENV[@]}" "${TS_ROOT}/guardbin/tmux" -S "${TS_SOCK}" "$@"
}

tmuxf_run() { run_capture env -i "${TS_ENV[@]}" "$@"; }

_tmuxf_gone() { ! kill -0 "$1" 2> /dev/null; }

# Status 0: stopped or no server answers; 1: refused (identity unproven).
tmuxf_stop() {
    local reported pid
    [[ -n "${TS_SOCK}" && "${TS_SOCK}" == "${TS_ROOT}/"* ]] || return 1
    reported=$(tx display-message -p '#{pid} #{socket_path}' 2> /dev/null) || return 0
    pid="${reported%% *}"
    [[ "${pid}" =~ ^[0-9]+$ && "${reported#* }" == "${TS_SOCK}" ]] || return 1
    [[ "$(cat "/proc/${pid}/comm" 2> /dev/null || ps -o comm= -p "${pid}" 2> /dev/null)" == *tmux* ]] || return 1
    tx kill-server 2> /dev/null
    wait_until 5 _tmuxf_gone "${pid}"
}

# Exit-trap form: runs with only TS_ROOT/TS_SOCK of the scenario restored.
tmuxf_stop_at_exit() {
    local TS_ENV=(F_ROOT="${TS_ROOT}" F_REAL_TMUX="${TMUXF_REAL}" PATH=/usr/bin:/bin)
    [[ -S "${TS_SOCK}" ]] || return 0
    tmuxf_stop || printf 'FAIL: cleanup: tmux server on %s not verified/stopped\n' "${TS_SOCK}"
}

tmuxf_last_line() {
    tx capture-pane -p -J -t "$1" 2> /dev/null | sed 's/[[:space:]]*$//; /^$/d' | tail -n 1
}

tmuxf_prompt_ready() { [[ "$(tmuxf_last_line "$1")" == "${TMUXF_PROMPT}" ]]; }

tmuxf_sessions() {
    tx list-sessions -F '#{session_name}' 2> /dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

# tmuxf_run_in <dir> <cmd...>: run_capture cmd inside TS_ENV with cwd <dir>
# (launchd starts agents in `/`), under a timeout.
tmuxf_run_in() {
    local dir="$1"
    shift
    run_capture bash -c 'cd "$1" && shift && exec "$@"' _ "${dir}" \
        timeout 60 env -i "${TS_ENV[@]}" "$@"
}

# tmuxf_normalize_inventory: inventory lines ("W <win> <active> <layout>
# <name>" / "P ...") with only the ephemeral parts of each window_layout
# replaced: tmux allocates fresh %N pane IDs on restore. Legacy layouts
# ("csum,WxH,X,Y{...}") lose the checksum (it covers the IDs) and each
# leaf's trailing ID; JSON v2 layouts (tmux 3.8) only the "I":"%N" values.
tmuxf_normalize_inventory() {
    sed -E '/^W [^ ]+ [01] \{[[:space:]]*"V"[[:space:]]*:/{
        s/("I"[[:space:]]*:[[:space:]]*)"%[0-9]+"/\1"ID"/g
        b
    }
    /^W /{
        s/^(W [^ ]+ [01] )[0-9a-f]{4},/\1/
        s/([0-9]+x[0-9]+,[0-9]+,[0-9]+),[0-9]+/\1,ID/g
    }'
}
