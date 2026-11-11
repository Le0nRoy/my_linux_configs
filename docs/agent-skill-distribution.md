# Agent Skill Distribution (caveman, ponytail)

This repository does not install agent skills or plugins itself. The shared
skills, `caveman` and `ponytail` among them, come from the `ai-wrapper`
submodule's existing distribution pipeline. Issue #58 retired the redundant
parent installer `run_always_install-claude-plugins.bash`.

## Evidence baseline

| Item | Value |
|------|-------|
| Parent commit researched | `bd8ac4e77cad4f89bb1b29bfabd0e1622fc4424e` (`agent/feature-55`) |
| Pinned AI-Wrapper | the commit pinned by the parent `ai-wrapper` gitlink (`git ls-tree HEAD ai-wrapper`); no SHA is hardcoded here |
| Dependency source inspected | that commit, read from the submodule's git objects (not its working tree, and not the parent's older `docs/ai-agent-sandboxing.md`) |
| Skill provenance (pinned `UPSTREAM.md`) | caveman: `JuliusBrussee/caveman@1f951fb4`; ponytail: `DietrichGebert/ponytail@09c434ab`; both vendored with adaptations, no plugin hooks |

## Pipeline

1. Parent `run_always_install-ai-wrapper.bash` applies the submodule as a
   secondary chezmoi source with `--destination "${HOME}/ai-wrapper"`.
   This deploys `dot_agents/skills/` to `~/ai-wrapper/.agents/skills/` and
   `bin/executable_setup_skills.bash` to `~/ai-wrapper/bin/setup_skills.bash`.
2. The submodule's `run_after_register-agent-skills.bash` runs in chezmoi's
   after phase of that apply and calls `~/ai-wrapper/bin/setup_skills.bash`.
3. `setup_skills.bash` copies every shared skill into each client's native
   skill directory. Each copy gets a `.setup_skills_managed` marker that
   records its source path.

Ownership rules in the pinned setup:

- A copy whose marker names the source is refreshed in place on every run,
  with `rsync --delete` or a `cp` swap when rsync is missing.
- An unmanaged directory, symlink or file with the same name is skipped
  unless `--force` is passed. The parent never passes `--force`.
- Skills with other names are left alone.
- Settings files are never read or written, including `~/.claude/settings.json`
  and a leftover `~/.claude/plugins.json`.

## Agent / profile matrix

| Agent (wrapper) | Mechanism | Destination written by setup | Sandbox visibility (pinned wrapper) | Owner | Verification in this repo |
|---|---|---|---|---|---|
| Claude Code (`claude_wrapper`) | Native skill dir (`SKILL.md`) | `~/.claude/skills/`; named profiles `~/.claude-<name>/skills/` | Default dir or the selected profile is bound RW at `~/.claude` | AI-Wrapper `setup_skills.bash` | Per-destination behaviour: AI-Wrapper `tests/test_setup_skills.bash`. Parent fixture: default root and a named profile get marked copies |
| Codex CLI (`codex_wrapper`) | Native skill dir | `~/.codex/skills/`; `~/.codex-<name>/skills/` | Default dir or profile bound RW at `~/.codex` | same | same |
| Antigravity CLI `agy` (`agy_wrapper`) | Native skill dir | `~/.gemini/config/skills/`; `~/.gemini-<name>/config/skills/` | Default dir or profile bound RW at `~/.gemini` | same | same |
| GitHub Copilot CLI (`copilot_wrapper`) | Native skill dir | `~/.copilot/skills/` (no named profiles in setup) | `~/.copilot` bound RW | same | same |
| Cursor Agent (`cursor_agent_wrapper`) | **Retired** (Le0nRoy/AI-Wrapper#43) | none: setup no longer writes `~/.cursor/skills/` | n/a | AI-Wrapper | Fixture asserts `~/.cursor` is not created |
| Hermes | `skills.external_dirs` -> `~/.agents/skills` (per pinned README) | none (host alias, not written by setup) | n/a | host configuration | Not verified; outside parent scope |

Optional Claude marketplace plugins are a separate mechanism. They live in
`~/.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`), as the
official Claude Code plugin docs describe. Claude Code does not document
`~/.claude/plugins.json` as a settings file. The retired parent script wrote
only that legacy file and never touched `settings.json`. Nothing in the parent
now writes either file. Existing host files are kept as they are: no cleanup,
no migration, and no change to enablement policy.

## What is and is not proven

`tests/test_agent_skill_distribution.bash` covers only what the parent adds.
It runs the parent's `run_always_install-ai-wrapper.bash` against a synthetic
HOME/XDG with `env -i`. `chezmoi` is a fake that deploys only what the skill
hook needs into the `--destination` the installer passes, then runs the pinned
`run_after_register-agent-skills.bash` as chezmoi's after phase would. Every
agent client, `git` and network command is a trap. The test proves:

- The chain installer -> `chezmoi apply --destination "${HOME}/ai-wrapper"` ->
  pinned hook -> pinned `setup_skills.bash` delivers every shared skill,
  caveman and ponytail included. Destinations are found from the markers setup
  writes; each must hold an exact copy of every shared skill. `~/.claude/skills`
  and the named profile `~/.claude-personal/skills` must be among them.
- `~/.cursor` is not created.
- A foreign same-name skill, a user skill, a legacy `plugins.json` and the
  settings files in each client root stay byte-identical. A fresh HOME gets no
  `plugins.json` or `settings.json`.
- A rerun leaves the type, mode and content of every path unchanged. Local
  edits and stray files in a managed copy are reverted, and a source update
  reaches every copy, a named profile included.
- A missing skill source fails setup loudly, and the failure propagates
  through the hook and chezmoi to the parent installer.
- No client, `git` or network command runs, and chezmoi is called once.
- Lint (source text): no deployable parent source references Claude plugin
  settings.

The full list of destinations, the rsync and `cp` paths, retirement and
Cursor are AI-Wrapper's own coverage (`tests/test_setup_skills.bash`).

Not proven:

- **Activation.** A skill being present and discoverable does not mean a
  running client loads or activates it. No client was started.
- **Real chezmoi.** The fake deploys only the skill files and setup script and
  runs only the skill hook. It does not check chezmoi's script ordering.
- **macOS.** Only the Linux path was exercised; the `sandbox-exec` backend was
  not.
- **Duplicate injection.** Whether a marketplace plugin and a skill copy of the
  same name load twice in one client was not reproduced.

## Running the test

```bash
bash tests/test_agent_skill_distribution.bash
TESTS_STRICT=1 bash tests/test_agent_skill_distribution.bash   # as CI
```

The test reads the pinned commit from `git ls-tree HEAD ai-wrapper` and
extracts it with `git -C ai-wrapper archive <pin> | tar -x` into a temporary
directory. The submodule working tree is not used, so its branch and local
changes do not matter. If the submodule is not initialised or the pinned
commit is not in its object store, the run records a `SKIP` locally and fails
under `CI` or `TESTS_STRICT=1`. Fetch the pin to fix it:
`git submodule update --init ai-wrapper`.
