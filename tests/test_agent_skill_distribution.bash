#!/usr/bin/env bash
# Regression test for issue #58: caveman and ponytail reach every wrapped
# agent through the existing AI-Wrapper shared-skill distribution, not a
# parent-repository installer.
#
# The pinned AI-Wrapper registration hook and setup_skills.bash are copied
# into a synthetic HOME (default and named profile roots, foreign/user skills,
# settings sentinels) and executed with an isolated environment and a sandbox
# PATH in which every agent client, chezmoi, git and network tool is a trap.
# Nothing touches the real HOME, no client starts and nothing is applied.
#
# This proves file distribution and discoverable placement only. It does not
# prove that a running client activates a skill.
#
# Input: an AI-Wrapper checkout at exactly the parent gitlink commit, clean.
# Default is the ai-wrapper submodule; when that is not initialized, pass an
# explicit read-only checkout of the pinned commit:
#   AI_WRAPPER_PINNED_SRC=/path/to/checkout bash tests/test_agent_skill_distribution.bash
# A missing or mismatched input fails the run; it is never skipped.
#
# Usage: bash tests/test_agent_skill_distribution.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED_SRC="${AI_WRAPPER_PINNED_SRC:-${REPO_ROOT}/ai-wrapper}"
RETIRED_INSTALLER="run_always_install-claude-plugins.bash"
LEGACY_PLUGINS_FILE=".claude/plugins.json"
TMP_BASE="${TMPDIR:-/tmp}"
MARKER=".setup_skills_managed"
GITLINK_MODE="160000"
SETUP_MISSING_SOURCE_STATUS=1
TRAP_STATUS=97

# Skills under test and the pinned files that distribute them.
SHARED_SKILLS=(caveman ponytail)
PINNED_SETUP="bin/executable_setup_skills.bash"
PINNED_HOOK="run_after_register-agent-skills.bash"

# Synthetic named profiles, created before the first run.
PROFILE_ROOTS=(.claude-personal .codex-work .gemini-staging)

# Every destination the pinned setup is expected to populate in the fixture.
EXPECTED_DSTS=(
    .claude/skills
    .codex/skills
    .gemini/config/skills
    .cursor/skills
    .copilot/skills
    .claude-personal/skills
    .codex-work/skills
    .gemini-staging/config/skills
)
FOREIGN_DST=".codex/skills"
FOREIGN_SKILL="caveman"
USER_SKILL_DIR=".claude/skills/my-own-skill"
DRIFT_DST=".claude/skills"
DRIFT_SKILL="ponytail"

# Pre-existing user data that the distribution must leave byte-identical.
SENTINEL_FILES=(
    "$LEGACY_PLUGINS_FILE"
    .claude/settings.json
    .claude-personal/settings.json
    .codex/config.toml
    .gemini/settings.json
    .copilot/config.json
    "${USER_SKILL_DIR}/SKILL.md"
    "${FOREIGN_DST}/${FOREIGN_SKILL}/SKILL.md"
)

# Tools the pinned scripts need; resolved into the sandbox PATH.
REQUIRED_TOOLS=(bash env mkdir cp rm mv cat basename dirname date readlink)
# Commands that must never run during distribution.
TRAPPED_COMMANDS=(claude codex agy cursor-agent copilot chezmoi git gh curl wget npm npx node python3 pip)

failures=0
skips=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failures=$((failures + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; skips=$((skips + 1)); }

# Git with isolated configuration; discovery never climbs above TMP_BASE.
isolated_git() {
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="$TMP_BASE" git "$@"
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
# Pinned input validation
# ---------------------------------------------------------------------------

# Print the commit the parent HEAD pins for the ai-wrapper gitlink.
expected_pin() {
    local entry mode type sha
    entry="$(isolated_git -C "$REPO_ROOT" ls-tree HEAD ai-wrapper)" || return 1
    read -r mode type sha _ <<< "$entry"
    [[ "$mode" == "$GITLINK_MODE" && "$type" == "commit" && -n "$sha" ]] || return 1
    printf '%s\n' "$sha"
}

# validate_pinned_source <dir> <sha> — succeed only for a clean checkout of
# exactly <sha>. The reason for a rejection is kept in PIN_REASON.
PIN_REASON=""
validate_pinned_source() {
    local src="$1" sha="$2" head dirty
    PIN_REASON=""
    if [[ ! -d "$src" ]]; then
        PIN_REASON="not a directory: ${src}"
        return 1
    fi
    if ! head="$(isolated_git -C "$src" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
        || [[ "$(isolated_git -C "$src" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$src" && pwd -P)" ]]; then
        PIN_REASON="not an initialized AI-Wrapper checkout: ${src}"
        return 1
    fi
    if [[ "$head" != "$sha" ]]; then
        PIN_REASON="checkout is at ${head}, parent gitlink pins ${sha}"
        return 1
    fi
    if ! dirty="$(isolated_git -C "$src" status --porcelain --untracked-files=all)"; then
        PIN_REASON="git status failed in ${src}"
        return 1
    fi
    if [[ -n "$dirty" ]]; then
        PIN_REASON="checkout has local changes: ${dirty}"
        return 1
    fi
    return 0
}

# Controls: the validator must reject every input other than the exact pin.
test_pin_validation_controls() {
    local fixture other_sha
    fixture="$(make_test_dir pin-control)" || { fail "control: pin fixture directory created"; return; }

    if validate_pinned_source "${fixture}/missing" "$PIN_SHA"; then
        fail "control: missing pinned source rejected"
    else
        pass "control: missing pinned source rejected"
    fi

    mkdir "${fixture}/plain"
    if validate_pinned_source "${fixture}/plain" "$PIN_SHA"; then
        fail "control: non-checkout directory rejected"
    else
        pass "control: non-checkout directory rejected"
    fi

    if mkdir "${fixture}/repo" \
        && isolated_git -C "${fixture}/repo" init -q \
        && printf 'x\n' > "${fixture}/repo/file.txt" \
        && isolated_git -C "${fixture}/repo" add file.txt \
        && isolated_git -C "${fixture}/repo" -c user.name=test -c user.email=test@invalid \
            commit -q -m fixture \
        && other_sha="$(isolated_git -C "${fixture}/repo" rev-parse HEAD)"; then
        if validate_pinned_source "${fixture}/repo" "$PIN_SHA"; then
            fail "control: checkout at another commit rejected"
        else
            pass "control: checkout at another commit rejected"
        fi
        if validate_pinned_source "${fixture}/repo" "$other_sha"; then
            pass "control: clean checkout at the expected commit accepted"
        else
            fail "control: clean checkout at the expected commit accepted (${PIN_REASON})"
        fi
        printf 'y\n' > "${fixture}/repo/untracked.txt"
        if validate_pinned_source "${fixture}/repo" "$other_sha"; then
            fail "control: dirty checkout rejected"
        else
            pass "control: dirty checkout rejected"
        fi
    else
        fail "control: git fixture prepared"
    fi

    remove_test_dir "$fixture" pin-control
}

# ---------------------------------------------------------------------------
# Parent source: the redundant installer is retired, nothing replaces it
# ---------------------------------------------------------------------------
test_parent_source() {
    if [[ -e "${REPO_ROOT}/${RETIRED_INSTALLER}" ]]; then
        fail "redundant parent installer ${RETIRED_INSTALLER} removed"
    else
        pass "redundant parent installer ${RETIRED_INSTALLER} removed"
    fi

    # Deployable parent sources must not write Claude plugin settings files.
    # Documentation and tests describe the retirement and are excluded.
    local output status
    output="$(isolated_git -C "$REPO_ROOT" grep -nIE 'plugins\.json|install-claude-plugins|enabledPlugins|extraKnownMarketplaces' \
        -- . ':(exclude)ai-wrapper' ':(exclude)docs' ':(exclude)tests' 2>&1)"
    status=$?
    case "$status" in
        1) pass "no deployable parent source manages Claude plugin settings" ;;
        0) fail "deployable parent source still manages Claude plugin settings:"; printf '%s\n' "$output" ;;
        *) fail "parent source search failed: ${output}" ;;
    esac

    # The parent applies AI-Wrapper with HOME/ai-wrapper as destination, which
    # is where the pinned hook expects setup_skills.bash and the skill source.
    if grep -qF -- "--destination \"\${HOME}/ai-wrapper\"" "${REPO_ROOT}/run_always_install-ai-wrapper.bash"; then
        pass "parent applies AI-Wrapper into \${HOME}/ai-wrapper"
    else
        fail "parent applies AI-Wrapper into \${HOME}/ai-wrapper"
    fi
}

# ---------------------------------------------------------------------------
# Pinned source: the distributor and the shared skills exist as expected
# ---------------------------------------------------------------------------
test_pinned_layout() {
    local name file
    for file in "$PINNED_SETUP" "$PINNED_HOOK"; do
        if [[ -f "${PINNED_SRC}/${file}" ]]; then
            pass "pinned ${file} present"
        else
            fail "pinned ${file} present"
        fi
    done
    if grep -qF -- "\"\${HOME}/ai-wrapper/bin/setup_skills.bash\"" "${PINNED_SRC}/${PINNED_HOOK}"; then
        pass "pinned hook invokes \${HOME}/ai-wrapper/bin/setup_skills.bash"
    else
        fail "pinned hook invokes \${HOME}/ai-wrapper/bin/setup_skills.bash"
    fi
    for name in "${SHARED_SKILLS[@]}"; do
        if [[ -f "${PINNED_SRC}/dot_agents/skills/${name}/SKILL.md" ]] \
            && grep -qx -- "name: ${name}" "${PINNED_SRC}/dot_agents/skills/${name}/SKILL.md"; then
            pass "pinned shared skill ${name} has SKILL.md with name: ${name}"
        else
            fail "pinned shared skill ${name} has SKILL.md with name: ${name}"
        fi
        # The fixture deploys skill files verbatim; a chezmoi attribute
        # prefix would make that differ from what chezmoi deploys.
        if find "${PINNED_SRC}/dot_agents/skills/${name}" -mindepth 1 \
            \( -name 'dot_*' -o -name 'executable_*' -o -name 'private_*' -o -name '*.tmpl' \
               -o -name 'symlink_*' -o -name 'run_*' -o -name 'modify_*' \) -print -quit | grep -q .; then
            fail "pinned skill ${name} has no chezmoi attribute names"
        else
            pass "pinned skill ${name} has no chezmoi attribute names"
        fi
    done
}

# ---------------------------------------------------------------------------
# Fixture: synthetic HOME populated as the parent + pinned chezmoi apply would
# ---------------------------------------------------------------------------

# prepare_fixture <root> <mode> — mode is "rsync" or "cp" (setup fallback).
# Fails if any step fails.
prepare_fixture() {
    local root="$1" mode="$2" home="${1}/home"
    local tool tool_path name cmd profile

    mkdir -p "${root}/bin" "${root}/hook" "${root}/tmp" \
        "${home}/ai-wrapper/bin" "${home}/ai-wrapper/.agents/skills" "${home}/.config" \
        "${home}/.local/share" "${home}/.local/state" "${home}/.cache" || return 1

    local tools=("${REQUIRED_TOOLS[@]}")
    [[ "$mode" == "rsync" ]] && tools+=(rsync)
    for tool in "${tools[@]}"; do
        tool_path="$(command -v "$tool")" || return 1
        ln -s "$tool_path" "${root}/bin/${tool}" || return 1
    done
    for cmd in "${TRAPPED_COMMANDS[@]}"; do
        printf '#!%s\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/canary.log"\nexit %d\n' \
            "$BASH" "$cmd" "$root" "$TRAP_STATUS" > "${root}/bin/${cmd}" || return 1
        chmod +x "${root}/bin/${cmd}" || return 1
    done

    # Pinned producers, placed where the secondary chezmoi apply puts them.
    cp -- "${PINNED_SRC}/${PINNED_SETUP}" "${home}/ai-wrapper/bin/setup_skills.bash" || return 1
    chmod +x "${home}/ai-wrapper/bin/setup_skills.bash" || return 1
    cp -- "${PINNED_SRC}/${PINNED_HOOK}" "${root}/hook/${PINNED_HOOK}" || return 1
    for name in "${SHARED_SKILLS[@]}"; do
        cp -R -- "${PINNED_SRC}/dot_agents/skills/${name}" "${home}/ai-wrapper/.agents/skills/${name}" || return 1
    done

    for profile in "${PROFILE_ROOTS[@]}"; do
        mkdir -p "${home}/${profile}" || return 1
    done
    # A non-directory with a profile-like name must not become a destination.
    printf 'note\n' > "${home}/.claude-notes" || return 1

    # User content and settings that must survive unchanged.
    mkdir -p "${home}/${USER_SKILL_DIR}" "${home}/${FOREIGN_DST}/${FOREIGN_SKILL}" \
        "${home}/.codex" "${home}/.gemini" "${home}/.copilot" || return 1
    printf -- '---\nname: my-own-skill\n---\nuser skill\n' > "${home}/${USER_SKILL_DIR}/SKILL.md" || return 1
    printf -- '---\nname: caveman\n---\nuser-maintained variant\n' \
        > "${home}/${FOREIGN_DST}/${FOREIGN_SKILL}/SKILL.md" || return 1
    printf '{"enabledPlugins":{"caveman@caveman":false,"other@market":true}}\n' \
        > "${home}/${LEGACY_PLUGINS_FILE}" || return 1
    printf '{"enabledPlugins":{"ponytail@ponytail":false,"unrelated@official":true},"theme":"dark"}\n' \
        > "${home}/.claude/settings.json" || return 1
    printf '{"model":"profile-choice"}\n' > "${home}/.claude-personal/settings.json" || return 1
    printf 'model = "user-choice"\n' > "${home}/.codex/config.toml" || return 1
    printf '{"user":"setting"}\n' > "${home}/.gemini/settings.json" || return 1
    printf '{"user":"setting"}\n' > "${home}/.copilot/config.json" || return 1
}

# Run a command inside the fixture with an isolated environment.
run_in_fixture() {
    local root="$1"
    shift
    env -i PATH="${root}/bin" HOME="${root}/home" TMPDIR="${root}/tmp" \
        XDG_CONFIG_HOME="${root}/home/.config" XDG_DATA_HOME="${root}/home/.local/share" \
        XDG_STATE_HOME="${root}/home/.local/state" XDG_CACHE_HOME="${root}/home/.cache" \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C \
        "$@"
}

# Print a content snapshot of a tree: type, mode, path and file hash.
snapshot_tree() {
    local dir="$1"
    (cd "$dir" && find . -printf '%y %m %p\n' | LC_ALL=C sort \
        && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

# Print hashes of the sentinel files of a fixture home.
snapshot_sentinels() {
    local home="$1" file
    for file in "${SENTINEL_FILES[@]}"; do
        printf '%s ' "$file"
        sha256sum < "${home}/${file}" || return 1
    done
}

# Assert every expected destination holds exact managed copies of the
# current fixture source, except the foreign copy, which must be untouched.
assert_distribution() {
    local root="$1" label="$2" home="${1}/home"
    local dst name src dest ok=1
    for dst in "${EXPECTED_DSTS[@]}"; do
        for name in "${SHARED_SKILLS[@]}"; do
            src="${home}/ai-wrapper/.agents/skills/${name}"
            dest="${home}/${dst}/${name}"
            if [[ "$dst" == "$FOREIGN_DST" && "$name" == "$FOREIGN_SKILL" ]]; then
                if [[ -e "${dest}/${MARKER}" ]]; then
                    fail "${label}: foreign ${dst}/${name} left unmanaged"
                    ok=0
                fi
                continue
            fi
            if ! diff -r --exclude="$MARKER" -- "$src" "$dest" > /dev/null 2>&1; then
                fail "${label}: ${dst}/${name} is an exact copy of the shared source"
                ok=0
            elif [[ "$(cat -- "${dest}/${MARKER}" 2>/dev/null)" != "$src" ]]; then
                fail "${label}: ${dst}/${name} carries a marker naming its source"
                ok=0
            fi
        done
    done
    [[ "$ok" -eq 1 ]] && pass "${label}: caveman and ponytail distributed to ${#EXPECTED_DSTS[@]} destinations; foreign copy unmanaged"
}

assert_equal() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        fail "${label}: expected '${expected}', got '${actual}'"
    fi
}

assert_output_has() {
    local label="$1" output="$2" needle="$3"
    if grep -qF -- "$needle" <<< "$output"; then
        pass "$label"
    else
        fail "${label}: missing '${needle}' in output"
    fi
}

# Full distribution scenario for one copy mode.
run_distribution_scenario() {
    local mode="$1" root home hook output status
    local sentinels_before sentinels_after tree_after_first tree_after_rerun
    local fresh=$(( ${#EXPECTED_DSTS[@]} * ${#SHARED_SKILLS[@]} - 1 ))

    root="$(make_test_dir skill-dist)" || { fail "${mode}: fixture directory created"; return; }
    home="${root}/home"
    hook="${root}/hook/${PINNED_HOOK}"

    if ! prepare_fixture "$root" "$mode"; then
        fail "${mode}: fixture prepared"
        remove_test_dir "$root" skill-dist
        return
    fi
    pass "${mode}: fixture prepared"

    if ! sentinels_before="$(snapshot_sentinels "$home")"; then
        fail "${mode}: sentinel snapshot taken"
        remove_test_dir "$root" skill-dist
        return
    fi

    # First run through the pinned after-apply registration hook.
    output="$(run_in_fixture "$root" "$BASH" "$hook" 2>&1)"
    status=$?
    assert_equal "${mode}: registration hook exits 0" 0 "$status"
    assert_output_has "${mode}: first run counts" "$output" \
        "Copied: ${fresh}, Updated: 0, Replaced: 0, Skipped: 1, Retired: 0"
    assert_output_has "${mode}: foreign copy reported as skipped" "$output" \
        "SKIP    ${FOREIGN_SKILL} (unmanaged directory at ${home}/${FOREIGN_DST}/${FOREIGN_SKILL}"
    assert_distribution "$root" "${mode}: first run"
    if [[ -e "${home}/.claude-notes/skills" ]]; then
        fail "${mode}: profile-like non-directory not treated as a profile"
    else
        pass "${mode}: profile-like non-directory not treated as a profile"
    fi
    tree_after_first="$(snapshot_tree "$home")"

    # Rerun without changes: same counts, identical tree content.
    output="$(run_in_fixture "$root" "$BASH" "$hook" 2>&1)"
    status=$?
    assert_equal "${mode}: rerun exits 0" 0 "$status"
    assert_output_has "${mode}: rerun refreshes only managed copies" "$output" \
        "Copied: 0, Updated: ${fresh}, Replaced: 0, Skipped: 1, Retired: 0"
    tree_after_rerun="$(snapshot_tree "$home")"
    if [[ "$tree_after_first" == "$tree_after_rerun" ]]; then
        pass "${mode}: rerun leaves type, mode and content of every path unchanged"
    else
        fail "${mode}: rerun leaves type, mode and content of every path unchanged"
        diff <(printf '%s\n' "$tree_after_first") <(printf '%s\n' "$tree_after_rerun")
    fi

    # Managed refresh: drift in a managed copy and a source update are both
    # reconciled; stray files in managed copies disappear.
    if printf 'local drift\n' >> "${home}/${DRIFT_DST}/${DRIFT_SKILL}/SKILL.md" \
        && printf 'stray\n' > "${home}/${DRIFT_DST}/${DRIFT_SKILL}/stray.txt" \
        && printf '\nsource update\n' >> "${home}/ai-wrapper/.agents/skills/caveman/SKILL.md"; then
        output="$(run_in_fixture "$root" "$BASH" "$hook" 2>&1)"
        status=$?
        assert_equal "${mode}: refresh run exits 0" 0 "$status"
        assert_distribution "$root" "${mode}: after drift and source update"
        if [[ -e "${home}/${DRIFT_DST}/${DRIFT_SKILL}/stray.txt" ]]; then
            fail "${mode}: stray file removed from managed copy"
        else
            pass "${mode}: stray file removed from managed copy"
        fi
    else
        fail "${mode}: drift fixture prepared"
    fi

    if sentinels_after="$(snapshot_sentinels "$home")" && [[ "$sentinels_before" == "$sentinels_after" ]]; then
        pass "${mode}: legacy plugins.json, settings, user and foreign skills unchanged"
    else
        fail "${mode}: legacy plugins.json, settings, user and foreign skills unchanged"
        diff <(printf '%s\n' "$sentinels_before") <(printf '%s\n' "$sentinels_after")
    fi

    if [[ -s "${root}/canary.log" ]]; then
        fail "${mode}: no client, chezmoi, git or network command invoked"
        cat "${root}/canary.log"
    else
        pass "${mode}: no client, chezmoi, git or network command invoked"
    fi

    remove_test_dir "$root" skill-dist
}

# Without pre-existing Claude state, distribution must not create the
# obsolete plugin file or any Claude settings.
test_fresh_home() {
    local root home output status
    root="$(make_test_dir skill-fresh)" || { fail "fresh: fixture directory created"; return; }
    home="${root}/home"
    if prepare_fixture "$root" cp && rm -rf -- "${home:?}/.claude" "${home:?}/.claude-personal"; then
        output="$(run_in_fixture "$root" "$BASH" "${root}/hook/${PINNED_HOOK}" 2>&1)"
        status=$?
        assert_equal "fresh: registration hook exits 0" 0 "$status"
        if [[ -f "${home}/.claude/skills/caveman/SKILL.md" && -f "${home}/.claude/skills/ponytail/SKILL.md" ]]; then
            pass "fresh: Claude skill root created with caveman and ponytail"
        else
            fail "fresh: Claude skill root created with caveman and ponytail"
        fi
        if [[ -e "${home}/${LEGACY_PLUGINS_FILE}" || -e "${home}/.claude/settings.json" ]]; then
            fail "fresh: no plugins.json or settings.json created"
        else
            pass "fresh: no plugins.json or settings.json created"
        fi
    else
        fail "fresh: fixture prepared"
    fi
    remove_test_dir "$root" skill-fresh
}

# Producer failure controls: a missing skill source fails setup; a missing
# setup script is reported by the hook (the pinned hook only warns).
test_producer_failures() {
    local root home output status
    root="$(make_test_dir skill-fail)" || { fail "control: failure fixture directory created"; return; }
    home="${root}/home"
    if prepare_fixture "$root" cp; then
        rm -rf -- "${home:?}/ai-wrapper/.agents"
        output="$(run_in_fixture "$root" "$BASH" "${home}/ai-wrapper/bin/setup_skills.bash" 2>&1)"
        status=$?
        assert_equal "control: setup with missing skill source fails" "$SETUP_MISSING_SOURCE_STATUS" "$status"
        assert_output_has "control: setup names missing skill source" "$output" "ERROR: skills source dir not found"
        output="$(run_in_fixture "$root" "$BASH" "${root}/hook/${PINNED_HOOK}" 2>&1)"
        status=$?
        if [[ "$status" -ne 0 ]]; then
            pass "control: hook propagates setup failure (status ${status})"
        else
            fail "control: hook propagates setup failure"
        fi

        rm -f -- "${home}/ai-wrapper/bin/setup_skills.bash"
        output="$(run_in_fixture "$root" "$BASH" "${root}/hook/${PINNED_HOOK}" 2>&1)"
        status=$?
        assert_equal "control: hook without setup script exits 0 (warn-only)" 0 "$status"
        assert_output_has "control: hook without setup script warns" "$output" "skills not synced"
        if [[ -e "${home}/.claude/skills/caveman" ]]; then
            fail "control: nothing distributed when producers are missing"
        else
            pass "control: nothing distributed when producers are missing"
        fi
    else
        fail "control: failure fixture prepared"
    fi

    # The tree snapshot must notice a content change, so the rerun check
    # cannot pass vacuously.
    local before after
    printf 'a\n' > "${root}/tmp/probe"
    before="$(snapshot_tree "${root}/tmp")"
    printf 'b\n' > "${root}/tmp/probe"
    after="$(snapshot_tree "${root}/tmp")"
    if [[ -n "$before" && "$before" != "$after" ]]; then
        pass "control: tree snapshot detects content changes"
    else
        fail "control: tree snapshot detects content changes"
    fi
    remove_test_dir "$root" skill-fail
}

# ---------------------------------------------------------------------------

if ! PIN_SHA="$(expected_pin)"; then
    fail "parent HEAD pins ai-wrapper as a gitlink"
    printf '\n%d check(s) failed\n' "$failures"
    exit 1
fi
printf 'INFO: parent %s pins AI-Wrapper %s\n' "$(isolated_git -C "$REPO_ROOT" rev-parse HEAD)" "$PIN_SHA"

test_pin_validation_controls
test_parent_source

if ! validate_pinned_source "$PINNED_SRC" "$PIN_SHA"; then
    fail "pinned AI-Wrapper input: ${PIN_REASON}"
    printf 'Provide a clean checkout of %s via AI_WRAPPER_PINNED_SRC.\n' "$PIN_SHA"
    printf '\n%d check(s) failed\n' "$failures"
    exit 1
fi
pass "pinned AI-Wrapper input ${PINNED_SRC} is a clean checkout of ${PIN_SHA}"

test_pinned_layout
test_producer_failures
test_fresh_home
run_distribution_scenario cp
if command -v rsync > /dev/null 2>&1; then
    run_distribution_scenario rsync
else
    skip "rsync scenario: rsync not installed on this host; only the cp fallback was exercised"
fi

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d check(s) failed, %d skipped\n' "$failures" "$skips"
    exit 1
fi
printf '\nAll checks passed, %d skipped\n' "$skips"
