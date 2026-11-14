#!/usr/bin/env bash
# Shared helpers for the repository's plain-bash tests. Source it; do not run it.
#
#   source "${REPO_ROOT}/tests/lib/common.bash"
#
# Output lines: "PASS: <label>", "FAIL: <label>[: detail]", "SKIP: <label>".
# Works with `set -u`; bash 3.2 compatible (no associative arrays).
#
# API
#   Counters (read-only for callers): TESTS_PASSED TESTS_FAILED TESTS_SKIPPED
#   pass <label>                        record a passing check
#   fail <label>                        record a failing check
#   skip <label>                        record a visible skip (counted)
#   tests_strict                        true when CI or TESTS_STRICT=1 (skips fail)
#   require_cmd <label> <cmd>...        true if every cmd is on PATH; else skip
#                                       "<label>: <cmd> not installed" and return 1
#
#   assert_eq <expected> <actual> <label>
#   assert_ne <unexpected> <actual> <label>
#   assert_contains <haystack> <needle> <label>       fixed-string substring
#   assert_not_contains <haystack> <needle> <label>
#   assert_file_contains <file> <needle> <label>      fixed string; missing or
#                                                     unreadable file fails
#   assert_file_not_contains <file> <needle> <label>  missing/unreadable fails
#   assert_status <expected> <actual> <label>         expected: N or "nonzero"
#
#   run_capture <cmd> [args...]         run cmd; set RUN_STATUS, RUN_STDOUT,
#                                       RUN_STDERR (separately); always returns 0
#   wait_until <seconds> <cmd> [args...] poll cmd every 0.1s until it succeeds;
#                                       return 1 on timeout
#
#   tests_init_tmp [prefix]             create TEST_TMP_ROOT (mktemp -d) and
#                                       install EXIT/INT/TERM/HUP cleanup traps
#   add_cleanup <command string>        run at exit, last added first, before
#                                       TEST_TMP_ROOT is removed
#   make_test_dir <prefix>              print a fresh dir under TEST_TMP_ROOT
#   remove_test_dir <dir>               rm -rf only a dir make_test_dir made
#
#   tests_summary                       print counts; return 1 on any failure,
#                                       on zero recorded checks, or on any skip
#                                       when tests_strict
#   tests_finish                        tests_summary, then exit with its status

[[ -n "${_TESTS_COMMON_LOADED:-}" ]] && return 0
_TESTS_COMMON_LOADED=1

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_TMP_ROOT="${TEST_TMP_ROOT:-}"
_TESTS_CLEANUPS=()

# --- Recording ---------------------------------------------------------------

pass() { printf 'PASS: %s\n' "$1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

tests_strict() {
    [[ "${TESTS_STRICT:-}" == 1 ]] && return 0
    [[ -n "${CI:-}" && "${CI}" != 0 && "${CI}" != false ]]
}

require_cmd() {
    local label="$1" cmd missing=()
    shift
    for cmd in "$@"; do
        command -v "${cmd}" > /dev/null 2>&1 || missing+=("${cmd}")
    done
    if ((${#missing[@]} > 0)); then
        skip "${label}: ${missing[*]} not installed"
        return 1
    fi
}

# --- Assertions --------------------------------------------------------------

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        pass "${label}"
    else
        fail "${label}: expected [${expected}] got [${actual}]"
    fi
}

assert_ne() {
    local unexpected="$1" actual="$2" label="$3"
    if [[ "${unexpected}" != "${actual}" ]]; then
        pass "${label}"
    else
        fail "${label}: got unexpected [${actual}]"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        pass "${label}"
    else
        fail "${label}: [${needle}] not found in [${haystack}]"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        pass "${label}"
    else
        fail "${label}: unexpected [${needle}] found in [${haystack}]"
    fi
}

# grep exit 0 = match, 1 = no match, anything else = error; an error or a
# missing file fails the assertion in both directions.
_tests_grep_file() {
    local file="$1" needle="$2"
    [[ -f "${file}" && -r "${file}" ]] || return 2
    grep -qF -- "${needle}" "${file}" 2> /dev/null
}

assert_file_contains() {
    local file="$1" needle="$2" label="$3" status
    _tests_grep_file "${file}" "${needle}"
    status=$?
    case "${status}" in
        0) pass "${label}" ;;
        1) fail "${label}: [${needle}] not found in ${file}" ;;
        *) fail "${label}: cannot read ${file}" ;;
    esac
}

assert_file_not_contains() {
    local file="$1" needle="$2" label="$3" status
    _tests_grep_file "${file}" "${needle}"
    status=$?
    case "${status}" in
        1) pass "${label}" ;;
        0) fail "${label}: unexpected [${needle}] found in ${file}" ;;
        *) fail "${label}: cannot read ${file}" ;;
    esac
}

assert_status() {
    local expected="$1" actual="$2" label="$3"
    if [[ ! "${actual}" =~ ^[0-9]+$ ]]; then
        fail "${label}: status [${actual}] is not a number"
    elif [[ "${expected}" == nonzero ]]; then
        if ((actual != 0)); then
            pass "${label}"
        else
            fail "${label}: expected non-zero status, got 0"
        fi
    elif [[ "${actual}" == "${expected}" ]]; then
        pass "${label}"
    else
        fail "${label}: expected status ${expected}, got ${actual}"
    fi
}

# --- Running -----------------------------------------------------------------

RUN_STATUS=0
RUN_STDOUT=""
RUN_STDERR=""

run_capture() {
    local err_file
    err_file="$(mktemp "${TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/stderr.XXXXXX")" || {
        RUN_STATUS=125 RUN_STDOUT="" RUN_STDERR="run_capture: mktemp failed"
        return 0
    }
    RUN_STDOUT="$("$@" 2> "${err_file}")"
    RUN_STATUS=$?
    RUN_STDERR="$(cat "${err_file}")"
    rm -f -- "${err_file}"
    return 0
}

wait_until() {
    local seconds="$1" tries
    shift
    tries=$((seconds * 10))
    while ((tries-- > 0)); do
        "$@" && return 0
        sleep 0.1
    done
    "$@"
}

# --- Temporary directories and cleanup ---------------------------------------

_tests_cleanup() {
    local status=$? i
    trap - EXIT
    for ((i = ${#_TESTS_CLEANUPS[@]} - 1; i >= 0; i--)); do
        eval "${_TESTS_CLEANUPS[i]}" || true
    done
    if [[ -n "${TEST_TMP_ROOT}" && -d "${TEST_TMP_ROOT}" && ! -L "${TEST_TMP_ROOT}" ]]; then
        rm -rf -- "${TEST_TMP_ROOT}"
    fi
    exit "${status}"
}

tests_init_tmp() {
    local prefix="${1:-test}"
    TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")" || {
        printf 'FAIL: tests_init_tmp: mktemp failed\n'
        exit 1
    }
    trap _tests_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
}

add_cleanup() { _TESTS_CLEANUPS+=("$1"); }

_tests_is_test_dir() {
    local dir="$1"
    [[ -n "${TEST_TMP_ROOT}" && -n "${dir}" && "${dir}" == "${TEST_TMP_ROOT}/"* \
        && "${dir}" != *"/../"* && -d "${dir}" && ! -L "${dir}" ]]
}

make_test_dir() {
    local prefix="$1" dir
    [[ -n "${TEST_TMP_ROOT}" && -d "${TEST_TMP_ROOT}" ]] || {
        printf 'make_test_dir: call tests_init_tmp first\n' >&2
        return 1
    }
    dir="$(mktemp -d "${TEST_TMP_ROOT}/${prefix}.XXXXXX")" || return 1
    _tests_is_test_dir "${dir}" || return 1
    printf '%s\n' "${dir}"
}

remove_test_dir() {
    local dir="$1"
    _tests_is_test_dir "${dir}" || return 1
    rm -rf -- "${dir}"
}

# --- Summary -----------------------------------------------------------------

tests_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    printf '\n%d passed, %d failed, %d skipped\n' \
        "${TESTS_PASSED}" "${TESTS_FAILED}" "${TESTS_SKIPPED}"
    if ((TESTS_FAILED > 0)); then
        return 1
    fi
    if ((total == 0)); then
        printf 'FAIL: no checks were recorded\n'
        return 1
    fi
    if ((TESTS_SKIPPED > 0)) && tests_strict; then
        printf 'FAIL: %d skip(s) not allowed in strict mode (CI / TESTS_STRICT=1)\n' \
            "${TESTS_SKIPPED}"
        return 1
    fi
    return 0
}

tests_finish() {
    tests_summary
    exit $?
}
