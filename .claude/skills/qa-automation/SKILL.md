---
name: qa-automation
description: Use when writing, changing, or reviewing tests in this chezmoi dotfiles repo (tests/*.bash, tests/lib/), or when a code change needs test coverage.
---

# QA Automation — chezmoi dotfiles tests

Plain-bash tests under `tests/`, no framework. Shared helpers live in
`tests/lib/common.bash`; the interactive-shell sandbox (synthetic HOME, logging
fakes, `env -i`) lives in `tests/lib/shell_fixture.bash`. The `ai-wrapper`
submodule has its own suite and rules (`ai-wrapper/docs/testing.md`,
`ai-wrapper/AGENTS.md` §4); do not duplicate its coverage here.

## Running

```bash
bash tests/test_<name>.bash              # one file
bash tests/run_all.bash                  # every registered file
bash tests/run_all.bash tmux_preservation hh_public_api   # a subset by name
TESTS_STRICT=1 bash tests/run_all.bash   # as CI: any SKIP fails
bash -n tests/<file>.bash                # syntax; shellcheck -x -S warning if installed
```

`run_all.bash` runs each file in its own bash process (stdin `/dev/null`),
prints a per-file pass/fail/skip/time table, exits 1 if any file fails, and
fails if a `tests/test_*.bash` on disk is missing from its `TEST_FILES` list.
The environment (`TESTS_STRICT`, `TMPDIR`, `BASH32`, `TMUX_TEST_ONLY`, ...)
passes through. The `bash32` section of `test_tmux_preservation.bash` needs a
bash 3.2 (`BASH32=<path>`), otherwise it is a SKIP.

CI: `.github/workflows/tests.yml` (pull requests) runs
`TESTS_STRICT=1 bash tests/run_all.bash` on ubuntu-24.04 with zsh, python3,
bash-completion, lsof, systemd-analyze, a pinned chezmoi, tmux built from a
pinned release (Ubuntu's 3.4 escapes `$` in `show -v`, which breaks the
resurrect hooks), and bash 3.2 built from GNU source. New tools a test needs
go in that workflow too.

Never run `chezmoi apply` as part of testing.

## Rules

1. **Behaviour through public interfaces.** Run the function or script; check
   exit status, stdout and stderr separately, files written, and argv that
   reached faked external commands. Never grep source/config text as a
   substitute for behaviour; no change-detector, byte or snapshot comparison of
   source; no magic counts of lines in source.
2. **Never lock in bugs.** If current behaviour is wrong, fix the code and
   assert the correct behaviour. Only if a fix is out of scope: an explicit
   known-bug check that FAILs once fixed, with an issue reference.
3. **No historical-only checks.** No comparisons against baseline commits, no
   "old code was broken" control replays, no "deleted name stays deleted"
   tests unless a realistic regression path exists.
4. **No harness inflation.** Product suites test product code. Harness
   self-checks go in their own file (`test_lib_common.bash`) or stay minimal.
5. **Every assertion can fail.** Check the status of the thing under test, not
   of a probe's last command. Print PASS only when the check passed. A test
   that claims to check stderr captures stderr separately (`run_capture`).
6. **Isolation.** `env -i`, synthetic `HOME`/XDG dirs, fakes first on `PATH`,
   timeouts on anything that can hang. Never touch host services: tmux only
   on a private socket (`tmux -L <name>` / `-S <path>`), never the default
   socket; no real `systemctl`/user services; no network.
7. **Missing tools are visible.** Missing zsh, python3, bash-completion, tmux,
   etc. is a counted SKIP locally and a FAILURE in CI (`CI` set or
   `TESTS_STRICT=1`). Use `require_cmd`; never a silent GAP that exits 0.
8. **Structure.** One scenario per function with fresh fixture state
   (`make_test_dir`); no mutable state shared between scenarios; table-driven
   cases where useful; no fixed sleeps — poll with `wait_until`; fakes log
   deterministically (one line per call, no timestamps/PIDs).
9. **Fakes** mock at the process boundary (a script on `PATH`), can be told to
   fail (env var or flag file), and tests assert on state/effects rather than
   exact argv when argv is not the contract.
10. **No duplicate coverage** across files or with ai-wrapper's own tests;
    parent tests cover only parent integration.
11. **Registered and in CI.** Every `tests/test_*.bash` is listed in
    `tests/run_all.bash` and runs in CI.

## tests/lib/common.bash API

```bash
source "${REPO_ROOT}/tests/lib/common.bash"
tests_init_tmp <prefix>            # TEST_TMP_ROOT + EXIT/INT/TERM/HUP cleanup
add_cleanup '<cmd>'                # LIFO, runs before TEST_TMP_ROOT removal
make_test_dir <prefix>             # fresh dir under TEST_TMP_ROOT (stdout)
remove_test_dir <dir>              # only removes dirs make_test_dir created
pass|fail|skip <label>             # counted PASS:/FAIL:/SKIP: lines
require_cmd <label> <cmd>...       # skip + return 1 when a tool is missing
tests_strict                       # true under CI / TESTS_STRICT=1
assert_eq|assert_ne <expected> <actual> <label>
assert_contains|assert_not_contains <haystack> <needle> <label>
assert_file_contains|assert_file_not_contains <file> <needle> <label>
assert_status <N|nonzero> <actual> <label>
run_capture <cmd> [args...]        # RUN_STATUS, RUN_STDOUT, RUN_STDERR
wait_until <seconds> <cmd> [args...]
tests_finish                       # summary; exit 1 on fail/no checks/strict skip
```

`run_capture` runs the command in a subshell: state changes inside it are not
visible afterwards. Counters are `TESTS_PASSED`, `TESTS_FAILED`,
`TESTS_SKIPPED`.

## Example

Bad — reads source, probe status, silent gap:

```bash
grep -q 'tmux kill-session' bin/executable_foo.bash && echo PASS   # source text
out=$(foo 2>&1); echo "$out" | grep -q ok; assert_eq 0 $? "foo ok" # grep's status
command -v zsh || { echo "GAP: no zsh"; exit 0; }                  # silent in CI
tmux new-session -d -s t                                           # real server
```

Good — behaviour, real status, separate streams, private socket:

```bash
test_foo_stops_session() {
    local home; home="$(make_test_dir foo)"
    run_capture env -i HOME="${home}" PATH="${FAKEBIN}:/usr/bin:/bin" \
        "${REPO_ROOT}/bin/executable_foo.bash" stop demo
    assert_status 0 "${RUN_STATUS}" "foo stop exits 0"
    assert_eq "" "${RUN_STDERR}" "foo stop: no stderr"
    assert_file_contains "${home}/fake-tmux.log" "kill-session -t demo" \
        "foo stop kills the session"
}
require_cmd "zsh startup" zsh && test_zsh_startup
test_foo_stops_session
tests_finish
```

Real tmux, when needed: `tmux -L "test-$$"` (or `-S "${TEST_TMP_ROOT}/sock"`)
plus `add_cleanup "tmux -L test-$$ kill-server"`.
