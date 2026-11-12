#!/usr/bin/env bash
# Self-test for tests/lib/common.bash. Each scenario runs a short script that
# sources the library in a clean `env -i` bash and checks its exit status and
# output; nothing outside a private temp dir is touched.
#
# Usage: bash tests/test_lib_common.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO_ROOT}/tests/lib/common.bash"
# shellcheck source=tests/lib/common.bash
source "${LIB}"
tests_init_tmp lib-common

# inner <script> [VAR=value...]: run script after sourcing the library in a
# clean environment with a fresh TMPDIR; sets RUN_STATUS / RUN_STDOUT / RUN_STDERR.
inner() {
    local script="$1" tmp
    shift
    tmp="$(make_test_dir inner)" || { fail "inner: make_test_dir failed"; return; }
    run_capture env -i PATH="${PATH}" TMPDIR="${tmp}" "$@" \
        bash -c "set -u; source '${LIB}'; ${script}"
}

test_all_pass_exits_zero() {
    inner 'assert_eq a a eq; assert_contains "foo bar" "o b" sub; tests_finish'
    assert_status 0 "${RUN_STATUS}" "all-pass suite exits 0"
    assert_contains "${RUN_STDOUT}" "PASS: eq" "pass line printed"
    assert_contains "${RUN_STDOUT}" "2 passed, 0 failed, 0 skipped" "summary counts"
}

test_failure_exits_nonzero() {
    inner 'assert_eq a b mismatch; assert_eq c c ok; tests_finish'
    assert_status 1 "${RUN_STATUS}" "failing suite exits 1"
    assert_contains "${RUN_STDOUT}" "FAIL: mismatch: expected [a] got [b]" "fail detail"
    assert_contains "${RUN_STDOUT}" "1 passed, 1 failed, 0 skipped" "fail counted"
}

test_no_checks_fails() {
    inner 'tests_finish'
    assert_status 1 "${RUN_STATUS}" "suite with zero checks exits 1"
}

test_skip_local_vs_strict() {
    local mode
    inner 'skip "needs zsh"; pass p; tests_finish'
    assert_status 0 "${RUN_STATUS}" "skip is not a failure locally"
    assert_contains "${RUN_STDOUT}" "1 passed, 0 failed, 1 skipped" "skip counted"
    for mode in TESTS_STRICT=1 CI=true; do
        inner 'skip "needs zsh"; pass p; tests_finish' "${mode}"
        assert_status 1 "${RUN_STATUS}" "skip fails with ${mode}"
    done
    inner 'skip "needs zsh"; pass p; tests_finish' CI=false
    assert_status 0 "${RUN_STATUS}" "CI=false is not strict"
}

test_require_cmd() {
    inner 'require_cmd "zsh suite" sh no-such-cmd-xyz && pass ran; tests_finish'
    assert_contains "${RUN_STDOUT}" "SKIP: zsh suite: no-such-cmd-xyz not installed" "missing tool skipped"
    assert_not_contains "${RUN_STDOUT}" "PASS: ran" "guarded block not run"
    inner 'require_cmd "sh suite" sh && pass ran; tests_finish'
    assert_contains "${RUN_STDOUT}" "PASS: ran" "present tool runs block"
}

test_assertions_detect_failure() {
    # Table: each negative assertion must record exactly one FAIL.
    local case
    local -a cases=(
        'assert_ne x x l'
        'assert_contains abc z l'
        'assert_not_contains abc b l'
        'assert_status 0 3 l'
        'assert_status nonzero 0 l'
        'assert_status 0 "" l'
        'assert_file_contains /nonexistent/f x l'
        'assert_file_not_contains /nonexistent/f x l'
        'printf "abc\n" > "$TMPDIR/f"; assert_file_contains "$TMPDIR/f" zz l'
        'printf "abc\n" > "$TMPDIR/f"; assert_file_not_contains "$TMPDIR/f" bc l'
    )
    for case in "${cases[@]}"; do
        inner "${case}; tests_finish"
        assert_status 1 "${RUN_STATUS}" "fails: ${case}"
        assert_contains "${RUN_STDOUT}" "0 passed, 1 failed" "one FAIL: ${case}"
    done
}

test_file_assertions_pass() {
    inner 'printf "abc\n" > "$TMPDIR/f"; assert_file_contains "$TMPDIR/f" bc l1;
        assert_file_not_contains "$TMPDIR/f" zz l2; assert_status nonzero 2 l3; tests_finish'
    assert_status 0 "${RUN_STATUS}" "positive file/status assertions pass"
}

test_run_capture_separates_streams() {
    inner 'run_capture sh -c "echo out; echo err >&2; exit 4";
        printf "status=%s\nout=%s\nerr=%s\n" "$RUN_STATUS" "$RUN_STDOUT" "$RUN_STDERR"; pass x; tests_finish'
    assert_contains "${RUN_STDOUT}" $'status=4\nout=out\nerr=err' "status, stdout, stderr captured separately"
}

test_tmp_dirs_and_cleanup() {
    local marker="${TEST_TMP_ROOT}/cleanup-ran"
    inner 'tests_init_tmp t; d=$(make_test_dir case) || exit 9; touch "$d/x";
        printf "root=%s\ndir=%s\n" "$TEST_TMP_ROOT" "$d";
        remove_test_dir "$d" && [[ ! -e "$d" ]] && pass removed;
        remove_test_dir /etc && fail "removed /etc";
        remove_test_dir "$TEST_TMP_ROOT" && fail "removed root";
        add_cleanup "echo first >> \"$MARK\""; add_cleanup "echo second >> \"$MARK\"";
        tests_finish' MARK="${marker}"
    assert_status 0 "${RUN_STATUS}" "tmp-dir scenario exits 0"
    local root
    root="$(sed -n 's/^root=//p' <<<"${RUN_STDOUT}")"
    assert_contains "${root}" "${TEST_TMP_ROOT}/inner." "TEST_TMP_ROOT created under TMPDIR"
    if [[ -n "${root}" && ! -e "${root}" ]]; then
        pass "TEST_TMP_ROOT removed at exit"
    else
        fail "TEST_TMP_ROOT removed at exit: [${root}] still present"
    fi
    assert_eq $'second\nfirst' "$(cat "${marker}" 2>/dev/null)" "cleanups run last-added first"
}

test_cleanup_on_signal() {
    inner 'tests_init_tmp sig; printf "%s\n" "$TEST_TMP_ROOT"; kill -TERM $$; sleep 5'
    assert_status 143 "${RUN_STATUS}" "TERM exits 143"
    if [[ -n "${RUN_STDOUT}" && ! -e "${RUN_STDOUT}" ]]; then
        pass "TEST_TMP_ROOT removed after TERM"
    else
        fail "TEST_TMP_ROOT removed after TERM: [${RUN_STDOUT}] still present"
    fi
}

test_make_test_dir_requires_init() {
    inner 'make_test_dir x'
    assert_status 1 "${RUN_STATUS}" "make_test_dir without tests_init_tmp fails"
    assert_contains "${RUN_STDERR}" "call tests_init_tmp first" "error on stderr"
}

test_wait_until() {
    inner 'wait_until 1 false; echo "s=$?"; touch "$TMPDIR/ready";
        wait_until 1 test -e "$TMPDIR/ready"; echo "s=$?"; pass x; tests_finish'
    assert_contains "${RUN_STDOUT}" $'s=1\ns=0' "wait_until times out, then succeeds"
}

test_all_pass_exits_zero
test_failure_exits_nonzero
test_no_checks_fails
test_skip_local_vs_strict
test_require_cmd
test_assertions_detect_failure
test_file_assertions_pass
test_run_capture_separates_streams
test_tmp_dirs_and_cleanup
test_cleanup_on_signal
test_make_test_dir_requires_init
test_wait_until
tests_finish
