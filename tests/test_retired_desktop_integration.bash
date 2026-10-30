#!/usr/bin/env bash
# Regression test for issue #57: retired desktop integration and Proton installer.
#
# Source-level checks only: inspects tracked repository files and runs the
# polybar chezmoi widget against a fake `chezmoi`. No template is rendered,
# nothing is applied, and no real chezmoi or application client is executed.
#
# Usage: bash tests/test_retired_desktop_integration.bash

# Needles are literal i3 config lines containing `$mod`/`$wsN`/`$HOME`.
# shellcheck disable=SC2016

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF_PATH="tests/test_retired_desktop_integration.bash"
I3_CONFIG="${REPO_ROOT}/dot_config/i3/config.tmpl"
MIMEAPPS="${REPO_ROOT}/dot_config/private_mimeapps.list"
CHEZMOIIGNORE="${REPO_ROOT}/.chezmoiignore"
WIDGET="${REPO_ROOT}/bin/executable_polybar_chezmoi_widget.sh"
WIDGET_DIRTY_OUTPUT="!CHZ"

failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }

# Assert that a fixed string is present (or absent) in a file.
assert_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then pass "$label"; else fail "$label"; fi
}

assert_not_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then fail "$label"; else pass "$label"; fi
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

    # Tracked files only; the ai-wrapper submodule is out of scope and this
    # test file necessarily names the retired patterns.
    local matches
    matches="$(cd "$REPO_ROOT" && git grep -nIiE \
        'proton_install_game|\(\?i\)lens"|postman|\(\?i\)code"|\(\?i\)cursor"|pritunl|keepass2|KeePass/KeePass\.config\.xml|Proton game launcher|Steam Proton' \
        -- . ":(exclude)ai-wrapper" ":(exclude)${SELF_PATH}")"
    if [[ -z "$matches" ]]; then
        pass "no retired integration references in tracked files"
    else
        fail "retired integration references remain:"
        printf '%s\n' "$matches"
    fi

    assert_not_contains "$MIMEAPPS" "x-scheme-handler/postman" "postman MIME handler removed"
}

# ---------------------------------------------------------------------------
# Retention boundaries
# ---------------------------------------------------------------------------
test_retained_boundaries() {
    # KeePassXC is the active password manager.
    assert_contains "$I3_CONFIG" 'bindsym $mod+F5 exec keepassxc' "keepassxc keybinding retained"
    assert_contains "$I3_CONFIG" 'for_window [class="keepassxc|KeePassXC"]' "keepassxc window rule retained"
    assert_contains "$CHEZMOIIGNORE" '.config/keepassxc/**' "keepassxc ignore gate retained"

    # Steam runtime rules stay (only the installer script is retired).
    assert_contains "$I3_CONFIG" 'assign [class="(?i)steam.*"] $ws5' "steam workspace rule retained"
    assert_contains "$I3_CONFIG" 'for_window [title="News" class="(?i)steam"]' "steam popup rule retained"

    # Other-host applications are out of scope.
    assert_contains "$I3_CONFIG" 'exec --no-startup-id Telegram' "telegram autostart retained"
    assert_contains "$I3_CONFIG" 'exec --no-startup-id "$HOME/bin/helper.bash todoist"' "todoist autostart retained"
    assert_contains "$I3_CONFIG" 'assign [class="(?i)todoist"] $ws1' "todoist workspace rule retained"
    assert_contains "$I3_CONFIG" 'assign [class="(?i)joplin"] $ws4' "joplin workspace rule retained"
    assert_contains "${REPO_ROOT}/bin/executable_helper.bash" '"todoist")' "helper.bash todoist retained"
    assert_contains "$MIMEAPPS" 'x-scheme-handler/tg=org.telegram.desktop.desktop' "telegram MIME handler retained"

    # Other IDE rules are not part of the retirement.
    assert_contains "$I3_CONFIG" 'assign [class="jetbrains-.+"] $ws2' "jetbrains workspace rule retained"

    # Generic mouse/text cursor behaviour.
    assert_contains "${REPO_ROOT}/dot_config/polybar/config.ini.tmpl" 'cursor-click = pointer' "polybar pointer cursor retained"

    # Protective runtime-data ignores for the Cursor agent CLI.
    local ignore_file entry
    for ignore_file in "$CHEZMOIIGNORE" "${REPO_ROOT}/.gitignore"; do
        for entry in .cursor .config/cursor .local/share/cursor-agent; do
            if grep -qxF -- "$entry" "$ignore_file"; then
                pass "protective ignore '${entry}' retained in $(basename "$ignore_file")"
            else
                fail "protective ignore '${entry}' retained in $(basename "$ignore_file")"
            fi
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
    actual="$(grep -F '{{' "$I3_CONFIG")"
    if [[ "$actual" == "$expected" ]]; then
        pass "i3 host-scoped template directives unchanged"
    else
        fail "i3 host-scoped template directives changed"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
    fi

    local darwin_block
    darwin_block="$(grep -cF '{{- if eq .chezmoi.os "darwin" }}' "$CHEZMOIIGNORE")"
    if [[ "$darwin_block" -eq 1 ]]; then
        pass ".chezmoiignore darwin block retained"
    else
        fail ".chezmoiignore darwin block retained"
    fi
}

# ---------------------------------------------------------------------------
# Polybar chezmoi widget with a fake chezmoi (controlled command resolution)
# ---------------------------------------------------------------------------

# Run the widget with PATH limited to a sandbox bin directory that only holds
# a fake `chezmoi` plus the tools the widget needs. Prints widget stdout.
run_widget_with_status() {
    local sandbox="$1" status_output="$2"
    local fake_bin="${sandbox}/bin"
    local tool tool_path

    mkdir -p "$fake_bin" "${sandbox}/home"
    for tool in awk grep; do
        tool_path="$(command -v "$tool")" || return 1
        ln -sf "$tool_path" "${fake_bin}/${tool}"
    done
    printf '%s\n' "$status_output" > "${sandbox}/status.txt"
    cat > "${fake_bin}/chezmoi" <<EOF
#!${BASH}
echo "\$*" >> "${sandbox}/canary.log"
[[ "\$1" == "status" ]] || exit 99
cat "${sandbox}/status.txt"
EOF
    chmod +x "${fake_bin}/chezmoi"
    # cat is used by the fake itself; resolve it through the sandbox too.
    ln -sf "$(command -v cat)" "${fake_bin}/cat"

    env -i PATH="$fake_bin" HOME="${sandbox}/home" XDG_CONFIG_HOME="${sandbox}/home/.config" \
        "$BASH" "$WIDGET"
}

assert_widget_case() {
    local label="$1" status_output="$2" expected="$3"
    local sandbox actual calls
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/widget-test-$(uuidgen 2>/dev/null || echo $$-$RANDOM).XXXXXX")"
    actual="$(run_widget_with_status "$sandbox" "$status_output")"
    calls="$(cat "${sandbox}/canary.log" 2>/dev/null)"
    rm -rf "$sandbox"

    if [[ "$calls" != "status" ]]; then
        fail "${label}: fake chezmoi not invoked exactly once with 'status' (got '${calls}')"
        return
    fi
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "${label}: expected '${expected}', got '${actual}'"
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

test_removed_references
test_retained_boundaries
test_i3_template_structure
test_widget

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d check(s) failed\n' "$failures"
    exit 1
fi
printf '\nAll checks passed\n'
