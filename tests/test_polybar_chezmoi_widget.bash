#!/usr/bin/env bash
# Behaviour of the polybar chezmoi-status widget (bin/executable_polybar_chezmoi_widget.sh)
# and of the .chezmoiignore rules for agent runtime directories.
#
# The widget runs under `env -i` against a fake `chezmoi` on PATH that logs its
# argv. The ignore check runs the real `chezmoi managed` against a throwaway
# source dir holding the repo's .chezmoiignore; nothing is applied.
#
# Usage: bash tests/test_polybar_chezmoi_widget.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"

WIDGET="${REPO_ROOT}/bin/executable_polybar_chezmoi_widget.sh"
DIRTY="!CHZ"
ERROR="?CHZ"

tests_init_tmp polybar-widget

# Fresh sandbox: bin/ with only a fake `chezmoi` plus the tools the widget
# needs, home/, status.txt (fake output) and chezmoi.log (one argv per call).
# Fake fails with status 3 and a stderr message when <sandbox>/fail exists.
make_widget_sandbox() {
    local status_output="$1" sandbox tool tool_path
    sandbox="$(make_test_dir widget)" || return 1
    mkdir -p "${sandbox}/bin" "${sandbox}/home" || return 1
    for tool in awk cat; do
        tool_path="$(command -v "${tool}")" || return 1
        ln -s "${tool_path}" "${sandbox}/bin/${tool}" || return 1
    done
    printf '%s\n' "${status_output}" > "${sandbox}/status.txt" || return 1
    cat > "${sandbox}/bin/chezmoi" << EOF || return 1
#!${BASH}
printf '%s\n' "\$*" >> "${sandbox}/chezmoi.log"
if [[ -e "${sandbox}/fail" ]]; then
    echo "chezmoi: fake failure" >&2
    exit 3
fi
[[ "\$1" == status ]] || exit 99
cat "${sandbox}/status.txt"
EOF
    chmod +x "${sandbox}/bin/chezmoi" || return 1
    printf '%s\n' "${sandbox}"
}

# Run <widget> in <sandbox>; sets RUN_STATUS/RUN_STDOUT/RUN_STDERR.
run_widget() {
    local sandbox="$1" widget="$2"
    run_capture timeout 10 env -i PATH="${sandbox}/bin" HOME="${sandbox}/home" \
        XDG_CONFIG_HOME="${sandbox}/home/.config" "${BASH}" "${widget}"
}

# One table row: label, fake `chezmoi status` output, expected widget stdout.
check_widget_case() {
    local label="$1" status_output="$2" expected="$3" sandbox
    sandbox="$(make_widget_sandbox "${status_output}")" || {
        fail "${label}: sandbox setup failed"
        return
    }
    run_widget "${sandbox}" "${WIDGET}"
    assert_status 0 "${RUN_STATUS}" "${label}: widget exits 0"
    assert_eq "${expected}" "${RUN_STDOUT}" "${label}: output"
    assert_eq "status" "$(cat "${sandbox}/chezmoi.log" 2> /dev/null)" \
        "${label}: chezmoi called exactly once with 'status'"
}

test_widget_status_table() {
    check_widget_case "empty status" "" ""
    check_widget_case "run-script rows only" \
        "$(printf ' R run_always_install-ai-wrapper.bash\n R run_onchange_enable-tmux-service.bash')" ""
    check_widget_case "ordinary modification" " M .bashrc" "${DIRTY}"
    check_widget_case "KeePass config modification" \
        " M .config/KeePass/KeePass.config.xml" "${DIRTY}"
    check_widget_case "run-script row plus modification" \
        "$(printf ' R run_always_install-ai-wrapper.bash\n M .bashrc')" "${DIRTY}"
    check_widget_case "path with spaces" " A .config/My App/settings file.conf" "${DIRTY}"
}

# A failing `chezmoi status` must not look clean.
test_widget_chezmoi_failure() {
    local label="chezmoi status fails" sandbox
    sandbox="$(make_widget_sandbox " M .bashrc")" || {
        fail "${label}: sandbox setup failed"
        return
    }
    : > "${sandbox}/fail"
    run_widget "${sandbox}" "${WIDGET}"
    assert_status 0 "${RUN_STATUS}" "${label}: widget exits 0"
    assert_eq "${ERROR}" "${RUN_STDOUT}" "${label}: shows error marker, not clean"
    assert_eq "status" "$(cat "${sandbox}/chezmoi.log" 2> /dev/null)" \
        "${label}: chezmoi called exactly once with 'status'"
}

# Control: the harness reports a missing widget script as a failure rather
# than as empty (clean-looking) output.
test_missing_widget_control() {
    local sandbox
    sandbox="$(make_widget_sandbox "")" || {
        fail "control: sandbox setup failed"
        return
    }
    run_widget "${sandbox}" "${REPO_ROOT}/bin/missing_widget_$$.sh"
    assert_status nonzero "${RUN_STATUS}" "control: missing widget script fails"
}

# Agent runtime dirs listed in .chezmoiignore are never managed, even if a
# matching source entry appears. Real chezmoi, throwaway source and home.
test_agent_runtime_dirs_not_managed() {
    local src home path
    src="$(make_test_dir source)" || { fail "ignore: source dir"; return; }
    home="$(make_test_dir home)" || { fail "ignore: home dir"; return; }
    cp "${REPO_ROOT}/.chezmoiignore" "${src}/.chezmoiignore" || { fail "ignore: copy"; return; }
    for path in dot_cursor/settings.json dot_config/cursor/state.json \
        dot_local/share/cursor-agent/state.json dot_control-file; do
        mkdir -p "${src}/$(dirname "${path}")" && : > "${src}/${path}" || {
            fail "ignore: create ${path}"
            return
        }
    done
    run_capture env -i HOME="${home}" PATH="${PATH}" timeout 30 \
        chezmoi --source "${src}" --destination "${home}" \
        --config "${home}/no-config.toml" --persistent-state "${home}/state.boltdb" \
        managed --include files
    assert_status 0 "${RUN_STATUS}" "chezmoi managed exits 0"
    assert_contains "${RUN_STDOUT}" ".control-file" "control: unignored file is managed"
    for path in .cursor/settings.json .config/cursor/state.json \
        .local/share/cursor-agent/state.json; do
        assert_not_contains "${RUN_STDOUT}" "${path}" "${path} not managed"
    done
}

test_widget_status_table
test_widget_chezmoi_failure
test_missing_widget_control
if require_cmd "agent runtime dirs ignore" chezmoi timeout; then
    test_agent_runtime_dirs_not_managed
fi

tests_finish
