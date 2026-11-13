---
name: chezmoi-workflow
description: Use when adding, renaming, or changing any managed file in this chezmoi dotfiles repo (dot_*, bin/, run_* scripts, *.tmpl, modify_*, .chezmoiignore, systemd units, LaunchAgents, the ai-wrapper submodule), or when checking what a change will deploy.
---

# Chezmoi workflow — this dotfiles repo

The repo root is the chezmoi source dir (`~/.local/share/chezmoi`). Nothing
deploys until `chezmoi apply` runs. Upstream chezmoi ships no agent skill (as
of twpayne/chezmoi `b638b01`); general reference: https://www.chezmoi.io/reference/.

## Hard rules for agents

1. **Never run `chezmoi apply`** (or `update`, `init --apply`) unless the user
   asks. It runs `run_*` scripts, restarts services and edits `$HOME`.
2. **Never run `chezmoi add` / `re-add` / `edit` / `chattr`** to change
   sources. `~/.config/chezmoi/chezmoi.toml` sets `git.autoCommit` and
   `git.autoPush`, so they commit and push behind your back. Edit the source
   files directly and commit with git yourself. (`re-add` on a `.tmpl` also
   replaces template syntax with rendered text.)
3. Always pass `-S .` (`--source`) when inspecting from a worktree or
   checkout; without it chezmoi reads `~/.local/share/chezmoi`.

## Source naming used here

| Prefix / suffix | Effect | Examples |
|---|---|---|
| `dot_` | `.name` in `$HOME` | `dot_bashrc`, `dot_config/`, `dot_local/` |
| (none) | same name | `bin/` → `~/bin/`, `Library/` → `~/Library/` |
| `executable_` | mode +x, prefix dropped | `bin/executable_helper.bash` → `~/bin/helper.bash` |
| `private_` | mode 0600/0700 | `dot_config/private_gtk-3.0/`, `private_mimeapps.list` |
| `.tmpl` | Go template, suffix dropped | `dot_config/i3/config.tmpl`, `tmux.conf.tmpl` |
| `modify_` | script: current target on stdin, new content on stdout | `modify_dot_gitconfig`, `bin/modify_dot_env.tmpl`, `dot_config/keepassxc/modify_keepassxc.ini` |
| `run_once_` | runs once per content hash | `run_once_install-tpm-plugins.bash` |
| `run_onchange_` | re-runs when rendered content changes | `run_onchange_enable-tmux-service.bash.tmpl` |
| `run_always_` | every apply | `run_always_install-ai-wrapper.bash`, `run_always_setup-git-hooks.bash` |

No `symlink_`, `create_`, `encrypted_` or `.chezmoiexternal` entries exist.
Files in `bin/helper/` are sourced, not executed, so they carry no
`executable_` prefix. `modify_` scripts are for files that tools or the user
also write (gitconfig, `~/bin/.env`, keepassxc.ini): they own a fixed set of
keys and pass everything else through. Use them instead of a plain file when
the target is shared.

`run_onchange_` scripts embed a hash of what they depend on so they re-run
when it changes, e.g. `{{ include "dot_config/systemd/user/tmux.service" | sha256sum }}`.

## Template data

Only built-ins plus one custom key are used:

- `.chezmoi.os` (`linux` / `darwin`), `.chezmoi.hostname` (`dragonlady`,
  `dragoncave`), `.chezmoi.homeDir`, `.chezmoi.sourceDir`
- `.localSymlinkTarget` — set in `[data]` of the generated config; guard with
  `hasKey . "localSymlinkTarget"`.

Config: `dot_config/chezmoi/chezmoi.toml.tmpl` deploys
`~/.config/chezmoi/chezmoi.toml` (no `.chezmoi.toml.tmpl` init template, no
`.chezmoidata`). Host-specific data goes there behind a hostname check.

## OS-conditional files

- `.chezmoiignore` is a template: macOS skips Linux-only configs and the five
  Linux-only `bin/helper` modules; Linux skips `Library/**`; keepassxc is
  skipped until its ini exists; `.local` is skipped when `localSymlinkTarget`
  is set. It also excludes repo-only paths: `.claude`, `tests/`, `docs/`,
  `TODO.md`, `ai-wrapper`, `worktrees/`.
- `.chezmoiignore` does not gate `run_` scripts. OS-specific scripts wrap
  their whole body in `{{ if eq .chezmoi.os "linux" }}` (systemd) or
  `"darwin"` (LaunchAgent). Write `{{ "{{" }}` inside comments to keep a
  literal `{{`.
- A new Linux-only target must be added to the darwin block of
  `.chezmoiignore` (and vice versa).

## Services

- systemd user units: `dot_config/systemd/user/*.service|*.timer` (plain
  files). Enabling them is done by a `run_onchange_` script, never on deploy
  alone; see `run_onchange_enable-tmux-service.bash.tmpl` (daemon-reload,
  enable, start only if not running).
- macOS: `Library/LaunchAgents/local.tmux.plist.tmpl` plus
  `run_onchange_load-tmux-launchagent.bash.tmpl`.
- Both start `~/bin/tmux_boot.bash`, so changes there affect both OSes and
  the script must stay Bash 3.2 compatible.

## Sub-sources

- `ai-wrapper` is a git submodule (HTTPS URL; CI rejects SSH). It is ignored
  by the main source and applied by `run_always_install-ai-wrapper.bash` as
  `chezmoi apply --source ai-wrapper --destination ~/ai-wrapper
  --persistent-state ~/.cache/chezmoi/ai-wrapper-state.boltdb` (separate
  state file, or the nested apply deadlocks on the lock). It has its own
  AGENTS.md and tests. Change it upstream and bump the gitlink in a
  `chore(#N): bump ai-wrapper to <sha>` commit; never stage a dirty submodule
  you did not change.
- `run_always_manage-local-symlink.bash.tmpl` applies `dot_local/` onto
  `localSymlinkTarget` the same way when `~/.local` is a symlink.
- `run_always_setup-git-hooks.bash` installs a pre-commit hook that blocks
  commits on `main`/`master`.

## Verifying a change (read-only)

```bash
chezmoi -S . managed | grep <path>                  # is it deployed? where?
chezmoi -S . cat ~/bin/.env                         # rendered target content
chezmoi -S . execute-template < dot_config/i3/config.tmpl
echo '{{ .chezmoi.os }}' | chezmoi -S . execute-template \
    --override-data '{"chezmoi":{"os":"darwin"}}'   # try another OS/host
chezmoi -S . execute-template < .chezmoiignore      # what is ignored here
chezmoi -S . diff --exclude=scripts                 # what apply would change
bash -n <script>; shellcheck -x -S warning <script> # validate.yml runs both
```

`diff` and `cat` run `modify_` scripts (they must stay side-effect free) but
never `run_` scripts. After adding repo-only files, confirm
`chezmoi -S . managed | grep -c <dir>` is 0.

## Tests and CI

Tests live in `tests/` and are not deployed. Rules and commands:
`qa-automation` skill (`.claude/skills/qa-automation/SKILL.md`). CI:
`.github/workflows/validate.yml` (`bash -n`, shellcheck at warning level,
HTTPS submodule check, chezmoi.toml check) and `tests.yml`.

## Checklist for a new managed file

1. Pick the source name (prefixes above); `.tmpl` only if it uses data.
2. OS/host specific? Add to `.chezmoiignore` or guard inside the template.
3. Needs activation (service, plugin)? Add a `run_onchange_` script that
   hashes its input; make it idempotent and OS-guarded.
4. Verify with `managed`, `cat`, `diff` as above; never `apply`.
5. Update `AGENTS.md`/`CLAUDE.md` overview lists if a new area appears.
