#!/usr/bin/env bash
# Parent integration test for shared agent skills (#58): caveman, ponytail and
# the rest of AI-Wrapper's shared skills reach the wrapped clients through the
# parent's run_always_install-ai-wrapper.bash -> AI-Wrapper after-apply hook ->
# setup_skills.bash chain, not through a parent installer.
#
# The AI-Wrapper files come from the commit the parent HEAD gitlink pins, read
# out of the submodule's git objects with `git archive`; the submodule working
# tree (and whatever branch or local edits it has) is never used. When those
# objects are not available (submodule not initialised, pin not fetched) the
# run is a counted SKIP locally and a FAILURE under CI / TESTS_STRICT=1.
#
# Each scenario runs the parent installer in a synthetic HOME/XDG with env -i
# and a sandbox PATH. `chezmoi` is a fake that deploys only what the skill hook
# needs into the --destination it is given and then runs the pinned hook; every
# agent client, git and network tool is a trap that logs and fails.
#
# Per-destination behaviour of setup_skills.bash (each client root, rsync/cp,
# retirement, Cursor) is covered by AI-Wrapper's own tests/test_setup_skills.bash.
# This file covers only what the parent adds. It does not prove that a running
# client activates a skill.
#
# Usage: bash tests/test_agent_skill_distribution.bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.bash
source "${REPO_ROOT}/tests/lib/common.bash"

INSTALLER="${REPO_ROOT}/run_always_install-ai-wrapper.bash"
PINNED_HOOK="run_after_register-agent-skills.bash"
MARKER=".setup_skills_managed"
FOREIGN_SKILL_DIR=".codex/skills/caveman"
USER_SKILL_DIR=".claude/skills/my-own-skill"
PROFILE_ROOTS=(.claude-personal .codex-work .gemini-staging)
# Destinations the parent relies on: the default Claude root and a named profile.
ANCHOR_DSTS=(.claude/skills .claude-personal/skills)
# Pre-existing user data that must stay byte-identical.
SENTINEL_FILES=(
    .claude/plugins.json
    .claude/settings.json
    .claude-personal/settings.json
    .codex/config.toml
    .gemini/settings.json
    .copilot/config.json
    "${USER_SKILL_DIR}/SKILL.md"
    "${FOREIGN_SKILL_DIR}/SKILL.md"
)
SANDBOX_TOOLS=(bash env mkdir cp rm mv cat chmod basename dirname date readlink)
TRAPPED_COMMANDS=(claude codex agy cursor-agent copilot git gh curl wget npm npx node python3 pip)
TRAP_STATUS=97

tests_init_tmp skill-dist
PINNED_TREE=""
PINNED_SKILLS=()

isolated_git() {
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"
}

# ---------------------------------------------------------------------------
# Pinned input: extract the gitlink commit from the submodule's object store.
# Returns 2 when the objects are unavailable (skip), 1 on extraction failure.
# ---------------------------------------------------------------------------
PIN_REASON=""
extract_pinned_tree() {
    local sub="${REPO_ROOT}/ai-wrapper" entry mode type pin top
    entry="$(isolated_git -C "${REPO_ROOT}" ls-tree HEAD ai-wrapper)" || {
        PIN_REASON="git ls-tree HEAD ai-wrapper failed"; return 1; }
    read -r mode type pin _ <<< "${entry}"
    [[ "${mode}" == 160000 && "${type}" == commit && -n "${pin}" ]] || {
        PIN_REASON="parent HEAD does not pin ai-wrapper as a gitlink"; return 1; }
    top="$(isolated_git -C "${sub}" rev-parse --show-toplevel 2> /dev/null)"
    if [[ ! -d "${sub}" || "${top}" != "$(cd "${sub}" && pwd -P)" ]]; then
        PIN_REASON="ai-wrapper submodule not initialised"; return 2
    fi
    isolated_git -C "${sub}" cat-file -e "${pin}^{commit}" 2> /dev/null || {
        PIN_REASON="pinned commit ${pin} not in the submodule object store"; return 2; }
    PINNED_TREE="${TEST_TMP_ROOT}/pinned"
    mkdir -p "${PINNED_TREE}" || return 1
    isolated_git -C "${sub}" archive --format=tar "${pin}" | tar -x -C "${PINNED_TREE}" || {
        PIN_REASON="git archive ${pin} | tar failed"; return 1; }
    printf 'INFO: AI-Wrapper %s extracted from git objects\n' "${pin}"
}

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

# Fake chezmoi: logs each call, deploys only what the skill hook consumes into
# --destination, then runs the pinned after-apply hook like chezmoi's after
# phase and returns its status. Skill files deploy verbatim, so a chezmoi
# attribute name it would have to translate aborts the fixture.
write_fake_chezmoi() {
    local root="$1" body
    body="$(cat <<'EOF'
#!@BASH@
set -u
printf 'chezmoi %s\n' "$*" >> "@ROOT@/chezmoi.log"
[[ "${1:-}" == apply ]] || exit 97
shift
src="" dst=""
while (($#)); do
    case "$1" in
        --source) src="$2"; shift 2 ;;
        --destination) dst="$2"; shift 2 ;;
        --persistent-state) shift 2 ;;
        *) echo "fake chezmoi: unexpected argument $1" >&2; exit 98 ;;
    esac
done
[[ -d "${src}" && -d "${dst}" ]] || { echo "fake chezmoi: bad --source/--destination" >&2; exit 98; }
if [[ -d "${src}/dot_agents/skills" ]]; then
    odd="$(@FIND@ "${src}/dot_agents/skills" -mindepth 1 \( -name 'dot_*' -o -name 'executable_*' \
        -o -name 'private_*' -o -name '*.tmpl' -o -name 'symlink_*' -o -name 'run_*' -o -name 'modify_*' \) -print -quit)"
    [[ -z "${odd}" ]] || { echo "fake chezmoi: cannot translate ${odd}" >&2; exit 98; }
    mkdir -p "${dst}/.agents/skills" && cp -R "${src}/dot_agents/skills/." "${dst}/.agents/skills/" || exit 1
fi
mkdir -p "${dst}/bin" \
    && cp "${src}/bin/executable_setup_skills.bash" "${dst}/bin/setup_skills.bash" \
    && chmod 755 "${dst}/bin/setup_skills.bash" || exit 1
cd "${dst}" && "@BASH@" "${src}/run_after_register-agent-skills.bash"
EOF
)"
    body="${body//@BASH@/${BASH}}"
    body="${body//@ROOT@/${root}}"
    body="${body//@FIND@/$(command -v find)}"
    printf '%s\n' "${body}" > "${root}/bin/chezmoi" && chmod +x "${root}/bin/chezmoi"
}

# make_fixture <prefix> [bare] — print a fresh fixture root: sandbox bin, a
# private copy of the pinned tree as CHEZMOI_SOURCE_DIR/ai-wrapper, and a HOME
# with named profiles, user/foreign skills and settings sentinels ("bare":
# HOME with XDG dirs only).
make_fixture() {
    local prefix="$1" kind="${2:-full}" root home tool tool_path cmd profile
    local -a tools
    root="$(make_test_dir "${prefix}")" || return 1
    home="${root}/home"
    mkdir -p "${root}/bin" "${root}/tmp" "${root}/src" "${home}/.config" \
        "${home}/.local/share" "${home}/.local/state" "${home}/.cache" || return 1
    cp -R "${PINNED_TREE}" "${root}/src/ai-wrapper" || return 1
    # The installer treats a .git entry as "submodule initialised".
    printf 'gitdir: /nonexistent\n' > "${root}/src/ai-wrapper/.git" || return 1

    tools=("${SANDBOX_TOOLS[@]}")
    command -v rsync > /dev/null 2>&1 && tools+=(rsync)
    for tool in "${tools[@]}"; do
        tool_path="$(command -v "${tool}")" || return 1
        ln -s "${tool_path}" "${root}/bin/${tool}" || return 1
    done
    for cmd in "${TRAPPED_COMMANDS[@]}"; do
        printf '#!%s\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/canary.log"\nexit %d\n' \
            "${BASH}" "${cmd}" "${root}" "${TRAP_STATUS}" > "${root}/bin/${cmd}" || return 1
        chmod +x "${root}/bin/${cmd}" || return 1
    done
    write_fake_chezmoi "${root}" || return 1

    if [[ "${kind}" != bare ]]; then
        for profile in "${PROFILE_ROOTS[@]}"; do
            mkdir -p "${home}/${profile}" || return 1
        done
        mkdir -p "${home}/${USER_SKILL_DIR}" "${home}/${FOREIGN_SKILL_DIR}" \
            "${home}/.gemini" "${home}/.copilot" || return 1
        printf -- '---\nname: my-own-skill\n---\nuser skill\n' > "${home}/${USER_SKILL_DIR}/SKILL.md"
        printf -- '---\nname: caveman\n---\nuser-maintained variant\n' > "${home}/${FOREIGN_SKILL_DIR}/SKILL.md"
        printf '{"enabledPlugins":{"caveman@caveman":false}}\n' > "${home}/.claude/plugins.json"
        printf '{"enabledPlugins":{"ponytail@ponytail":false},"theme":"dark"}\n' > "${home}/.claude/settings.json"
        printf '{"model":"profile-choice"}\n' > "${home}/.claude-personal/settings.json"
        printf 'model = "user-choice"\n' > "${home}/.codex/config.toml"
        printf '{"user":"setting"}\n' > "${home}/.gemini/settings.json"
        printf '{"user":"setting"}\n' > "${home}/.copilot/config.json" || return 1
    fi
    printf '%s\n' "${root}"
}

# in_fixture <root> <cmd>... — run with an empty environment and sandbox PATH.
in_fixture() {
    local root="$1"
    shift
    env -i PATH="${root}/bin" HOME="${root}/home" TMPDIR="${root}/tmp" \
        CHEZMOI_SOURCE_DIR="${root}/src" \
        XDG_CONFIG_HOME="${root}/home/.config" XDG_DATA_HOME="${root}/home/.local/share" \
        XDG_STATE_HOME="${root}/home/.local/state" XDG_CACHE_HOME="${root}/home/.cache" \
        LC_ALL=C "$@"
}

run_installer() { run_capture in_fixture "$1" "${BASH}" "${INSTALLER}"; }

snapshot_tree() {
    (cd "$1" && find . -printf '%y %m %p\n' | LC_ALL=C sort \
        && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

snapshot_sentinels() {
    local home="$1" file
    for file in "${SENTINEL_FILES[@]}"; do
        printf '%s ' "${file}"
        sha256sum < "${home}/${file}" || return 1
    done
}

assert_canary_clean() {
    local root="$1" label="$2"
    if [[ -s "${root}/canary.log" ]]; then
        fail "${label}: no client, git or network command invoked: $(cat "${root}/canary.log")"
    else
        pass "${label}: no client, git or network command invoked"
    fi
}

# assert_managed_copies <home> <label> — destinations are discovered from the
# markers setup wrote (not re-declared here). Every discovered destination
# must hold an exact, marked copy of every shared skill, except the foreign
# same-name directory, which must stay unmanaged; the anchors must be among them.
assert_managed_copies() {
    local home="$1" label="$2" src_root="${1}/ai-wrapper/.agents/skills"
    local marker dst name dest bad="" anchor
    local -a dsts=()
    while IFS= read -r marker; do
        dst="$(dirname "$(dirname "${marker}")")"
        [[ " ${dsts[*]} " == *" ${dst} "* ]] || dsts+=("${dst}")
    done < <(find "${home}" -path "${home}/ai-wrapper" -prune -o -name "${MARKER}" -print | LC_ALL=C sort)

    for anchor in "${ANCHOR_DSTS[@]}"; do
        [[ " ${dsts[*]} " == *" ${home}/${anchor} "* ]] || bad+=" missing-destination:${anchor}"
    done
    for dst in "${dsts[@]}"; do
        for name in "${PINNED_SKILLS[@]}"; do
            dest="${dst}/${name}"
            if [[ "${dest}" == "${home}/${FOREIGN_SKILL_DIR}" && -e "${home}/${FOREIGN_SKILL_DIR}/SKILL.md" ]]; then
                [[ -e "${dest}/${MARKER}" ]] && bad+=" foreign-managed:${dest#"${home}"/}"
                continue
            fi
            if ! diff -r --exclude="${MARKER}" -- "${src_root}/${name}" "${dest}" > /dev/null 2>&1; then
                bad+=" not-exact:${dest#"${home}"/}"
            elif [[ "$(cat -- "${dest}/${MARKER}" 2> /dev/null)" != "${src_root}/${name}" ]]; then
                bad+=" bad-marker:${dest#"${home}"/}"
            fi
        done
    done
    if [[ -z "${bad}" ]]; then
        pass "${label}: ${#PINNED_SKILLS[@]} shared skills copied to ${#dsts[@]} destinations"
    else
        fail "${label}: managed copies wrong:${bad}"
    fi
}

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

# Parent installer -> chezmoi apply into ${HOME}/ai-wrapper -> pinned hook ->
# setup: skills reach the client roots; user data and settings are untouched.
test_install_chain_distributes() {
    local root home before after calls
    root="$(make_fixture chain)" || { fail "chain: fixture prepared"; return; }
    home="${root}/home"
    before="$(snapshot_sentinels "${home}")" || { fail "chain: sentinel snapshot"; return; }

    run_installer "${root}"
    assert_status 0 "${RUN_STATUS}" "chain: parent installer exits 0"
    assert_not_contains "${RUN_STDERR}" "WARNING" "chain: hook found setup_skills.bash under the parent destination"
    assert_not_contains "${RUN_STDERR}" "ERROR" "chain: no setup error"
    calls="$(wc -l < "${root}/chezmoi.log" 2> /dev/null || echo 0)"
    assert_eq 1 "${calls// /}" "chain: chezmoi called once (hook and setup never call it)"

    assert_managed_copies "${home}" "chain"
    if [[ -f "${home}/.claude/skills/caveman/SKILL.md" && -f "${home}/.claude/skills/ponytail/SKILL.md" ]]; then
        pass "chain: caveman and ponytail present in ~/.claude/skills"
    else
        fail "chain: caveman and ponytail present in ~/.claude/skills"
    fi
    if [[ -e "${home}/.cursor" ]]; then
        fail "chain: retired Cursor root ~/.cursor not created"
    else
        pass "chain: retired Cursor root ~/.cursor not created"
    fi
    after="$(snapshot_sentinels "${home}")"
    assert_eq "${before}" "${after}" "chain: plugins.json, settings, user and foreign skills unchanged"
    assert_canary_clean "${root}" "chain"
}

# A HOME without client state gets skills but no Claude settings files.
test_fresh_home_creates_no_settings() {
    local root home found
    root="$(make_fixture fresh bare)" || { fail "fresh: fixture prepared"; return; }
    home="${root}/home"
    run_installer "${root}"
    assert_status 0 "${RUN_STATUS}" "fresh: parent installer exits 0"
    if [[ -f "${home}/.claude/skills/caveman/SKILL.md" ]]; then
        pass "fresh: ~/.claude/skills populated"
    else
        fail "fresh: ~/.claude/skills populated"
    fi
    found="$(find "${home}" \( -name settings.json -o -name plugins.json \) -print)"
    assert_eq "" "${found}" "fresh: no settings.json or plugins.json created"
    assert_canary_clean "${root}" "fresh"
}

# Rerun is a no-op on the tree; local edits and stray files in managed copies
# and a source update are reconciled by the next apply.
test_rerun_and_local_edits() {
    local root home first second
    root="$(make_fixture rerun)" || { fail "rerun: fixture prepared"; return; }
    home="${root}/home"
    run_installer "${root}"
    assert_status 0 "${RUN_STATUS}" "rerun: first apply exits 0"
    first="$(snapshot_tree "${home}")"
    run_installer "${root}"
    assert_status 0 "${RUN_STATUS}" "rerun: second apply exits 0"
    second="$(snapshot_tree "${home}")"
    if [[ -n "${first}" && "${first}" == "${second}" ]]; then
        pass "rerun: type, mode and content of every path unchanged"
    else
        fail "rerun: type, mode and content of every path unchanged"
        diff <(printf '%s\n' "${first}") <(printf '%s\n' "${second}")
    fi

    printf 'local drift\n' >> "${home}/.claude/skills/ponytail/SKILL.md"
    printf 'stray\n' > "${home}/.claude/skills/ponytail/stray.txt"
    printf '\nsource update\n' >> "${root}/src/ai-wrapper/dot_agents/skills/caveman/SKILL.md"
    run_installer "${root}"
    assert_status 0 "${RUN_STATUS}" "rerun: apply after local edits exits 0"
    assert_managed_copies "${home}" "rerun: after drift and source update"
    if [[ -e "${home}/.claude/skills/ponytail/stray.txt" ]]; then
        fail "rerun: stray file removed from managed copy"
    else
        pass "rerun: stray file removed from managed copy"
    fi
    assert_file_contains "${home}/.claude-personal/skills/caveman/SKILL.md" "source update" \
        "rerun: source update reaches a named profile"
}

# A missing skill source fails setup loudly, and the failure propagates
# through the hook and chezmoi to the parent installer.
test_missing_source_fails() {
    local root home
    root="$(make_fixture missing bare)" || { fail "missing: fixture prepared"; return; }
    home="${root}/home"
    rm -rf -- "${root:?}/src/ai-wrapper/dot_agents"
    run_installer "${root}"
    assert_status nonzero "${RUN_STATUS}" "missing: parent installer fails when setup fails"
    assert_contains "${RUN_STDERR}" "skills source dir not found" "missing: setup error reaches stderr"
    if [[ -e "${home}/.claude/skills" ]]; then
        fail "missing: nothing distributed"
    else
        pass "missing: nothing distributed"
    fi
    assert_canary_clean "${root}" "missing"
}

# Lint (source text; no behavioural equivalent short of running every parent
# script): no deployable parent source manages Claude plugin settings.
lint_no_plugin_settings_writer() {
    local output status
    output="$(isolated_git -C "${REPO_ROOT}" grep -nIE \
        'plugins\.json|install-claude-plugins|enabledPlugins|extraKnownMarketplaces' \
        -- . ':(exclude)ai-wrapper' ':(exclude)docs' ':(exclude)tests' 2>&1)"
    status=$?
    case "${status}" in
        1) pass "lint: no deployable parent source manages Claude plugin settings" ;;
        0) fail "lint: deployable parent source manages Claude plugin settings: ${output}" ;;
        *) fail "lint: parent source search failed: ${output}" ;;
    esac
}

# ---------------------------------------------------------------------------

main() {
    local status name
    require_cmd "skill distribution" git tar find sha256sum diff || tests_finish
    lint_no_plugin_settings_writer

    extract_pinned_tree
    status=$?
    case "${status}" in
        0) ;;
        2) skip "skill distribution: pinned AI-Wrapper objects unavailable (${PIN_REASON})"; tests_finish ;;
        *) fail "skill distribution: pinned AI-Wrapper extracted (${PIN_REASON})"; tests_finish ;;
    esac
    for name in "${PINNED_TREE}"/dot_agents/skills/*/; do
        [[ -d "${name}" ]] && PINNED_SKILLS+=("$(basename "${name}")")
    done
    if [[ " ${PINNED_SKILLS[*]} " != *" caveman "* || " ${PINNED_SKILLS[*]} " != *" ponytail "* ]]; then
        fail "pinned AI-Wrapper ships caveman and ponytail (found: ${PINNED_SKILLS[*]})"
        tests_finish
    fi

    test_install_chain_distributes
    test_fresh_home_creates_no_settings
    test_rerun_and_local_edits
    test_missing_source_fails
    tests_finish
}

main
