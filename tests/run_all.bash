#!/usr/bin/env bash
# Run every registered test file, each in its own bash process, and print a
# per-file summary. Exit 1 if any file fails or the registry is out of date.
#
# Usage: bash tests/run_all.bash [name...]
#        name: test_foo.bash, test_foo or foo (default: every registered file)
#        TESTS_STRICT=1 bash tests/run_all.bash   # as CI: any SKIP fails
#
# The environment (TESTS_STRICT, CI, TMPDIR, BASH32, TMUX_TEST_ONLY, ...)
# is passed through to every file unchanged.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Every tests/test_*.bash must be listed here (checked below).
TEST_FILES=(
    test_lib_common.bash
    test_hh_public_api.bash
    test_shell_helper_isolation.bash
    test_tmux_harness.bash
    test_tmux_preservation.bash
    test_agent_skill_distribution.bash
    test_retired_desktop_integration.bash
)

usage() {
    sed -n '2,10s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

is_registered() {
    local f
    for f in "${TEST_FILES[@]}"; do
        [[ "${f}" == "$1" ]] && return 0
    done
    return 1
}

# Registry self-check: on disk but not listed, or listed but missing.
registry_errors=0
for path in "${TESTS_DIR}"/test_*.bash; do
    [[ -e "${path}" ]] || continue
    name="${path##*/}"
    if ! is_registered "${name}"; then
        printf 'FAIL: registry: tests/%s is not listed in tests/run_all.bash\n' "${name}"
        registry_errors=$((registry_errors + 1))
    fi
done
for name in "${TEST_FILES[@]}"; do
    if [[ ! -f "${TESTS_DIR}/${name}" ]]; then
        printf 'FAIL: registry: tests/%s is listed but does not exist\n' "${name}"
        registry_errors=$((registry_errors + 1))
    fi
done

selected=()
for arg in "$@"; do
    case "${arg}" in
        -h | --help) usage; exit 0 ;;
    esac
    name="${arg##*/}"
    name="${name%.bash}"
    name="${name#test_}"
    name="test_${name}.bash"
    if ! is_registered "${name}"; then
        printf 'run_all: unknown test file: %s\n' "${arg}" >&2
        exit 2
    fi
    selected+=("${name}")
done
((${#selected[@]} > 0)) || selected=("${TEST_FILES[@]}")

log_dir="$(mktemp -d "${TMPDIR:-/tmp}/run_all.XXXXXX")" || exit 1
trap 'rm -rf -- "${log_dir}"' EXIT

# Counts from the common.bash summary line "N passed, N failed, N skipped";
# files without it (own reporting) get counts from PASS:/FAIL:/SKIP: lines.
counts_of() {
    local log="$1" line
    line=$(grep -E '^[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped$' "${log}" | tail -n 1)
    if [[ -n "${line}" ]]; then
        # shellcheck disable=SC2086
        set -- ${line}
        printf '%s %s %s\n' "$1" "$3" "$5"
    else
        printf '%s %s %s\n' "$(grep -c '^PASS:' "${log}")" \
            "$(grep -c '^FAIL:' "${log}")" "$(grep -c '^SKIP:' "${log}")"
    fi
}

rows=()
failed_files=0
total_start=${SECONDS}
for name in "${selected[@]}"; do
    log="${log_dir}/${name}.log"
    printf '\n===== %s =====\n' "${name}"
    start=${SECONDS}
    bash "${TESTS_DIR}/${name}" < /dev/null 2>&1 | tee "${log}"
    status=${PIPESTATUS[0]}
    duration=$((SECONDS - start))
    read -r n_pass n_fail n_skip < <(counts_of "${log}")
    if ((status == 0)); then result=ok; else result=FAILED; failed_files=$((failed_files + 1)); fi
    rows+=("$(printf '%-6s %-40s %5s %5s %5s %6ss  exit %s' \
        "${result}" "${name}" "${n_pass}" "${n_fail}" "${n_skip}" "${duration}" "${status}")")
done

mode=normal
# Same rule as tests_strict in tests/lib/common.bash.
if [[ "${TESTS_STRICT:-}" == 1 || (-n "${CI:-}" && "${CI}" != 0 && "${CI}" != false) ]]; then
    mode="strict: any skip fails"
fi
printf '\n===== summary (%s) =====\n' "${mode}"
printf '%-6s %-40s %5s %5s %5s %7s\n' result file pass fail skip time
for row in "${rows[@]}"; do printf '%s\n' "${row}"; done
printf '%d file(s), %d failed, %ss total\n' "${#selected[@]}" "${failed_files}" "$((SECONDS - total_start))"
if ((registry_errors > 0)); then
    printf 'FAIL: %d registry error(s) in tests/run_all.bash\n' "${registry_errors}"
fi
((failed_files == 0 && registry_errors == 0))
