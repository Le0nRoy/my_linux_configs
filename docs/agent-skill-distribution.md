# Agent Skill Distribution (caveman, ponytail)

This repository does not install agent skills or plugins itself. The shared
skills, `caveman` and `ponytail` among them, come from the `ai-wrapper`
submodule's existing distribution pipeline. Issue #58 retired the redundant
parent installer `run_always_install-claude-plugins.bash`.

## Evidence baseline

| Item | Value |
|------|-------|
| Parent commit researched | `bd8ac4e77cad4f89bb1b29bfabd0e1622fc4424e` (`agent/feature-55`) |
| Pinned AI-Wrapper gitlink | `db66133af5c94fff51a6984db2cb7ba85adcb03c` |
| Dependency source inspected | clean read-only checkout of exactly the gitlink commit (not the parent's older `docs/ai-agent-sandboxing.md`) |
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
| Claude Code (`claude_wrapper`) | Native skill dir (`SKILL.md`) | `~/.claude/skills/`; named profiles `~/.claude-<name>/skills/` | Default dir or the selected profile is bound RW at `~/.claude` | AI-Wrapper `setup_skills.bash` | Fixture: copy, marker, rerun, refresh, foreign skip |
| Codex CLI (`codex_wrapper`) | Native skill dir | `~/.codex/skills/`; `~/.codex-<name>/skills/` | Default dir or profile bound RW at `~/.codex` | same | same |
| Antigravity CLI `agy` (`agy_wrapper`) | Native skill dir | `~/.gemini/config/skills/`; `~/.gemini-<name>/config/skills/` | Default dir or profile bound RW at `~/.gemini` | same | same |
| GitHub Copilot CLI (`copilot_wrapper`) | Native skill dir | `~/.copilot/skills/` (no named profiles in setup) | `~/.copilot` bound RW | same | same |
| Cursor Agent (`cursor_agent_wrapper`) | Native skill dir | `~/.cursor/skills/` | `~/.cursor` bound RW | same | Copy observed in fixture only. **Coverage exception**: Cursor retirement is parked under Le0nRoy/AI-Wrapper#43; no Cursor change or coverage claim is made here |
| Hermes | `skills.external_dirs` -> `~/.agents/skills` (per pinned README) | none (host alias, not written by setup) | n/a | host configuration | Not verified; outside parent scope |

Optional Claude marketplace plugins are a separate mechanism. They live in
`~/.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`), as the
official Claude Code plugin docs describe. Claude Code does not document
`~/.claude/plugins.json` as a settings file. The retired parent script wrote
only that legacy file and never touched `settings.json`. Nothing in the parent
now writes either file. Existing host files are kept as they are: no cleanup,
no migration, and no change to enablement policy.

## What is and is not proven

`tests/test_agent_skill_distribution.bash` runs the pinned hook and
`setup_skills.bash`, unmodified, against a synthetic HOME/XDG. Every client,
`chezmoi`, `git` and network command in that run is a trap. The test proves:

- On a fresh run, both skills reach all 8 fixture destinations: 5 default
  roots and 3 named profiles.
- A rerun gives the same counts and leaves the type, mode and content of
  every path unchanged.
- Managed copies are refreshed after local drift or a source update, and
  stray files in them are removed.
- A foreign same-name skill, a user skill, a legacy `plugins.json` and
  settings files in each client root stay byte-identical.
- A fresh HOME gets no `plugins.json` or `settings.json`.
- A missing skill source fails the run. The pinned hook only warns when
  `setup_skills.bash` itself is absent; that warn-only behavior is pinned
  dependency behavior and was not changed.

Not proven:

- **Activation.** A skill being present and discoverable does not mean a
  running client loads or activates it. No client was started.
- **macOS.** Only the Linux path was exercised; the `sandbox-exec` backend was
  not.
- **The rsync path.** It is exercised only on hosts that have rsync. Without
  rsync the test prints an explicit `SKIP` and runs only the `cp` fallback.
- **Duplicate injection.** Whether a marketplace plugin and a skill copy of the
  same name load twice in one client was not reproduced.

## Running the test

The test needs a clean checkout of the exact pinned commit. It uses the
`ai-wrapper` submodule when that is initialized, or an explicit read-only
checkout given as input:

```bash
AI_WRAPPER_PINNED_SRC=/path/to/ai-wrapper-at-pin bash tests/test_agent_skill_distribution.bash
```

A missing, dirty or mismatched input fails the run; it is never skipped.
