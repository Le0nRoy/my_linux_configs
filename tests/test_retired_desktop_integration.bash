#!/usr/bin/env bash
# Regression test for issue #57: retired desktop integration and Proton installer.
#
# Source-level checks only: inspects tracked repository files and runs the
# polybar chezmoi widget against a fake `chezmoi`. No template is rendered,
# nothing is applied, and no real chezmoi or application client is executed.
#
# Usage: bash tests/test_retired_desktop_integration.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_PATH="tests/test_retired_desktop_integration.bash"
I3_CONFIG="${REPO_ROOT}/dot_config/i3/config.tmpl"
MIMEAPPS="${REPO_ROOT}/dot_config/private_mimeapps.list"
CHEZMOIIGNORE="${REPO_ROOT}/.chezmoiignore"
WIDGET="${REPO_ROOT}/bin/executable_polybar_chezmoi_widget.sh"
WIDGET_DIRTY_OUTPUT="!CHZ"
TMP_BASE="${TMPDIR:-/tmp}"
RETIRED_PATTERN='proton_install_game|\(\?i\)lens"|postman|\(\?i\)code"|\(\?i\)cursor"|pritunl|keepass2|KeePass/KeePass\.config\.xml|Proton game launcher|Steam Proton'

# Search exit codes, normalised from grep / git grep semantics.
SEARCH_MATCH=0
SEARCH_NO_MATCH=1
SEARCH_ERROR=2

failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }

# Run a search command with grep/git-grep exit semantics (0 = match,
# 1 = no match, anything else = operational error). Stdout and stderr are
# kept in SEARCH_OUTPUT; returns SEARCH_MATCH, SEARCH_NO_MATCH or SEARCH_ERROR.
# Empty output alone is never treated as "no match".
SEARCH_OUTPUT=""
run_search() {
    local status
    SEARCH_OUTPUT="$("$@" 2>&1)"
    status=$?
    case "$status" in
        0) return "$SEARCH_MATCH" ;;
        1) return "$SEARCH_NO_MATCH" ;;
        *) return "$SEARCH_ERROR" ;;
    esac
}

# Search tracked files of the Git work tree in $1 for retired integrations.
# The ai-wrapper submodule is out of scope and this test file necessarily
# names the retired patterns.
search_retired_refs() {
    local tree="$1"
    run_search git -C "$tree" grep -nIiE "$RETIRED_PATTERN" \
        -- . ":(exclude)ai-wrapper" ":(exclude)${SELF_PATH}"
}

# Assert that a fixed string is present (or absent) in a file. A read or
# command error fails the assertion in both directions.
assert_contains() {
    local file="$1" needle="$2" label="$3" status
    run_search grep -qF -- "$needle" "$file"
    status=$?
    case "$status" in
        "$SEARCH_MATCH") pass "$label" ;;
        "$SEARCH_NO_MATCH") fail "$label" ;;
        *) fail "${label}: search error: ${SEARCH_OUTPUT}" ;;
    esac
}

assert_not_contains() {
    local file="$1" needle="$2" label="$3" status
    run_search grep -qF -- "$needle" "$file"
    status=$?
    case "$status" in
        "$SEARCH_NO_MATCH") pass "$label" ;;
        "$SEARCH_MATCH") fail "$label" ;;
        *) fail "${label}: search error: ${SEARCH_OUTPUT}" ;;
    esac
}

# Create a test-owned temporary directory under TMP_BASE and print its path.
make_test_dir() {
    local prefix="$1" dir
    dir="$(mktemp -d "${TMP_BASE}/${prefix}-$(uuidgen 2>/dev/null || echo "$$-$RANDOM").XXXXXX")" || return 1
    is_test_dir "$dir" "$prefix" || return 1
    printf '%s\n' "$dir"
}

# True only for an existing, non-symlink directory created by make_test_dir.
is_test_dir() {
    local dir="$1" prefix="$2"
    [[ -n "$dir" && "$dir" == "${TMP_BASE}/${prefix}-"* && -d "$dir" && ! -L "$dir" ]]
}

# Remove a directory only if it is a validated test-created path.
remove_test_dir() {
    local dir="$1" prefix="$2"
    if is_test_dir "$dir" "$prefix"; then
        rm -rf -- "$dir"
    fi
}

# ---------------------------------------------------------------------------
# Controls: search failures must never pass as "no match"
# ---------------------------------------------------------------------------
expect_search_status() {
    local label="$1" expected="$2" status
    shift 2
    "$@"
    status=$?
    if [[ "$status" -eq "$expected" ]]; then
        pass "control: ${label}"
    else
        fail "control: ${label}: expected status ${expected}, got ${status} (${SEARCH_OUTPUT})"
    fi
}

# Git commands against disposable fixtures: isolated config, and discovery
# never climbs above TMP_BASE into an enclosing repository.
fixture_git() {
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$TMP_BASE" "$@"
}

test_search_controls() {
    local fixture
    fixture="$(make_test_dir search-control)" || { fail "control: fixture directory created"; return; }

    # Disposable Git repository; files are staged only, nothing is committed.
    if mkdir "${fixture}/repo" "${fixture}/plain" \
        && printf 'clean line\n' > "${fixture}/repo/clean.txt" \
        && printf 'clean line\n' > "${fixture}/plain/clean.txt" \
        && fixture_git git -C "${fixture}/repo" init -q \
        && fixture_git git -C "${fixture}/repo" add clean.txt; then
        expect_search_status "git grep no match in clean repo" "$SEARCH_NO_MATCH" \
            fixture_git search_retired_refs "${fixture}/repo"
        if printf 'x-scheme-handler/postman=x\n' > "${fixture}/repo/retired.txt" \
            && fixture_git git -C "${fixture}/repo" add retired.txt; then
            expect_search_status "git grep match in repo with retired reference" "$SEARCH_MATCH" \
                fixture_git search_retired_refs "${fixture}/repo"
        else
            fail "control: retired fixture prepared"
        fi
        # Synthetic trap: a directory without Git metadata must be an error.
        expect_search_status "git grep outside a repository is an error" "$SEARCH_ERROR" \
            fixture_git search_retired_refs "${fixture}/plain"
    else
        fail "control: git fixture prepared"
    fi

    expect_search_status "grep match" "$SEARCH_MATCH" \
        run_search grep -qF -- "clean line" "${fixture}/plain/clean.txt"
    expect_search_status "grep no match" "$SEARCH_NO_MATCH" \
        run_search grep -qF -- "absent line" "${fixture}/plain/clean.txt"
    expect_search_status "grep on unreadable file is an error" "$SEARCH_ERROR" \
        run_search grep -qF -- "absent line" "${fixture}/plain/missing.txt"

    remove_test_dir "$fixture" search-control
}

# ---------------------------------------------------------------------------
# Removal: no active retired-product integration or Proton-installer callers
# ---------------------------------------------------------------------------
test_removed_references() {
    if [[ -e "${REPO_ROOT}/bin/executable_proton_install_game.bash" ]]; then
        fail "proton installer source removed"
    else
        pass "proton installer source removed"
    fi

    local status
    search_retired_refs "$REPO_ROOT"
    status=$?
    case "$status" in
        "$SEARCH_NO_MATCH") pass "no retired integration references in tracked files" ;;
        "$SEARCH_MATCH")
            fail "retired integration references remain:"
            printf '%s\n' "$SEARCH_OUTPUT"
            ;;
        *) fail "retired reference search failed: ${SEARCH_OUTPUT}" ;;
    esac

    assert_not_contains "$MIMEAPPS" "x-scheme-handler/postman" "postman MIME handler removed"
}

# ---------------------------------------------------------------------------
# Retention boundaries
# ---------------------------------------------------------------------------
test_retained_boundaries() {
    # KeePassXC is the active password manager.
    assert_contains "$I3_CONFIG" "bindsym \$mod+F5 exec keepassxc" "keepassxc keybinding retained"
    assert_contains "$I3_CONFIG" 'for_window [class="keepassxc|KeePassXC"]' "keepassxc window rule retained"
    assert_contains "$CHEZMOIIGNORE" '.config/keepassxc/**' "keepassxc ignore gate retained"

    # Steam runtime rules stay (only the installer script is retired).
    assert_contains "$I3_CONFIG" "assign [class=\"(?i)steam.*\"] \$ws5" "steam workspace rule retained"
    assert_contains "$I3_CONFIG" 'for_window [title="News" class="(?i)steam"]' "steam popup rule retained"

    # Other-host applications are out of scope.
    assert_contains "$I3_CONFIG" 'exec --no-startup-id Telegram' "telegram autostart retained"
    assert_contains "$I3_CONFIG" "exec --no-startup-id \"\$HOME/bin/helper.bash todoist\"" "todoist autostart retained"
    assert_contains "$I3_CONFIG" "assign [class=\"(?i)todoist\"] \$ws1" "todoist workspace rule retained"
    assert_contains "$I3_CONFIG" "assign [class=\"(?i)joplin\"] \$ws4" "joplin workspace rule retained"
    assert_contains "${REPO_ROOT}/bin/executable_helper.bash" '"todoist")' "helper.bash todoist retained"
    assert_contains "$MIMEAPPS" 'x-scheme-handler/tg=org.telegram.desktop.desktop' "telegram MIME handler retained"

    # Other IDE rules are not part of the retirement.
    assert_contains "$I3_CONFIG" "assign [class=\"jetbrains-.+\"] \$ws2" "jetbrains workspace rule retained"

    # Generic mouse/text cursor behaviour.
    assert_contains "${REPO_ROOT}/dot_config/polybar/config.ini.tmpl" 'cursor-click = pointer' "polybar pointer cursor retained"

    # Protective runtime-data ignores for the Cursor agent CLI.
    local ignore_file entry label status
    for ignore_file in "$CHEZMOIIGNORE" "${REPO_ROOT}/.gitignore"; do
        for entry in .cursor .config/cursor .local/share/cursor-agent; do
            label="protective ignore '${entry}' retained in ${ignore_file##*/}"
            run_search grep -qxF -- "$entry" "$ignore_file"
            status=$?
            case "$status" in
                "$SEARCH_MATCH") pass "$label" ;;
                "$SEARCH_NO_MATCH") fail "$label" ;;
                *) fail "${label}: search error: ${SEARCH_OUTPUT}" ;;
            esac
        done
    done
}

# ---------------------------------------------------------------------------
# Go-template structure of the i3 config (source check, not a render)
# ---------------------------------------------------------------------------
test_i3_template_structure() {
    local expected actual
    expected="$(cat <<'EOF'
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ else if eq .chezmoi.hostname "dragoncave" -}}
{{ end -}}
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ else if eq .chezmoi.hostname "dragoncave" -}}
{{ end -}}
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ else if eq .chezmoi.hostname "dragoncave" -}}
{{ end -}}
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ else if eq .chezmoi.hostname "dragoncave" -}}
{{ end -}}
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ end -}}
{{ if eq .chezmoi.hostname "dragonlady" -}}
{{ end -}}
EOF
)"
    local status
    actual="$(grep -F '{{' "$I3_CONFIG")"
    status=$?
    if [[ "$status" -ne "$SEARCH_MATCH" ]]; then
        fail "i3 host-scoped template directives read (grep status ${status})"
    elif [[ "$actual" == "$expected" ]]; then
        pass "i3 host-scoped template directives unchanged"
    else
        fail "i3 host-scoped template directives changed"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
    fi

    local darwin_block
    darwin_block="$(grep -cF '{{- if eq .chezmoi.os "darwin" }}' "$CHEZMOIIGNORE")"
    status=$?
    if [[ "$status" -ne "$SEARCH_MATCH" && "$status" -ne "$SEARCH_NO_MATCH" ]]; then
        fail ".chezmoiignore darwin block read (grep status ${status})"
    elif [[ "$darwin_block" == "1" ]]; then
        pass ".chezmoiignore darwin block retained"
    else
        fail ".chezmoiignore darwin block retained"
    fi
}

# ---------------------------------------------------------------------------
# Polybar chezmoi widget with a fake chezmoi (controlled command resolution)
# ---------------------------------------------------------------------------

# Populate a sandbox bin directory that only holds a fake `chezmoi` plus the
# tools the widget and the fake need. Fails if any step fails.
prepare_widget_sandbox() {
    local sandbox="$1" status_output="$2"
    local fake_bin="${sandbox}/bin"
    local tool tool_path

    mkdir -p "$fake_bin" "${sandbox}/home" || return 1
    # cat is used by the fake itself; resolve it through the sandbox too.
    for tool in awk grep cat; do
        tool_path="$(command -v "$tool")" || return 1
        ln -s "$tool_path" "${fake_bin}/${tool}" || return 1
    done
    printf '%s\n' "$status_output" > "${sandbox}/status.txt" || return 1
    cat > "${fake_bin}/chezmoi" <<EOF || return 1
#!${BASH}
echo "\$*" >> "${sandbox}/canary.log"
[[ "\$1" == "status" ]] || exit 99
cat "${sandbox}/status.txt"
EOF
    chmod +x "${fake_bin}/chezmoi"
}

# Run a widget script inside a prepared sandbox with a minimal environment.
# Prints widget stdout; returns the widget's exit status.
run_widget_in_sandbox() {
    local sandbox="$1" widget="$2"
    env -i PATH="${sandbox}/bin" HOME="${sandbox}/home" XDG_CONFIG_HOME="${sandbox}/home/.config" \
        "$BASH" "$widget"
}

# Evaluate one widget case. Returns 0 when the widget exits 0, the fake
# chezmoi was called exactly once with `status`, and stdout matches.
# Otherwise returns 1 with the reason in WIDGET_CASE_REASON.
WIDGET_CASE_REASON=""
check_widget_case() {
    local widget="$1" status_output="$2" expected="$3"
    local sandbox actual widget_status calls result=1
    WIDGET_CASE_REASON=""

    sandbox="$(make_test_dir widget-test)" || { WIDGET_CASE_REASON="sandbox directory not created"; return 1; }

    if ! prepare_widget_sandbox "$sandbox" "$status_output"; then
        WIDGET_CASE_REASON="sandbox preparation failed"
    else
        actual="$(run_widget_in_sandbox "$sandbox" "$widget")"
        widget_status=$?
        calls="$(cat "${sandbox}/canary.log" 2>/dev/null)"
        if [[ "$widget_status" -ne 0 ]]; then
            WIDGET_CASE_REASON="widget exited with status ${widget_status}"
        elif [[ "$calls" != "status" ]]; then
            WIDGET_CASE_REASON="fake chezmoi not invoked exactly once with 'status' (got '${calls}')"
        elif [[ "$actual" != "$expected" ]]; then
            WIDGET_CASE_REASON="expected '${expected}', got '${actual}'"
        else
            result=0
        fi
    fi

    remove_test_dir "$sandbox" widget-test
    return "$result"
}

assert_widget_case() {
    local label="$1" status_output="$2" expected="$3"
    if check_widget_case "$WIDGET" "$status_output" "$expected"; then
        pass "$label"
    else
        fail "${label}: ${WIDGET_CASE_REASON}"
    fi
}

# Control: a widget process that fails must fail its case even though its
# stdout is empty, which would otherwise look like a clean status.
test_widget_failure_control() {
    local label="control: failing widget process fails its case"
    if check_widget_case "${REPO_ROOT}/bin/missing_widget_$$.sh" "" ""; then
        fail "$label"
    elif [[ "$WIDGET_CASE_REASON" == "widget exited with status "* ]]; then
        pass "$label"
    else
        fail "${label}: unexpected reason '${WIDGET_CASE_REASON}'"
    fi
}

test_widget() {
    assert_widget_case "widget clean on empty status" "" ""
    assert_widget_case "widget clean on run-script-only status" \
        "$(printf ' R run_always_install-ai-wrapper.bash\n R run_onchange_enable-tmux-service.bash')" ""
    assert_widget_case "widget dirty on ordinary modification" \
        " M .bashrc" "$WIDGET_DIRTY_OUTPUT"
    assert_widget_case "widget dirty on formerly whitelisted KeePass path" \
        " M .config/KeePass/KeePass.config.xml" "$WIDGET_DIRTY_OUTPUT"
}

test_search_controls
test_removed_references
test_retained_boundaries
test_i3_template_structure
test_widget_failure_control
test_widget

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d check(s) failed\n' "$failures"
    exit 1
fi
printf '\nAll checks passed\n'
