#!/usr/bin/env bash
# Self-test of tests/lib/tmux_fixture.bash: the socket guard every test tmux
# call goes through, the private socket directory, the verified server stop
# and the layout normaliser the native restore check relies on. The guard
# runs against a fake "real tmux" (no server is started here).
#
# Usage: bash tests/test_tmux_harness.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"
# shellcheck source=tests/lib/tmux_fixture.bash
source "${REPO_ROOT}/tests/lib/tmux_fixture.bash"

tests_init_tmp tmuxh
ROOT="$(cd "${TEST_TMP_ROOT}" && pwd -P)"

# --- guard -------------------------------------------------------------------
G_ROOT="${ROOT}/g"
G_IN="${G_ROOT}/t/sock"
G_OUT="${ROOT}/outside/sock"
tmuxf_guard_write "${G_ROOT}/guardbin"
printf '#!/bin/bash\nprintf "RAN %%s\\n" "${PATH}"\n' > "${G_ROOT}/real-tmux"
chmod +x "${G_ROOT}/real-tmux"

# guard_case <allow|deny> <label> [VAR=value...] -- <tmux args...>
guard_case() {
    local expect="$1" label="$2" vars=()
    shift 2
    while [[ "$1" != -- ]]; do vars+=("$1"); shift; done
    shift
    run_capture env -i PATH=/usr/bin:/bin F_ROOT="${G_ROOT}" F_REAL_TMUX="${G_ROOT}/real-tmux" \
        "${vars[@]}" "${G_ROOT}/guardbin/tmux" "$@"
    if [[ "${expect}" == allow ]]; then
        assert_eq "0:RAN ${G_ROOT}/guardbin:/usr/bin:/bin" "${RUN_STATUS}:${RUN_STDOUT}" \
            "guard allows ${label} (real tmux runs with the guard first on PATH)"
    else
        assert_eq "${TMUXF_DENY_STATUS}:" "${RUN_STATUS}:${RUN_STDOUT}" "guard refuses ${label}"
    fi
}
# With G_TMP the default socket would be allowed, so only the parsed -S refuses.
G_TMP="TMUX_TMPDIR=${G_ROOT}/t"
guard_case allow "-S inside the root" -- -S "${G_IN}" list-sessions
guard_case deny "-S outside the root" "${G_TMP}" -- -S "${G_OUT}" list-sessions
guard_case deny "clustered -uS outside" "${G_TMP}" -- -uS "${G_OUT}" list-sessions
guard_case deny "last -S outside (inside given first)" "${G_TMP}" -- -S "${G_IN}" -S "${G_OUT}" list-sessions
guard_case deny "-S path leaving the root through .." "${G_TMP}" -- -S "${G_ROOT}/../outside/sock" list-sessions
guard_case deny "\$TMUX outside without socket options" TMUX="${G_OUT},1,0" "${G_TMP}" -- list-sessions
guard_case deny "the default socket without TMUX_TMPDIR" -- list-sessions
guard_case allow "the default socket under the test TMUX_TMPDIR" "${G_TMP}" -- list-sessions
guard_case deny "-S after the command name (a command argument)" -- list-sessions -S "${G_IN}"

# --- private socket directory -----------------------------------------------
mkdir -p "${ROOT}/s"
if sock=$(tmuxf_socket_dir "${ROOT}/s/fresh"); then
    assert_eq "${ROOT}/s/fresh/tmux-${TMUXF_UID}/default" "${sock}" "socket dir: path under the test tmpdir"
    assert_eq 700 "$(stat -c '%a' "${ROOT}/s/fresh/tmux-${TMUXF_UID}" 2> /dev/null || stat -f '%Lp' "${ROOT}/s/fresh/tmux-${TMUXF_UID}")" \
        "socket dir: created 0700"
else
    fail "socket dir: could not create the private socket parent"
fi
mkdir -p "${ROOT}/s/linked" "${ROOT}/s/elsewhere" && chmod 700 "${ROOT}/s/elsewhere"
ln -s "${ROOT}/s/elsewhere" "${ROOT}/s/linked/tmux-${TMUXF_UID}"
run_capture tmuxf_socket_dir "${ROOT}/s/linked"
assert_status nonzero "${RUN_STATUS}" "socket dir: refuses a symlinked socket parent"

# --- verified stop -----------------------------------------------------------
# A socket path outside the scenario root is never stopped.
run_capture env TS_ROOT="${ROOT}/scenario" TS_SOCK="${ROOT}/other/sock" bash -c \
    'source "$1"; source "$2"; tmuxf_stop' _ "${REPO_ROOT}/tests/lib/common.bash" \
    "${REPO_ROOT}/tests/lib/tmux_fixture.bash"
assert_status 1 "${RUN_STATUS}" "tmuxf_stop refuses a socket outside the scenario root"

# --- inventory normaliser ----------------------------------------------------
# inv_case <label> <same|differs> <before> <after>
inv_case() {
    local actual=differs
    [[ "$(tmuxf_normalize_inventory <<< "$3")" == "$(tmuxf_normalize_inventory <<< "$4")" ]] && actual=same
    assert_eq "$2" "${actual}" "normaliser: $1"
}
LEGACY='W s:1 1 b2a1,80x24,0,0{40x24,0,0,1,39x24,41,0,2} term'
inv_case "legacy: new pane IDs only" same "${LEGACY}" 'W s:1 1 3c4f,80x24,0,0{40x24,0,0,2,39x24,41,0,3} term'
inv_case "legacy: changed pane size" differs "${LEGACY}" 'W s:1 1 b2a1,80x24,0,0{41x24,0,0,1,38x24,42,0,2} term'
inv_case "legacy: lost layout leaf" differs "${LEGACY}" 'W s:1 1 b2a1,80x24,0,0{40x24,0,0,1} term'
JSON='W s:1 1 {"V":2,"L":{"t":"h","w":80,"C":[{"t":"p","w":40,"i":0,"I":"%1"},{"t":"p","w":39,"i":1,"I":"%2"}]}} term'
inv_case "json-v2: new pane IDs only" same "${JSON}" "${JSON//%2/%7}"
inv_case "json-v2: changed pane size" differs "${JSON}" "${JSON/\"w\":40/\"w\":41}"
inv_case "json-v2: changed pane index" differs "${JSON}" "${JSON/\"i\":1/\"i\":2}"

tests_finish
