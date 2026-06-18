# AI Agent Rules — Chezmoi Dotfiles

These rules apply to AI agents working in this repository.

> **Note:** This file covers only the `chezmoi-dotfiles` repository (Linux/system configs).
> Additional AI rules may be provided by submodules (e.g. `ai-wrapper`) applied as secondary chezmoi sources.

---

## This Repository

This is a **chezmoi-managed Linux system configuration** repository:
- Shell configs: `dot_bashrc`, `dot_bash_profile`, `dot_zshrc`
- Editor: `dot_vimrc`, `dot_gitconfig`
- Window manager: `dot_config/i3/`
- Status bar: `dot_config/polybar/`
- Terminal: `dot_config/alacritty/`
- Multiplexer: `dot_config/tmux/`
- Display management: `bin/executable_xrandr_manager.bash`
- Systemd user services: `dot_config/systemd/user/`
- System utilities: `bin/executable_*.bash`, `bin/helper/`

---

## Chezmoi Workflow

Always use `chezmoi diff` before `chezmoi apply`. Changes in this repo don't deploy until `chezmoi apply` runs.

File naming conventions matter:
- `dot_` → deploys as `.<name>` under `~/`
- `executable_` → deployed with execute bit set
- `private_` → deployed with mode 0600
- `.tmpl` → processed as a Go template before deployment
- `run_once_` → runs once on `chezmoi apply`, tracked by chezmoi
- `run_always_` → runs on every `chezmoi apply`

---

## Submodule Extensibility

This repo supports additional tool layers via git submodules applied as secondary chezmoi sources.
Currently: the `ai-wrapper` submodule installs AI orchestration tools by running:

```bash
CHEZMOI_SOURCE_DIR="${CHEZMOI_SOURCE_DIR}/ai-wrapper" chezmoi apply
```

Future submodules follow the same pattern — add to `.gitmodules`, add a `run_always_` script.

---

## Minimal Rules

1. Never commit secrets, credentials, API keys, or tokens.
2. Read files before modifying them.
3. Check `git status` at the start of every session.
4. Ask before destructive operations (`rm -rf`, `git reset --hard`).
5. Validate bash syntax before completing tasks: `bash -n script.bash`
6. Never commit directly to `main` — use feature branches (`feat/`, `fix/`, `chore/`).
