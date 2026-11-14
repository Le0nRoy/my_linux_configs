---
name: coding-standards
description: Use when writing or reviewing Bash, Zsh or Python code in this chezmoi dotfiles repo (bin/, bin/helper/, run_* scripts, modify_* scripts, shell rc files), adding or changing a public hh_* helper, or writing a commit message here.
---

# Coding standards — chezmoi dotfiles

Derived from the existing code (`bin/`, `bin/helper/`, `run_*`, `modify_*`)
and `AGENTS.md`. Chezmoi naming and deployment: `chezmoi-workflow` skill.
Tests: `qa-automation` skill.

## Bash scripts (executed)

- Shebang `#!/bin/bash`; header comment saying what the script does, why it
  exists, and any non-obvious constraint (see `modify_dot_gitconfig`,
  `run_always_install-ai-wrapper.bash`).
- `set -euo pipefail` near the top of every executed script (`run_*`,
  `modify_*`, `bin/executable_*.bash`).
- Quote every expansion with braces: `"${var}"`, `"$@"`. Use `[[ ]]`, not
  `[ ]`. `local` for every function variable; split `local x; x="$(cmd)"`
  when the status of `cmd` matters.
- Errors to stderr (`>&2`), with a prefix naming the function or script, plus
  how to fix it when useful.
- Comments explain *why* (traps, chezmoi quirks, OS differences), e.g. the
  `--persistent-state` deadlock note. No commented-out code.
- `run_*` scripts are idempotent: check before writing (see the hook guard in
  `run_always_setup-git-hooks.bash`), never restart a running service that
  holds user state.
- `modify_*` scripts read stdin, write the full target to stdout, have no
  other side effects, and pass through anything they do not own. If a needed
  tool is missing, pass the input through unchanged with a stderr warning;
  never emit an empty file.
- Use `mktemp` + `trap ... EXIT` for temp files; never fixed `/tmp` names.

## Sourced helpers (`bin/helper/*.bash`, `*.zsh`, `aliases.shrc`, rc files)

- Never `set -e`/`-u`/`-o pipefail` at file or function level: it would
  change the user's interactive shell.
- Public helpers never `exit`; they `return` a non-zero status and print
  `hh_name: <reason>` to stderr. `exit` is only acceptable in script-private
  modules that load only when `helper.bash` runs as a command.
- Do not change caller state (cwd, options, traps, globals) unless that is
  the helper's job (`hh_gio_mount` changes cwd, and only on success). Use
  subshells `( ... )` to isolate.
- A helper that runs several steps keeps going and returns the first failure
  (see `hh_git_cleanout`), unless a later step depends on an earlier one.
- Missing modules are skipped (`[[ -f ... ]] && source ...`) so macOS, where
  Linux-only modules are not deployed, still loads.

## Public `hh_*` helper API

- Interactive shells see only `hh_*` functions and the `hh_cp_ssh` alias.
  Internals use a `_` prefix (`_i3_*`, `_tmux_*`) or stay script-private
  (loaded only in script mode by `bin/executable_helper.bash`).
- Bash/Zsh parity is required. In `dot_zshrc` a module is either sourced
  in-process (portable code, or it must change caller cwd) or wrapped in
  `bin/helper/bash_exec.zsh`, which runs the unchanged module in a child
  `bash -c` with the shared aliases. Code sourced into zsh keeps to the
  common subset (no `$status`, no `mapfile`, no Bash-only expansions).
- Adding, renaming or removing a public helper means updating, in one
  change: the module, `helper.bash`'s interactive module list or the
  `hh_i3_*` wrappers if needed, `dot_zshrc` / `bash_exec.zsh`, completion
  (`dot_bash_completion.d/`, zsh `compdef` in `dot_zshrc`), the function list
  in `bin/helper/README.md`, and `tests/test_hh_public_api.bash`.
- Linux-only modules (`firefox`, `i3`, `storage`, `system`, `utils`) must be
  listed in the darwin block of `.chezmoiignore`.

## Portability

- Anything that runs on macOS (`tmux_boot.bash`,
  `tmux_bootstrap_cleanup.bash`, `tmux_resurrect_save_filter.bash`, portable
  `bin/helper` modules, rc files) must work with `/bin/bash` 3.2: no
  associative arrays, `mapfile`, `${var,,}`, `;&`, `declare -n`, `|&`,
  negative array indices or `wait -n`. Mark such files with a
  "Bash 3.2 compatible (macOS /bin/bash)" comment; the `bash32` section of
  `tests/test_tmux_preservation.bash` checks them.
- No GNU-only flags in macOS paths (`sed -i` without a suffix argument,
  `date -d`, `stat -c`, `grep -P`); prefer `/proc` with an `lsof` fallback, as the
  resurrect filter does. launchd/systemd PATH is minimal: use full paths or
  extend PATH for tools like `lsof` (`/usr/sbin`).

## Python

Only `bin/executable_tmux_osc52_pbcopy.py`: `#!/usr/bin/env python3`, stdlib
only, header comment, module-level constants in UPPER_CASE, bytes-safe
streaming I/O. Tests run Python with `python3 -I` (`tests/pty_drive.py`).

## Validation (CI: `.github/workflows/validate.yml`)

```bash
bash -n <file>                       # every *.bash / *.sh
shellcheck -x -S warning <file>      # CI fails on warnings
zsh -n dot_zshrc bin/helper/*.zsh    # zsh files
```

Silence a shellcheck finding only with a targeted
`# shellcheck disable=SCxxxx` or `# shellcheck source=...` on the line
above, with a reason when it is not obvious. `.tmpl` scripts are not
shellchecked by CI: render with `chezmoi -S . execute-template < file` and
check the output.

## Commits

- Branches: never `main` (a pre-commit hook blocks it). Use `feat/`, `fix/`,
  `chore/` or the task branch you were given.
- Subject: `type(#issue): imperative summary`, lower case, no period.
  Types used: `feat`, `fix`, `refactor`, `test`, `ci`, `docs`, `chore`.
  Example: `fix(#55): stop pane lookups trusting tmux display-message for gone panes`.
- One logical change per commit; code, docs and tests that belong together
  go together. Bump `ai-wrapper` in its own `chore` commit.
- Never commit secrets, tokens or machine-local data.
