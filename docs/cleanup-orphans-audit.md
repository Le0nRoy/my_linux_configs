# Cleanup Orphan Audit and Regression Evidence (#62)

Final report for work package **H** of the configuration cleanup (#55). It
reconciles two orphan groups against the integrated revision and records
the regression evidence actually collected for it.

This report is **evidence only**. It does not remove anything, does not
approve any removal, and does not certify what is installed on any host.
Host installation checks belong to the owner-controlled host session **G**;
application removal belongs to session **B**. Final integration (PR #63)
stays unmerged pending owner acceptance.

## Contents

1. [Target, scope and method](#1-target-scope-and-method)
2. [Coverage accounting](#2-coverage-accounting)
3. [Orphan group 1 — configurations without an executable](#3-orphan-group-1--configurations-without-an-executable)
4. [Orphan group 2 — functions and variables without callers](#4-orphan-group-2--functions-and-variables-without-callers)
5. [Regression evidence](#5-regression-evidence)
6. [Non-orphan risk context (disclosure only)](#6-non-orphan-risk-context-disclosure-only)
7. [Owner-host handoff (sessions B and G)](#7-owner-host-handoff-sessions-b-and-g)
8. [Audit limitations](#8-audit-limitations)
- [Appendix A — production definition manifest](#appendix-a--production-definition-manifest)
- [Appendix B — tracked path manifest](#appendix-b--tracked-path-manifest)

---

## 1. Target, scope and method

| Item | Value |
|------|-------|
| Inspected revision | `agent/feature-55` at `dc61d97790543a4a323ce2a6fee0332f158e0eb5` (squash merge of PR #68) |
| PR #68 source head | `d170491` — **not available** in this checkout. Its evidence is inherited, never re-attributed to `dc61d977` |
| This report's tested head | The docs-only commit(s) on top of `dc61d977`. `git diff --stat dc61d977 HEAD` touches only `docs/`, so every production and test file was byte-identical to `dc61d977` when §5 was run (historical; see the next row) |
| Later refresh | **2026-11-14**, working tree at `c2d2a00` (`agent/feature-55-followups`). Every `file:line` citation in §3, §4, §6 and Appendix A was re-checked against that tree with a script: Appendix A definition lines and references were recomputed with the method in this section, and every other citation was checked against the construct it names. Stale lines were updated, mostly from the EasyEffects merge (#70: `bin/executable_polybar_volume_all.bash`, `dot_config/i3/config.tmpl`) and #55 follow-ups (`bin/helper/*`, `dot_config/tmux/tmux.conf.tmpl`, `bin/executable_tmux_boot.bash`). Earlier refresh (also against the working tree): the `hh_ex` → `hh_unar` rename (c5e4b6a) and `hh_sshfsctl` becoming a wrapper that launches `~/bin/sshfs.bash` (046cb3f; its old systemctl body was retired). §6.1 was fixed by 9452b3b. **Not re-inventoried:** paths and definitions added after `dc61d977` (Appendix A.1, Appendix B note) and new associations such as the EasyEffects autostart (`dot_config/i3/config.tmpl:121`) and the bootstrap cleanup / save filter tmux hooks (`dot_config/tmux/tmux.conf.tmpl:217,221`). Counts in §1–§4 still describe `dc61d977`. §2, §5 and Appendix B are historical `dc61d977` snapshots |
| Inspection date | **2026-11-05** (this audit). Any other dates are labelled *historical last change* (`git log -1`) and are not inspection dates |
| AI-Wrapper submodule | gitlink `db66133af5c94fff51a6984db2cb7ba85adcb03c` unchanged and not traversed. A separate clean clone at that SHA was used only as `AI_WRAPPER_PINNED_SRC` input for the existing distribution test (§5.1) |
| Not read | Live host files, `/Data/Job`, `~/bin/.env`, secrets, installed tmux plugins, host package managers |

**Method.** Every candidate below comes from reading tracked source at the
target revision, plus these bounded scans:

- **Path accounting:** `git ls-tree -r HEAD` (131 entries), with a role and
  disposition for each path (Appendix B).
- **Shell definitions:** an anchored scan,
  `^[[:space:]]*(function[[:space:]]+)?NAME[[:space:]]*\(\)[[:space:]]*[{(]`,
  over the 105 tracked paths that are not tests, Markdown or the gitlink.
  The scan found 202 hits. Two of those are AWK `function flush()`
  definitions inside `awk '…'` programs, not shell. One shell definition
  uses `name ()` with `{` on the next line (`hh_unar`), which the scan misses,
  so it was added by hand. Python `def` and Vimscript `function!`
  definitions were also added by hand. Result: 206 definitions in
  Appendix A.
- **Caller references:** a whole-word search of the same 105 paths with
  comment lines and the defining line removed. References inside a
  function's own body do not count as callers. For standalone
  `bin/executable_*` scripts and `modify_dot_gitconfig`, only same-file
  references count, because cross-file hits for names like `main` are
  coincidences. A reachability pass then started from top-level references
  plus public/shim interfaces and followed calls between functions. This
  is a lexical scan, not a parser: a matched word can be a usage string
  (Appendix A's header says which rows this affects). The zero- and
  self-only-reference results were then re-read by hand.
- **Unused variables:** `shellcheck -s bash -i SC2034` over every tracked
  Bash-family production file. Zsh-only files were reviewed by hand.
- **Exported variables:** every `export` in production files, followed by
  a whole-word search for consumers.

---

## 2. Coverage accounting

`git ls-tree -r HEAD` at `dc61d977` returns **131 entries**: 130 blobs and
1 gitlink.

| Role | Entries | Disposition |
|------|--------:|-------------|
| Submodule gitlink `ai-wrapper` | 1 | Excluded: not traversed |
| Markdown docs and agent rules (`*.md`) | 18 | Excluded from the orphan inventory (not deployed) |
| Tests and fixtures (`tests/**`) | 7 | Excluded from the orphan inventory; run as evidence (§5) |
| Repository/CI metadata (`.github/`, `.gitignore`, `.gitmodules`, `.chezmoiignore`) | 4 | Read; `.chezmoiignore` gives OS/host scope |
| `bin/executable_*` | 23 | Group 1 chains (§3.2), Group 2 definitions |
| `bin/helper/*` (non-Markdown) | 16 | Group 2 definitions and variables, tool dependencies |
| `bin/modify_dot_env.tmpl` | 1 | Group 2 variables |
| `dot_bash_completion.d/*` | 2 | Group 2 approved plumbing |
| `dot_config/systemd/user/*` | 19 | Group 1 (§3.1) |
| Other `dot_config/**` | 19 | Group 1 (§3.1, §3.3, §3.4) |
| `dot_local/**` | 6 | Group 1 desktop entries |
| `Library/**` | 1 | Group 1 macOS LaunchAgent |
| Root dotfiles and `modify_dot_gitconfig` | 7 | Groups 1 and 2 |
| `run_*` chezmoi installers | 7 | Group 1 installer interfaces (read, not executed) |
| **Total** | **131** | |

That leaves **101 production paths**: 131 minus the gitlink, 18 Markdown
files, 7 tests and 4 metadata files. Each path's role, how deeply it was
inspected, and its historical last change are in Appendix B.

**Embedded languages.** The production tree includes Python
(`bin/executable_tmux_osc52_pbcopy.py`, `dot_config/keepassxc/modify_keepassxc.ini`),
AWK programs inside shell scripts, and Vimscript (`dot_vimrc`). Python and
Vimscript definitions were enumerated by hand. AWK `function` definitions
were found by searching for indented `function NAME(` lines; only the two
in `bin/executable_polybar_volume_all.bash` exist. The modify script and
`.github/workflows/validate.yml`'s inline Python define no functions.

---

## 3. Orphan group 1 — configurations without an executable

**What was found:** 68 tracked association rows (A1–A68) in which
configuration starts or expects an external command, 23 owned-script
chains (§3.2), and the non-executing/declarative cases that cannot be
orphaned the same way (§3.3–3.4).

**Confirmed missing-executable set: unknown, pending session G.** No host
installation evidence was collected. A command missing from this runner's
container says nothing about the owner's hosts, and the repository cannot
prove what is installed. All recommendations are therefore **retain;
owner-host revalidate (G)**, except where noted. Being part of the core
desktop is a reason to retain an entry, not evidence that its executable
is installed.

Host/OS scope comes from `.chezmoiignore` and inline template guards. On
macOS, `.config/i3/**`, `.config/polybar/**`, `.config/dunst/**`,
`.config/systemd/**`, `.config/mimeapps.list`, `.xsessionrc` and the
Linux-only `bin/` scripts are ignored. `Library/**` is ignored on
non-macOS. `dragonlady` and `dragoncave` come from `{{ if eq .chezmoi.hostname … }}`
guards.

### 3.1 Executable-bearing associations

Owned targets (`~/bin/…`) are followed in §3.2. "Owned" means the target
script is tracked here; its own external dependencies are still
unverified.

| # | Source (path:line) | Expected command | Scope / guard | Recommendation |
|---|--------------------|------------------|---------------|----------------|
| A1 | `dot_config/i3/config.tmpl:31-55,76,78,94,102,147-161,166,168,256,258,263` | `bash` → owned `~/bin/helper.bash <action>` (B1) | Linux | Retain; chain in §3.2 |
| A2 | `dot_config/i3/config.tmpl:81,264,265` | owned `~/bin/i3_workspaces.bash` (B2) | Linux | Retain |
| A3 | `dot_config/i3/config.tmpl:83,85` | `i3-msg` (`append_layout`), `uname` | Linux; dragonlady / dragoncave | Retain |
| A4 | `dot_config/i3/config.tmpl:88` | `firefox` | Linux | Retain; G revalidate |
| A5 | `dot_config/i3/config.tmpl:89,144,145` | `alacritty` | Linux | Retain; G revalidate |
| A6 | `dot_config/i3/config.tmpl:145` | `/usr/bin/zsh` (absolute path) | Linux | Retain; G revalidate |
| A7 | `dot_config/i3/config.tmpl:93` | `Telegram` (autostart) | Linux; **dragonlady** | Retain in tree (other-host support; B/G owns host removal) |
| A8 | `dot_config/i3/config.tmpl:94` | `helper.bash todoist` → `find ~/Applications/ -name 'Todoist*'` | Linux; **dragonlady** | Retain in tree (B/G) |
| A9 | `dot_config/i3/config.tmpl:96` | `thunderbird` | Linux; dragonlady | Retain; G revalidate |
| A10 | `dot_config/i3/config.tmpl:98` | `qbittorrent` | Linux; dragoncave | Retain; G revalidate |
| A11 | `dot_config/i3/config.tmpl:103` | `pasystray` | Linux | Retain; G revalidate |
| A12 | `dot_config/i3/config.tmpl:106` | `cbatticon` | Linux; dragonlady | Retain; G revalidate |
| A13 | `dot_config/i3/config.tmpl:107` | `birdtray` | Linux; dragonlady | Retain; G revalidate |
| A14 | `dot_config/i3/config.tmpl:108` | `blueman-applet` | Linux; dragonlady | Retain; G revalidate |
| A15 | `dot_config/i3/config.tmpl:109` | `iwgtk` | Linux; dragonlady | Retain; G revalidate |
| A16 | `dot_config/i3/config.tmpl:112,113` | `light` | Linux; dragonlady | Retain; G revalidate |
| A17 | `dot_config/i3/config.tmpl:115` | `redshift` | Linux; dragonlady | Retain; G revalidate |
| A18 | `dot_config/i3/config.tmpl:119` | `start-pulseaudio-x11` | Linux | Retain; G revalidate |
| A19 | `dot_config/i3/config.tmpl:124` | owned `~/bin/xrandr_manager.bash` (B3) | Linux | Retain |
| A20 | `dot_config/i3/config.tmpl:127` | `inputplug` → owned `~/bin/input_device_handler.bash` (B4) | Linux | Retain; G revalidate |
| A21 | `dot_config/i3/config.tmpl:130` | `libinput-gestures-setup` | Linux | Retain; G revalidate |
| A22 | `dot_config/i3/config.tmpl:133` | `pkill`, owned `~/bin/xrandr_keymap_watcher.bash` (B5) | Linux | Retain |
| A23 | `dot_config/i3/config.tmpl:141,142` | `rofi` | Linux | Retain; G revalidate |
| A24 | `dot_config/i3/config.tmpl:155` | `pavucontrol` | Linux | Retain; G revalidate |
| A25 | `dot_config/i3/config.tmpl:163` | `keepassxc` | Linux | **Retain (protected)** |
| A26 | `dot_config/i3/config.tmpl:167` | `bash ~/.xsessionrc` (owned) | Linux | Retain |
| A27 | `dot_config/i3/config.tmpl:171` | `xsel`, `xargs`, `vlc` | Linux | Retain; G revalidate |
| A28 | `dot_config/i3/config.tmpl:173-185` | `quodlibet` (bindings; autostart at :92 is commented out) | Linux | Retain; G revalidate |
| A29 | `dot_config/i3/config.tmpl:187-192` | `flameshot` | Linux | Retain; G revalidate |
| A30 | `dot_config/i3/config.tmpl:195,196` | owned `~/bin/asusctl_rofi.bash` (B6) | Linux; dragonlady | Retain; G revalidate on ASUS hardware |
| A31 | `dot_config/i3/config.tmpl:209,210` | `notify-send` | Linux | Retain; G revalidate |
| A32 | `dot_config/i3/config.tmpl:264,265` | `systemctl reboot` / `poweroff` | Linux | Retain |
| A33 | `dot_config/polybar/config.ini.tmpl:160` | owned `~/bin/polybar_chezmoi_widget.sh` (B7) | Linux | Retain |
| A34 | `dot_config/polybar/config.ini.tmpl:165` | owned `~/bin/check_dir_usage.bash` (B8) on `/Data/Downloads/DownloadedMusic/` | Linux | Retain; G revalidate path |
| A35 | `dot_config/polybar/config.ini.tmpl:229,237` | `nvidia-smi` (has `|| echo "N/A"` fallback) | Linux; module listed only for dragonlady (`:112`) | Retain; G revalidate |
| A36 | `dot_config/polybar/config.ini.tmpl:246,254,262` | owned `~/bin/polybar_system_stats.bash` (B9) | Linux | Retain |
| A37 | `dot_config/polybar/config.ini.tmpl:312-336` | owned `~/bin/polybar_volume_all.bash` (B10) | Linux | Retain |
| A38 | `dot_config/polybar/config.ini.tmpl:307` | owned `~/bin/polybar_lang_menu.bash` (B11) | Linux | Retain |
| A39 | `dot_config/tmux/tmux.conf.tmpl:4-5,11,12,64,66,70` | `xclip` (Linux) / `pbcopy`,`pbpaste` (macOS via `:6-8`) | Linux, macOS | Retain; G revalidate |
| A40 | `dot_config/tmux/tmux.conf.tmpl:48` | `pbcopy` | macOS (`:38-61`) | Retain; G revalidate |
| A41 | `dot_config/tmux/tmux.conf.tmpl:53-55` | owned `~/bin/tmux_osc52_pbcopy.py` (B12) | macOS | Retain |
| A42 | `dot_config/tmux/tmux.conf.tmpl:60` | owned `~/bin/tmux_pipe_pane_init.bash` (B13) | macOS | Retain |
| A43 | `dot_config/tmux/tmux.conf.tmpl:141` | `ps`, `tail` (status-left) | Linux, macOS | Retain |
| A44 | `dot_config/tmux/tmux.conf.tmpl:145` | owned `~/bin/tmux_git_branch.bash` (B14) | Linux, macOS | Retain |
| A45 | `dot_config/tmux/tmux.conf.tmpl:217` | owned `~/bin/tmux_prefill_last_cmd.bash` (B15), resurrect hook (since 9452b3b it first runs `~/bin/tmux_bootstrap_cleanup.bash`, a script added after `dc61d977` and not in §3.2) | Linux, macOS | Retain |
| A46 | `dot_config/tmux/tmux.conf.tmpl:227` | owned `~/bin/tmux_pane_hist_release.bash` (B16) | Linux, macOS | Retain |
| A47 | `dot_config/tmux/tmux.conf.tmpl:243` | `~/.tmux/plugins/tpm/tpm` (installed by `run_once_install-tpm-plugins.bash`) | Linux, macOS | Retain; G revalidate plugin install |
| A48 | `dot_config/systemd/user/failure-notification@.service:7`, `success-notification@.service:7` | `/usr/bin/notify-send` (needs a notification daemon such as dunst) | Linux | Retain; G revalidate |
| A49 | `dot_config/systemd/user/rclone-{encrypt,linux,media}-cloud-bisync{,-resync}.service:10/11`, `rclone-minecraft-local-bisync{,-resync}.service:10` (8 units) | `/usr/bin/bash` → owned `helper.bash rclone_bisync` → `rclone`; `EnvironmentFile=%h/.config/environment.d/rclone-bisync.conf` | Linux | Retain; G revalidate `rclone` and remotes |
| A50 | `dot_config/systemd/user/sshfs@.service:12,13` | owned `%h/bin/sshfs-mount.sh` (B17) | Linux | Retain |
| A51 | `dot_config/systemd/user/syncthing.service:7` | `/usr/bin/syncthing` | Linux | Retain; G revalidate |
| A52 | `dot_config/systemd/user/tmux.service:8` | owned `%h/bin/tmux_boot.bash` (B18) | Linux | Retain |
| A53 | `dot_config/systemd/user/yt-mp3.service:8` | owned `%h/bin/yt_playlist_mp3.bash` (B19) | Linux | Retain |
| A54 | `Library/LaunchAgents/local.tmux.plist.tmpl:9` | owned `tmux_boot.bash` (B18) | macOS | Retain |
| A55 | `dot_local/share/applications/calculator.desktop:30` | `galculator` | Linux | Retain; G revalidate |
| A56 | `dot_local/share/applications/calendar.desktop:7` | `zenity` | Linux | Retain; G revalidate |
| A57 | `dot_local/share/applications/chromium-insecure.desktop:9,20,24` | `/usr/bin/chromium` | Linux | Retain; G revalidate |
| A58 | `dot_local/share/applications/com.uploadedlobster.peek.desktop:3` | `peek` | Linux | Retain; G revalidate |
| A59 | `dot_local/share/applications/firefox.desktop.tmpl:7,20,24,28` | owned `helper.bash firefox` (B1); `/usr/lib/firefox/firefox` (absolute path, `:28`) | Linux | Retain; G revalidate absolute path |
| A60 | `dot_local/share/applications/opera-insecure.desktop:6,7,17,22` | `opera` (`TryExec` hides the entry if missing) | Linux | Retain; G revalidate |
| A61 | `dot_config/dunst/dunstrc:229,232` | `/usr/bin/dmenu`, `/usr/bin/xdg-open` | Linux | Retain; G revalidate |
| A62 | `dot_config/libinput-gestures.conf` (6 `gesture` lines) | `i3-msg`, `rofi` | Linux | Retain |
| A63 | `dot_xsessionrc:16-27,35` | `xset`, `xinput`, `ssh-agent` | Linux | Retain |
| A64 | `dot_bashrc:50-52,70-81,119,155` | `git` (prompt), `dircolors` (guarded by `type -P`), `xhost` (unguarded; output discarded), `pyenv` (guarded by dir) | Linux, macOS | Retain; G revalidate `xhost` on macOS |
| A65 | `dot_zshrc:84-89,149` | `dircolors` (guarded), `pyenv` (guarded); `vcs_info` is built in | Linux, macOS | Retain |
| A66 | `modify_dot_gitconfig` | `git` | Linux, macOS | Retain |
| A67 | `dot_config/keepassxc/modify_keepassxc.ini:1` | `python3` (shebang) | Only where `keepassxc.ini` exists (`.chezmoiignore:32-37`) | **Retain (protected)** |
| A68 | `run_always_install-ai-wrapper.bash`, `run_always_manage-local-symlink.bash.tmpl`, `run_always_setup-git-hooks.bash`, `run_once_create_firefox_profiles.bash`, `run_once_install-tpm-plugins.bash`, `run_onchange_enable-tmux-service.bash.tmpl` (Linux guard `:1`), `run_onchange_load-tmux-launchagent.bash.tmpl` (macOS guard `:1`) | `git`, `chezmoi`, `tmux`, `systemctl`, `launchctl` | Per guard | Retain; installers were **not executed** |

**Not counted as associations:** commented lines
(`dot_config/i3/config.tmpl:74` `nvidia-settings`, `:92` `quodlibet`
autostart) and timers. The five `*.timer` units activate the `.service`
of the same name and start no executable themselves. The four
`*-resync.service` units have no timer and are started manually.

### 3.2 Owned-script chains to external tools

Each tracked `bin/executable_*` script, what invokes it, and the external
tools it calls. Tools were found by grepping each script for a fixed list
of candidate command names, so the lists may be incomplete (§8). These
tools are what host session G needs to check.

| # | Owned script | Invoked from | External tools referenced |
|---|--------------|--------------|---------------------------|
| B1 | `bin/executable_helper.bash` | A1, A8, A49, A59, B3, B4, B5, `bin/executable_firefox_rofi.bash:3`, `dot_bashrc:146` (sourced) | dispatch: `xinput`, `notify-send`, `light`, `pactl` (via `system.bash`), `setxkbmap`, `kbdd`, `dunstctl`, `i3lock`, `i3-nagbar`, `i3-msg`, `feh`, `docker`, `rclone`, `tmux`, `chezmoi`, `firejail`, `xdotool`, `rofi`, `xclip` (firefox module) |
| B2 | `bin/executable_i3_workspaces.bash` | A2 | `i3-msg`, `jq`, `sed` |
| B3 | `bin/executable_xrandr_manager.bash` | A19, B1 `screens_settings`, `bin/executable_xrandr_dmenu_test.bash:83` | `xrandr`, `rofi`/`dmenu`, `feh`, `polybar` (via supervisor) |
| B4 | `bin/executable_input_device_handler.bash` | A20 (`inputplug -c`) | `notify-send`, B1 |
| B5 | `bin/executable_xrandr_keymap_watcher.bash` | A22 | `xrandr`, B1 |
| B6 | `bin/executable_asusctl_rofi.bash` | A30 | `asusctl`, `rofi`, `notify-send` |
| B7 | `bin/executable_polybar_chezmoi_widget.sh` | A33 | `chezmoi` |
| B8 | `bin/executable_check_dir_usage.bash` | A34 | `du` |
| B9 | `bin/executable_polybar_system_stats.bash` | A36 | `sensors`, `nvidia-smi` |
| B10 | `bin/executable_polybar_volume_all.bash` | A37 | `pactl`, `rofi`, `notify-send` |
| B11 | `bin/executable_polybar_lang_menu.bash` | A38 | `rofi`, `setxkbmap`, `kbdd` |
| B12 | `bin/executable_tmux_osc52_pbcopy.py` | A41, B13 | `python3`, `pbcopy` |
| B13 | `bin/executable_tmux_pipe_pane_init.bash` | A42 | `tmux` |
| B14 | `bin/executable_tmux_git_branch.bash` | A44 | `git` |
| B15 | `bin/executable_tmux_prefill_last_cmd.bash` | A45 | `tmux` |
| B16 | `bin/executable_tmux_pane_hist_release.bash` | A46, `bin/helper/tmux_last_cmd.bash:71`, `bin/helper/tmux_last_cmd.zsh:73` | `tmux` |
| B17 | `bin/executable_sshfs-mount.sh` | A50, `bin/executable_sshfs.bash:442` | `sshfs`, `fusermount3` |
| B18 | `bin/executable_tmux_boot.bash` | A52, A54 | `tmux` |
| B19 | `bin/executable_yt_playlist_mp3.bash` | A53 | `yt-dlp` |
| B20 | `bin/executable_polybar-supervisor.bash` | `bin/helper/system.bash:44`, `bin/executable_xrandr_manager.bash:168` | `polybar` |
| B21 | `bin/executable_firefox_rofi.bash` | **No tracked invoker** (user command on `PATH`) | B1 |
| B22 | `bin/executable_sshfs.bash` | `bin/helper/storage.bash:8` (public `hh_sshfsctl`, interactive only); also a TUI on `PATH` | `ssh`, `sshfs`, `systemctl`, B17 |
| B23 | `bin/executable_xrandr_dmenu_test.bash` | **No tracked invoker** (debug script) | `xrandr`, `rofi`, `dmenu`, B3 |

The public `hh_*` helpers (§4.1) also call external tools: `gio`, `adb`,
`ffmpeg`, `gpg`, `yay`/`pacman`, `7z`/`unrar`/`unzip`, `rsync`, `ssh`,
`git`, `systemctl`/`launchctl`, `tmux`. They run only when called
interactively; nothing configured starts them.

### 3.3 Non-executing associations (no executable needed for the config to load)

These match windows or desktop IDs. If the application is missing, the
rule never fires and the file still loads. A rule like this goes dead when
its application is removed, but its config does not fail.

| Source | Applications matched | Scope | Recommendation |
|--------|----------------------|-------|----------------|
| `dot_config/i3/config.tmpl:289-314` (`assign`) | slack, job_navigator, thunderbird, zoom, jetbrains-studio / `jetbrains-.+`, Android Emulator, Arduino IDE, alacritty, quodlibet, Telegram, firefox, todoist, discord, joplin, steam, minecraft-launcher, chromium, opera | Linux | Retain. Telegram/Todoist/Joplin/Discord/JetBrains rules stay as other-host support until B/G; Steam/Minecraft/IDE rules are protected |
| `dot_config/i3/config.tmpl:318-367` (`for_window`) | dialog/notification types, peek, firefox, alsamixer, nvidia-settings, telegram-desktop, thunderbird, flameshot, steam, virtualbox, galculator, Android Emulator, zoom, gthumb, okular, slack, keepassxc, pavucontrol, easyeffects (added by #70), blueman-manager, iwgtk, matplotlib, picture-in-picture | Linux | Retain; G may report rules whose application is gone |
| `dot_config/i3/workspaces/workspace_4-dragonlady.json:91-144` | Telegram, Todoist, Joplin swallow criteria (consumed by `append_layout`, A3) | Linux; dragonlady | Retain until B/G decides |
| `dot_config/i3/workspaces/workspace_4-dragoncave.json` | Layout swallow criteria | Linux; dragoncave | Retain |
| `dot_config/private_mimeapps.list:1-48` | Desktop IDs `org.telegram.desktop`, `firefox`, `org.kde.okular`, `userapp-Thunderbird-*`, `discord-402572971681644545`, `pcmanfm`, `org.gnome.gThumb`, `feh`, `jetbrains-toolbox`, `claude-code-url-handler`, `libreoffice-startcenter` | Linux | Retain. Only `firefox.desktop` is tracked here (A59); the other `.desktop` files come from packages. A missing desktop file makes XDG skip the handler |

### 3.4 Declarative configuration (no standalone executable requirement)

Each of these is read by a consumer. Whether that consumer is installed on
the owner's hosts is **not verified**.

| Path | Consumer | Note |
|------|----------|------|
| `dot_config/alacritty/alacritty.toml.tmpl` | alacritty (A5) | Host-guarded font block `:2-6`; no `program`/`shell` override, so `$SHELL` is used |
| `dot_config/polybar/config-dragoncave.ini`, `config-dragonlady.ini` | polybar via `include-file = config-{{ .chezmoi.hostname }}.ini` (`config.ini.tmpl:19`) | Per-host include |
| `dot_config/private_gtk-3.0/settings.ini`, `private_gtk-4.0/settings.ini` | GTK 3/4 applications | — |
| `dot_config/private_user-dirs.dirs` | `xdg-user-dirs` consumers | — |
| `dot_dir_colors` | `dircolors` (A64, A65) | — |
| `dot_vimrc` | vim | Vimscript functions in Appendix A |
| `dot_config/chezmoi/chezmoi.toml.tmpl` | chezmoi | `git.autoCommit` / `autoPush` assume `git`; `localSymlinkTarget` on dragonlady |
| `dot_config/environment.d/create_rclone-bisync.conf` | Target `~/.config/environment.d/rclone-bisync.conf` (chezmoi `create_` prefix): `EnvironmentFile=` of the 8 rclone units (A49), and systemd's user environment generator | Variables in §4.3 |
| `dot_config/.keep`, `dot_config/chezmoi/.keep` | — | Empty directory markers |

### 3.5 Group 1 counts

| Measure | Count | Basis |
|---------|------:|-------|
| Executable-bearing association rows | 68 | A1–A68 (some rows list several commands or lines) |
| Owned-script chain rows | 23 | B1–B23 (all tracked `bin/executable_*`) |
| Owned scripts with no tracked invoker | 2 | B21, B23 (user commands on `PATH`; also listed under Group 2). B22 is launched only by the interactive `hh_sshfsctl` |
| Distinct external command names in A1–A68 | 57 | Listed below |
| Confirmed missing executables | **unknown** | Pending session G |

The 57 distinct external command names in A1–A68 are: `bash`, `i3-msg`,
`uname`, `firefox`, `alacritty`, `zsh`, `Telegram`, `find`, `thunderbird`,
`qbittorrent`, `pasystray`, `cbatticon`, `birdtray`, `blueman-applet`,
`iwgtk`, `light`, `redshift`, `start-pulseaudio-x11`, `inputplug`,
`libinput-gestures-setup`, `pkill`, `rofi`, `pavucontrol`, `keepassxc`,
`xsel`, `xargs`, `vlc`, `quodlibet`, `flameshot`, `notify-send`,
`systemctl`, `nvidia-smi`, `xclip`, `pbcopy`, `pbpaste`, `ps`, `tail`,
`rclone`, `syncthing`, `galculator`, `zenity`, `chromium`, `peek`,
`opera`, `dmenu`, `xdg-open`, `xset`, `xinput`, `ssh-agent`, `git`,
`dircolors`, `xhost`, `pyenv`, `python3`, `chezmoi`, `tmux`, `launchctl`.
Absolute-path forms (`/usr/bin/zsh`, `/usr/lib/firefox/firefox`, …) are
counted under their command name. Owned `~/bin` targets and the TPM plugin
script (A47) are excluded. Tools that appear only in owned-script chains
(§3.2, for example `jq`, `sensors`, `yt-dlp`, `sshfs`) are excluded.
Distinct *applications* are not counted, because several rows cover one
application (A4/A59 firefox) or several applications (A27).

---

## 4. Orphan group 2 — functions and variables without callers

No static caller does **not** prove that a public helper, callback,
dispatch action or exported variable is unused. Public status, dynamic
registration and possible external consumers are recorded separately.

### 4.1 Definition counts (computed from Appendix A)

Counts are for `dc61d977`. The six definitions added since then are in
Appendix A.1 and are not counted here.

| Class | Occurrences | Notes |
|-------|------------:|-------|
| Public `hh_*` implementations (`bin/helper/*.bash`) | 20 | The approved public API |
| Zsh public shims (`bin/helper/bash_exec.zsh:22-88`) | 14 | Bash-only helpers run through `bash -c` |
| Bash public i3 subshell wrappers (`bin/executable_helper.bash:41-43`) | 3 | Interactive-only wrappers around `i3.bash` |
| Approved Bash plumbing | 10 | `_bashrc_git_branch`, `_tmux_log_last_cmd`, `_tmux_pane_hist_{path,claim,sync}`, `_helper_script`, `_ssh_config_hosts`, nested `_flush`, `_rsync_ssh_complete`, `_rm_ssh_complete` |
| Approved Zsh plumbing | 8 | `_ctrl_d_exit`, `_reset_ctrl_d_count`, `_tmux_log_last_cmd`, `_tmux_pane_hist_{path,claim,detect,addhistory,sync}` |
| Helper-module private (`bin/helper/*.bash`, non-`hh_`) | 24 | Includes nested `__emit` (`firefox.bash`) and nested `print_usage` (`system.bash:84`) |
| Dispatcher-private (`bin/executable_helper.bash:69`) | 1 | `show_error_and_usage` |
| Sourced private (`dot_xsessionrc:14`) | 1 | `apply_xsession_input_settings` |
| Script-local (`bin/executable_*`, `modify_dot_gitconfig`) | 120 | asusctl_rofi 11, i3_workspaces 3, polybar-supervisor 4, polybar_system_stats 7, polybar_volume_all 23, sshfs-mount 1, sshfs 18, tmux_prefill_last_cmd 1, xrandr_manager 51, modify_dot_gitconfig 1 |
| **Shell subtotal** | **201** | 180 unique names |
| Embedded AWK `flush()` (`bin/executable_polybar_volume_all.bash:208,346`) | 2 | Separate AWK programs |
| Python `main` (`bin/executable_tmux_osc52_pbcopy.py:16`) | 1 | |
| Vimscript `MoveToNextComma`, `MoveToPrevComma` (`dot_vimrc:140,145`) | 2 | |
| **Total definitions** | **206** | |

**Reconciling unique names.** The 201 shell occurrences contain 21
repeated names: 4 tmux plumbing names defined once for Bash and once for
Zsh, and 17 public names that also have a Zsh shim (14) or a Bash i3
wrapper (3). That gives 180 unique names. The approved exceptions are 10
Bash plus 8 Zsh entries, which share 4 names: **14 unique names, 18
shell-specific occurrences**. They are runtime exceptions to private
absence, not a separate function category. The public API is 20 `hh_*`
functions plus the `hh_cp_ssh` alias (`bin/helper/transfer.bash:190`,
`bin/helper/bash_exec.zsh:73`). That is an interface count, not a
definition count. `has_control_bytes` (`bin/executable_tmux_prefill_last_cmd.bash:20`)
is a script-local helper called at `:48`. It is not an interactive API and
not an allowlist entry.

### 4.2 Functions without callers (candidates)

| # | Definition | Static callers | Dynamic interface / status | Uncertainty | Recommendation |
|---|------------|----------------|----------------------------|-------------|----------------|
| F1 | `get_display` — `bin/helper/system.bash:9` | **None** (no dispatch action; the reachability pass leaves it unreachable) | Helper-module private, loaded only in `helper.bash` script mode | Low. Out-of-tree scripts could only reach it by sourcing `system.bash` | **Source-only no-caller candidate.** Retain in H; owner decides removal later |
| F2 | `hh_git_cleanout` (`git.bash:5`), `hh_sshfsctl` (`storage.bash:5`, a wrapper that launches `~/bin/sshfs.bash` with its arguments), `hh_gio_mount` (`storage.bash:11`), `hh_gio_umount` (`storage.bash:36`), `hh_tmux_restore` (`tmux_commands.bash:10`) | None outside their own bodies | Public interactive API (Bash `helper.bash:28` module list; Zsh `dot_zshrc:120-128`) | Interactive use cannot be seen from source | Retain (public API) |
| F3 | 14 Zsh shims (`bash_exec.zsh`) and 3 Bash i3 wrappers (`helper.bash:41-43`) | Invoked by name from the interactive shell only | Public wrappers | Same as F2 | Retain |
| F4 | `hh_colors`, `hh_unar`, `hh_upgrade_system`, `hh_yay_no_cache`, `hh_adb_pull_music`, `hh_unzip_books`, `hh_cut_video`, `hh_gpg_decrypt`, `hh_gpg_encrypt`, `hh_i3_*` implementations | Only the `bash -c '… && NAME "$@"'` strings in `bash_exec.zsh` or the `helper.bash:41-43` wrappers | Public API; Bash loads them directly | — | Retain |

Every other definition in Appendix A has at least one verified call site
or registration outside its own body: `complete -F`, `PROMPT_COMMAND`,
`precmd_functions`, `zshaddhistory_functions`, `zle -N` / `bindkey`, the
`helper.bash` `case` dispatch, a same-file call, the AWK `END` block,
Python `__main__`, or a Vim `xnoremap`. The reachability pass found no
function whose only callers are themselves unreachable, except F1.
Appendix A lists the evidence for each definition.

**Dispatch actions without a tracked invoker.** `bin/executable_helper.bash`
dispatches 23 string actions (`:92-239`). These have no invoker in tracked
config: `kbd_brightness_up` (`:116`), `kbd_brightness_down` (`:119`),
`i3_restart` (`:180`), `i3-reload` (`:184`), `mitmproxy` (`:190`),
`swagger-ui` (`:198`), `swagger-editor` (`:208`), `rclone_to_backup`
(`:229`), `tmux_ide_session` (`:236`). They are command-line interface
entries offered by `dot_bash_completion.d/helper.bash`, so manual use is
plausible. **Retain; owner revalidates usage.** The other 14 actions are
invoked from A1, A8, A49, A59 or B3–B5.

**Owned scripts without a tracked invoker:** `bin/executable_firefox_rofi.bash`,
`bin/executable_xrandr_dmenu_test.bash` (B21, B23). These are user
commands on `PATH`. `bin/executable_sshfs.bash` (B22) is launched by the
public `hh_sshfsctl` (`bin/helper/storage.bash:8`), so its only tracked
invoker is interactive. **Retain; owner revalidates.**

### 4.3 Variables

| # | Variable | Definition | Static/dynamic consumers in tracked tree | Interface status | Recommendation |
|---|----------|------------|------------------------------------------|------------------|----------------|
| V1 | `RED_COLOR` | `dot_bashrc:89` | **None** (SC2034) | Unexported shell variable | **Source-only unused candidate.** Retain in H |
| V2 | `GDK_SCALE` | `dot_xsessionrc:9` | **None** in tree (SC2034); assigned without `export` | Unexported unless the host's Xsession wrapper exports sourced variables (not verified) | **Source-only unused candidate**; G revalidates whether the X session exports it. Retain in H |
| V3 | `RED` | `dot_zshrc:60` | **None** (manual review; `BLUE`, `GREEN`, `MAGENTA`, `RESET` are used at `:67-79`) | Unexported Zsh variable | **Source-only unused candidate.** Retain in H |
| V4 | `JOB_MOUNT_DIR` | `bin/helper/common.bash:11` | **None** since #60 removed `job_mount`/`job_umount` | Exported interface | Retain pending external `/Data/Job` confirmation (not inspected) |
| V5 | `JOB_TEARDOWN_FILE` | `bin/helper/common.bash:13` | **None** since #60 | Exported interface | Retain pending external confirmation |
| V6 | `JOB_SETUP_FILE` | `bin/helper/common.bash:12` | `bin/executable_helper.bash:61-63`, `dot_zshrc:141-142` (sourced if present) | Exported, active | Retain |
| V7 | `PORT_SWAGGER_UI`, `PORT_SWAGGER_EDITOR` | `bin/helper/common.bash:16,17` | `bin/executable_helper.bash:206,209` (actions with no tracked invoker, §4.2) | Exported | Retain |
| V8 | `DESKTOP_BG` | `bin/helper/common.bash:20` | `bin/helper/system.bash:36`, `bin/executable_xrandr_manager.bash:173-178`, `bin/modify_dot_env.tmpl:15,26,29` | Exported; per-host value in `~/bin/.env` | Retain |
| V9 | `LOCK_SCREEN_IMAGE` | `bin/helper/common.bash:21` | `bin/executable_helper.bash:163`, `bin/modify_dot_env.tmpl:15,27,30` | Exported | Retain |
| V10 | `TMUX_SESSION` | `bin/helper/common.bash:24` | `bin/helper/tmux.bash:66`, `bin/modify_dot_env.tmpl:15,23` | Exported | Retain |
| V11 | `SINK_NAME` | `bin/helper/common.bash:27` | `bin/executable_helper.bash:131,141`, `bin/helper/system.bash:69-101` | Exported | Retain |
| V12 | `VBOX_USB` | `dot_bashrc:136`, `dot_zshrc:92` | **None in tree** | Exported. External consumption (VirtualBox) is **unverified** | Retain pending owner confirmation |
| V13 | `EDITOR`, `VISUAL` | `dot_bashrc:137-138`, `dot_zshrc:93-94` | None in tree | Exported; conventional variables read by external programs (not verified on host) | Retain |
| V14 | `PIPENV_VENV_IN_PROJECT`, `JAVA_HOME`, `USE_GKE_GCLOUD_AUTH_PLUGIN`, `PYTHONWARNINGS` | `dot_bashrc:140-144`, `dot_zshrc:96-100` | None in tree | Exported for external tools; consumption **unverified** | Retain pending owner confirmation |
| V15 | `PYENV_ROOT` | `dot_bashrc:152`, `dot_zshrc:146` | Same files `:153-154` / `:147-148` | Exported | Retain |
| V16 | `TMUX_TMPDIR` | `run_once_install-tpm-plugins.bash:58` | Read by the `tmux` child processes of that script | Exported to children | Retain |
| V17 | `BISYNC_*` (12 keys) | `dot_config/environment.d/create_rclone-bisync.conf:1-15` | Each key is used in its matching pair of rclone units (A49) | Environment file interface | Retain |
| V18 | `HOME_HELPER_UNIQ_SCRIPT_{NAME,PATH,DIR}`, `HELPER_MODULE_DIR`, `EXEC_NAME`, `XSESSIONRC_SKIP_INIT` | `bin/executable_helper.bash:6-18`, `bin/helper/system.bash:7` | Used within `helper.bash`, `system.bash:85`, `dot_xsessionrc:1-6,32` | Internal | Retain |

SC2034 over every Bash-family production file (`shellcheck -s bash -i SC2034`)
reported only V1 and V2. Zsh-only files were reviewed by hand (V3).

---

## 5. Regression evidence

> **Historical.** This section records runs against `dc61d977` on
> 2026-11-05 and was not re-run in the 2026-11-14 refresh. The test suites
> have since been rewritten; `tests/test_retired_desktop_integration.bash`
> was removed in 900aea9 (replaced by `tests/test_polybar_chezmoi_widget.bash`).
> Line numbers in §5.4 refer to the revisions named in its table.

### 5.1 Fresh runs at this head (degraded runner)

**Runner environment:** Linux x86_64, GNU bash 5.2.37, Python 3, ShellCheck
0.10.0. **Not installed:** `zsh`, `tmux`, `rsync`, `chezmoi`,
`bash-completion`. The suites skip assertions that need a missing tool and
print `GAP`/`SKIP` instead. These totals are therefore **lower than the
native totals in §5.2 and must not be compared with them**. Each suite was
run in the foreground with stdin from `/dev/null`. The three
interactive-shell suites ran under `setsid -w`, so no controlling terminal
was attached; no TIOCNOTTY or other terminal harness was used. Counts are
`grep -c '^PASS'` etc. over each log.

| Suite | Command | Exit | PASS | FAIL | GAP | SKIP | Final line |
|-------|---------|-----:|-----:|-----:|----:|-----:|------------|
| Retired desktop integration | `bash tests/test_retired_desktop_integration.bash </dev/null` | 0 | 35 | 0 | 0 | 0 | `All checks passed` |
| Agent skill distribution | `AI_WRAPPER_PINNED_SRC=<clean clone at db66133> bash tests/test_agent_skill_distribution.bash </dev/null` | 0 | 40 | 0 | 0 | 1 | `All checks passed, 1 skipped` |
| Shell helper isolation | `setsid -w bash tests/test_shell_helper_isolation.bash </dev/null` | 0 | 113 | 0 | 1 | 0 | `0 failure(s), 1 verification gap(s)` |
| `hh_` public API | `setsid -w bash tests/test_hh_public_api.bash </dev/null` | 0 | 102 | 0 | 3 | 0 | `0 failure(s), 3 verification gap(s)` |
| tmux preservation | `setsid -w bash tests/test_tmux_preservation.bash </dev/null` | 0 | 155 | 0 | 4 | 0 | `failures=0 gaps=4` |

The GAP/SKIP lines reported verbatim by the suites:

- Distribution — `SKIP: rsync scenario: rsync not installed on this host; only the cp fallback was exercised`
- Isolation — `GAP: zsh not installed on this runner: zsh namespace, bash_exec boundary, re-source and macOS layout not verified here (owner-side native run required)`
- API — `GAP: zsh not installed …: zsh API/alias/env parity not verified here`;
  `GAP: bash-completion not installed (/usr/share/bash-completion/bash_completion): bash transfer argument completion not verified here`;
  `GAP: zsh not installed …: zsh hh<Tab>, transfer completion and Ctrl+D PTY checks not verified here`
- tmux — `GAP: zsh not installed: ZLE side-effect checks not run (Bash only)`;
  `GAP: zsh not installed: Zsh last-command logger target resolution not run`;
  `GAP: systemd user-manager lifecycle (…) not exercised: needs a service-manager sandbox`;
  `GAP: tmux not installed: native save/restore not run`

No GAP or SKIP was counted as a PASS.

### 5.2 Inherited native evidence (PR #68, source head `d170491`, squashed as `dc61d977`)

This evidence was recorded in PR #68 (issue comments 6657462903 and
6658918848, plus the final review). It was **not reproduced here**.

| Evidence | Recorded result | Environment as recorded |
|----------|-----------------|-------------------------|
| tmux preservation | 219 PASS, 0 FAIL; exactly 1 GAP (systemd lifecycle) | Owner-side native run, tmux 3.8 |
| Shell helper isolation (E1) | 162 PASS | Native, with zsh |
| `hh_` public API | 212 PASS | Native, with zsh and bash-completion |
| Retired desktop integration | 35 PASS | — |
| Agent skill distribution | 54 PASS | Pinned AI-Wrapper `db66133` |
| systemd lifecycle | PASS: clean startup and cgroup ownership, existing-server inactive/no-adoption, synthetic restore/bootstrap cleanup, real PAM logout with linger on/off, cold container start | Separate owner-approved container (systemd 252.39, tmux 3.3a), since removed. It supplies the tmux suite's single systemd GAP. It does **not** prove native host boot or macOS |

No new privileged sandbox was launched for H.

### 5.3 Syntax and whitespace (fresh)

| Check | Command | Inputs | Result |
|-------|---------|--------|--------|
| Bash syntax, all tracked Bash-family files | `bash -n` on every tracked `*.bash`, `*.sh`, `*.shrc`, plus `dot_bashrc`, `dot_bash_profile`, `dot_xsessionrc`, `modify_dot_gitconfig` | 52 files (46 production, 6 under `tests/`) | 0 failures |
| CI-equivalent syntax step | `find . \( -path ./.git -prune \) -o \( \( -name '*.bash' -o -name '*.sh' \) -print \) \| sort \| xargs -I{} bash -n {}` | 47 files | exit 0 |
| Python parse | `python3 -I -m py_compile bin/executable_tmux_osc52_pbcopy.py tests/pty_drive.py`; `ast.parse` of `dot_config/keepassxc/modify_keepassxc.ini` | 3 files | OK |
| Whitespace | `git diff --check 56796c0..dc61d977` (milestone base #54 → integration) | — | exit 0 |
| Zsh syntax | — | `dot_zshrc`, `bin/helper/*.zsh` | **Not run** (no zsh). Covered only by inherited native evidence |
| Template rendering | — | 11 `*.tmpl` files plus templated `.chezmoiignore` | **Not run.** chezmoi is not installed and no other renderer was used. Raw `.bash.tmpl` files contain `{{ }}` and cannot go through `bash -n`. Linux/Darwin/host guards were **read**, not rendered (§3) |

### 5.4 ShellCheck (fresh, comparable baseline)

Command, identical at both revisions:
`find . \( -path ./.git -prune \) -o \( \( -name '*.bash' -o -name '*.sh' \) -print \) | sort | xargs shellcheck -S warning -f gcc`.
This matches the CI ShellCheck pattern (`*.bash *.sh`, level `warning`).

| Revision | Files | Findings |
|----------|------:|----------|
| Milestone base `56796c0` (git archive) | 41 | `bin/executable_helper.bash:21` SC1090; `bin/helper/tmux.bash:206` SC2174 |
| `dc61d977` | 47 | `bin/executable_helper.bash:33` SC1090; `bin/helper/tmux_last_cmd.bash:73` SC2174 |

Both findings are the same instruction at both revisions:
`[[ -f "${HELPER_MODULE_DIR}/${_mod}.bash" ]] && source "${HELPER_MODULE_DIR}/${_mod}.bash"`
and `mkdir -p -m 700 "${_TMUX_PANE_HIST_DIR}"`. The second one moved
modules between the two revisions. Within this command's scope, no new
code/instruction pair appeared. ShellCheck exits non-zero (123) at both
revisions, so the tree is **not** warning-free.

**Outside the CI pattern:** `dot_bashrc`, `dot_bash_profile`,
`dot_xsessionrc` and `bin/helper/aliases.shrc` are not linted in CI.
Running ShellCheck on them directly reports SC2148 (no shebang) on all
four, plus SC2045/SC1090/SC2046/SC2034 in `dot_bashrc`, SC2034 in
`dot_xsessionrc` and SC2142 in `aliases.shrc`. These are reported
**as-is**: no waiver was added and no comparison against a baseline was
made. `*.tmpl` and `*.zsh` files are not linted at all. These gaps in the
CI pattern are existing behaviour and unchanged.

---

## 6. Non-orphan risk context (disclosure only)

These are not orphans. Each one is a proposal only. No fix and no new
issue is part of this package. Item 1 was later fixed outside this package (noted inline).

1. **`tmux_main_session` bootstrap cleanup goes through the aliased
   `kill-session`.** *Resolved after this audit by 9452b3b.* At
   `dc61d977`, `bin/helper/tmux.bash` ran
   `tmux kill-session -t "${boot_session}"`, but
   `dot_config/tmux/tmux.conf.tmpl:130` aliases `kill-session` to an
   interactive `confirm-before … kill-ses`, so the temporary
   `_main_boot_$$` session could survive. `bin/helper/tmux.bash:103` now
   runs `tmux kill-ses -t "=${boot_session}"` (comment at `:99-102`), the
   same form `bin/executable_tmux_boot.bash:64` uses (comment at `:57-59`).
2. **`helper.bash volume -h` calls a nested function before it exists.**
   `bin/executable_helper.bash:127` calls `print_usage`. That function is
   defined only inside `set_volume` (`bin/helper/system.bash:84`), which has
   not run yet at that point. Also, `getopts "h:s:"` makes `-h` take an
   argument. Evidence is static; the command was not run because it would
   call `pactl`. The nested body is frozen. Proposed for a follow-up only.
3. **Missing `.env.template` fallback.** `bin/executable_helper.bash:50`
   and `dot_xsessionrc:6` source `~/bin/.env.template` when `~/bin/.env` is
   absent, but no `.env.template` is tracked. `dot_zshrc:106` guards the
   same fallback with `-f`. `bin/modify_dot_env.tmpl` normally creates
   `~/bin/.env`, so the fallback only runs on a host where that never
   happened. Session G can confirm `~/bin/.env` exists.

---

## 7. Owner-host handoff (sessions B and G)

**Session G (owner-host validation; dragoncave, dragonlady, macOS):**

1. For each A-row and B-row whose scope covers the host, check whether the
   command exists (`command -v`, or the absolute path). Record the date,
   host and result. Only that result can confirm a Group 1 orphan.
2. Absolute paths to confirm: `/usr/bin/zsh` (A6), `/usr/bin/notify-send`
   (A48), `/usr/bin/syncthing` (A51), `/usr/bin/chromium` (A57),
   `/usr/lib/firefox/firefox` (A59), `/usr/bin/dmenu` and `/usr/bin/xdg-open`
   (A61), `/usr/bin/bash` (A49).
3. Dead window rules and MIME desktop IDs (§3.3) whose application is gone.
4. Whether the X session exports `GDK_SCALE` (V2). Whether external tools
   still read `VBOX_USB` and the V14 variables. Whether `/Data/Job` scripts
   read `JOB_MOUNT_DIR` / `JOB_TEARDOWN_FILE` (V4, V5).
5. Whether the no-invoker dispatch actions and scripts (§4.2) are still
   used manually.
6. That `~/bin/.env` exists (§6.3). Native zsh, tmux and macOS reruns of
   the §5.1 suites, to close the runner GAPs.

**Session B (owner-controlled application removal):** Telegram, Todoist,
Joplin, Discord, WebStorm and JetBrains Toolbox are approved for later
owner-controlled host removal. Their repository references (A7, A8, §3.3
rules, MIME IDs, `workspace_4-dragonlady.json`) stay in the tree as
other-host support. KeePassXC, Steam/game, project, shared data, unrelated
IDEs and the excluded Cursor scope are protected. **No row in this report
approves any removal or execution.**

**Owner decisions:** none are required to accept this report, because
everything is retained. These are future cleanup options, not blockers:
F1 `get_display`, V1 `RED_COLOR`, V2 `GDK_SCALE`, V3 `RED`, V4/V5 job
exports, V12 `VBOX_USB`, and the §6 follow-ups.

---

## 8. Audit limitations

- **Lexical scans.** Definition and caller detection is by regex and whole
  words, with the zero- and self-reference results re-read by hand. A
  dynamically built name such as `"${prefix}_x"` would not be found; none
  was seen during the manual review. Usage strings count as references for
  public helpers; Appendix A flags this.
- **Tool lists for owned scripts (§3.2)** come from a fixed list of
  candidate command names and may miss less common commands.
- **External consumers** (other repositories, private `/Data/Job` scripts,
  host scripts, GUI launchers, user muscle memory) were not inspected and
  cannot be inspected from here.
- **No host evidence.** Package managers, installed binaries, live
  services, tmux sessions and the X session were not touched.
- **Degraded runner.** zsh, tmux, rsync, chezmoi and bash-completion are
  missing, so templates were not rendered and Zsh/native tmux checks rely
  on inherited PR #68 evidence.
- **Excluded scopes:** the AI-Wrapper submodule contents, test files and
  fixtures (147 anchored-scan definition hits under `tests/` at `dc61d977`, not
  enumerated), Markdown docs, and
  installed plugin copies.

---

## Appendix A — production definition manifest

Columns: definition site in the working tree at `c2d2a00` (refreshed
2026-11-14; the set of rows is the `dc61d977` inventory), name, class, and references found
outside the function's own body (`file:lines`). For script-local classes,
only same-file references count. Public `hh_*` rows can include usage
strings and `bash -c` strings: these show dynamic dispatch, not
independent callers. Rows 1–201 are shell (generated); rows 202–206 were
added by hand.

| # | Definition | Name | Class | References outside body |
|---|------------|------|-------|-------------------------|
| 1 | `bin/executable_asusctl_rofi.bash:12` | `_rofi_menu` | script-local | bin/executable_asusctl_rofi.bash:70,95,128,162,200 |
| 2 | `bin/executable_asusctl_rofi.bash:19` | `_notify` | script-local | bin/executable_asusctl_rofi.bash:79,81,104,106,112,138,139,143,144,148,149,176,177,183,184 |
| 3 | `bin/executable_asusctl_rofi.bash:24` | `_current_profile` | script-local | bin/executable_asusctl_rofi.bash:55,197 |
| 4 | `bin/executable_asusctl_rofi.bash:30` | `_list_profiles` | script-local | bin/executable_asusctl_rofi.bash:65 |
| 5 | `bin/executable_asusctl_rofi.bash:36` | `_current_fan_preset` | script-local | bin/executable_asusctl_rofi.bash:111 |
| 6 | `bin/executable_asusctl_rofi.bash:42` | `_battery_limit` | script-local | bin/executable_asusctl_rofi.bash:125 |
| 7 | `bin/executable_asusctl_rofi.bash:52` | `_menu_profile` | script-local | bin/executable_asusctl_rofi.bash:209 |
| 8 | `bin/executable_asusctl_rofi.bash:92` | `_menu_fan_curve` | script-local | bin/executable_asusctl_rofi.bash:210 |
| 9 | `bin/executable_asusctl_rofi.bash:122` | `_menu_battery` | script-local | bin/executable_asusctl_rofi.bash:211 |
| 10 | `bin/executable_asusctl_rofi.bash:159` | `_menu_aura` | script-local | bin/executable_asusctl_rofi.bash:212 |
| 11 | `bin/executable_asusctl_rofi.bash:194` | `_menu_main` | script-local | bin/executable_asusctl_rofi.bash:217 |
| 12 | `bin/executable_helper.bash:41` | `hh_i3_save_chezmoi_ws` | Bash public i3 subshell wrapper | bin/helper/bash_exec.zsh:78; bin/helper/i3.bash:45 |
| 13 | `bin/executable_helper.bash:42` | `hh_i3_save_ws` | Bash public i3 subshell wrapper | bin/helper/bash_exec.zsh:82; bin/helper/i3.bash:109 |
| 14 | `bin/executable_helper.bash:43` | `hh_i3_restore_ws` | Bash public i3 subshell wrapper | bin/helper/bash_exec.zsh:86; bin/helper/i3.bash:158 |
| 15 | `bin/executable_helper.bash:69` | `show_error_and_usage` | dispatcher-private | bin/executable_helper.bash:244 |
| 16 | `bin/executable_i3_workspaces.bash:14` | `drop_single_window_titles` | script-local | bin/executable_i3_workspaces.bash:59 |
| 17 | `bin/executable_i3_workspaces.bash:32` | `save_all` | script-local | bin/executable_i3_workspaces.bash:83 |
| 18 | `bin/executable_i3_workspaces.bash:70` | `restore_all` | script-local | bin/executable_i3_workspaces.bash:84 |
| 19 | `bin/executable_polybar-supervisor.bash:10` | `launch_mon_bars` | script-local | bin/executable_polybar-supervisor.bash:45 |
| 20 | `bin/executable_polybar-supervisor.bash:32` | `launch_bars` | script-local | bin/executable_polybar-supervisor.bash:56,84 |
| 21 | `bin/executable_polybar-supervisor.bash:49` | `restart_if_primary_changed` | script-local | bin/executable_polybar-supervisor.bash:62 |
| 22 | `bin/executable_polybar-supervisor.bash:60` | `monitor_bars` | script-local | bin/executable_polybar-supervisor.bash:85 |
| 23 | `bin/executable_polybar_system_stats.bash:32` | `get_cpu_power` | script-local | bin/executable_polybar_system_stats.bash:204,366 |
| 24 | `bin/executable_polybar_system_stats.bash:127` | `get_gpu_power` | script-local | bin/executable_polybar_system_stats.bash:205,367 |
| 25 | `bin/executable_polybar_system_stats.bash:144` | `get_battery_power` | script-local | bin/executable_polybar_system_stats.bash:206,368 |
| 26 | `bin/executable_polybar_system_stats.bash:185` | `get_power` | script-local | bin/executable_polybar_system_stats.bash:445 |
| 27 | `bin/executable_polybar_system_stats.bash:262` | `get_max_temp` | script-local | bin/executable_polybar_system_stats.bash:451 |
| 28 | `bin/executable_polybar_system_stats.bash:312` | `get_max_fan` | script-local | bin/executable_polybar_system_stats.bash:454 |
| 29 | `bin/executable_polybar_system_stats.bash:350` | `get_power_detail` | script-local | bin/executable_polybar_system_stats.bash:448 |
| 30 | `bin/executable_polybar_volume_all.bash:81` | `get_volume` | script-local | bin/executable_polybar_volume_all.bash:109,301,520 |
| 31 | `bin/executable_polybar_volume_all.bash:87` | `get_mute` | script-local | bin/executable_polybar_volume_all.bash:304,521 |
| 32 | `bin/executable_polybar_volume_all.bash:96` | `clamp_volume` | script-local | bin/executable_polybar_volume_all.bash:113,683,684,685 |
| 33 | `bin/executable_polybar_volume_all.bash:107` | `change_volume` | script-local | bin/executable_polybar_volume_all.bash:424,425,637,640 |
| 34 | `bin/executable_polybar_volume_all.bash:121` | `toggle_mute` | script-local | bin/executable_polybar_volume_all.bash:426,550 |
| 35 | `bin/executable_polybar_volume_all.bash:127` | `volume_bar` | script-local | bin/executable_polybar_volume_all.bash:435,437,687,688,689,691,692 |
| 36 | `bin/executable_polybar_volume_all.bash:147` | `is_real_device` | script-local | bin/executable_polybar_volume_all.bash:196,654,655,656,666,667,669,672,674 |
| 37 | `bin/executable_polybar_volume_all.bash:166` | `get_default_device` | script-local | bin/executable_polybar_volume_all.bash:313,462,525,623 |
| 38 | `bin/executable_polybar_volume_all.bash:172` | `get_next_device` | script-local | bin/executable_polybar_volume_all.bash:630 |
| 39 | `bin/executable_polybar_volume_all.bash:191` | `get_devices` | script-local | bin/executable_polybar_volume_all.bash:178,314,392,479 |
| 40 | `bin/executable_polybar_volume_all.bash:240` | `format_dev_name` | script-local | bin/executable_polybar_volume_all.bash:274,390,469,650,651,652 |
| 41 | `bin/executable_polybar_volume_all.bash:268` | `build_output` | script-local | bin/executable_polybar_volume_all.bash:315 |
| 42 | `bin/executable_polybar_volume_all.bash:311` | `render` | script-local | bin/executable_polybar_volume_all.bash:699 |
| 43 | `bin/executable_polybar_volume_all.bash:335` | `list_streams` | script-local | bin/executable_polybar_volume_all.bash:582 |
| 44 | `bin/executable_polybar_volume_all.bash:378` | `device_index` | script-local | bin/executable_polybar_volume_all.bash:569 |
| 45 | `bin/executable_polybar_volume_all.bash:386` | `device_label` | script-local | bin/executable_polybar_volume_all.bash:516 |
| 46 | `bin/executable_polybar_volume_all.bash:421` | `apply_volume_key` | script-local | bin/executable_polybar_volume_all.bash:505,545 |
| 47 | `bin/executable_polybar_volume_all.bash:432` | `volume_status` | script-local | bin/executable_polybar_volume_all.bash:477,528,691,692 |
| 48 | `bin/executable_polybar_volume_all.bash:441` | `context_menu` | script-local | bin/executable_polybar_volume_all.bash:634 |
| 49 | `bin/executable_polybar_volume_all.bash:514` | `device_menu` | script-local | bin/executable_polybar_volume_all.bash:508 |
| 50 | `bin/executable_polybar_volume_all.bash:565` | `move_streams_menu` | script-local | bin/executable_polybar_volume_all.bash:556 |
| 51 | `bin/executable_polybar_volume_all.bash:621` | `handle_click` | script-local | bin/executable_polybar_volume_all.bash:701 |
| 52 | `bin/executable_polybar_volume_all.bash:647` | `self_check` | script-local | bin/executable_polybar_volume_all.bash:700 |
| 53 | `bin/executable_sshfs-mount.sh:60` | `check_mount_health` | script-local | bin/executable_sshfs-mount.sh:120 |
| 54 | `bin/executable_sshfs.bash:29` | `show_header` | script-local | bin/executable_sshfs.bash:182,273,329,337,383,398 |
| 55 | `bin/executable_sshfs.bash:42` | `parse_ssh_hosts` | script-local | bin/executable_sshfs.bash:180 |
| 56 | `bin/executable_sshfs.bash:52` | `_flush_host` | script-local | bin/executable_sshfs.bash:79,97,104 |
| 57 | `bin/executable_sshfs.bash:116` | `escape_instance` | script-local | bin/executable_sshfs.bash:130,139,148,157,312 |
| 58 | `bin/executable_sshfs.bash:121` | `unescape_instance` | script-local | bin/executable_sshfs.bash:170 |
| 59 | `bin/executable_sshfs.bash:127` | `do_mount` | script-local | bin/executable_sshfs.bash:295 |
| 60 | `bin/executable_sshfs.bash:136` | `do_umount` | script-local | bin/executable_sshfs.bash:358,364 |
| 61 | `bin/executable_sshfs.bash:145` | `do_enable` | script-local | bin/executable_sshfs.bash:307 |
| 62 | `bin/executable_sshfs.bash:154` | `is_mounted` | script-local | bin/executable_sshfs.bash:299 |
| 63 | `bin/executable_sshfs.bash:163` | `list_active_instances` | script-local | bin/executable_sshfs.bash:326 |
| 64 | `bin/executable_sshfs.bash:178` | `select_host` | script-local | bin/executable_sshfs.bash:259 |
| 65 | `bin/executable_sshfs.bash:223` | `select_remote_dir` | script-local | bin/executable_sshfs.bash:266 |
| 66 | `bin/executable_sshfs.bash:236` | `select_mountpoint` | script-local | bin/executable_sshfs.bash:270 |
| 67 | `bin/executable_sshfs.bash:256` | `run_mount_wizard` | script-local | bin/executable_sshfs.bash:409,460 |
| 68 | `bin/executable_sshfs.bash:324` | `run_umount_wizard` | script-local | bin/executable_sshfs.bash:410,463 |
| 69 | `bin/executable_sshfs.bash:382` | `show_status` | script-local | bin/executable_sshfs.bash:411,466 |
| 70 | `bin/executable_sshfs.bash:396` | `run_menu` | script-local | bin/executable_sshfs.bash:473 |
| 71 | `bin/executable_sshfs.bash:423` | `show_help` | script-local | bin/executable_sshfs.bash:469,475,481 |
| 72 | `bin/executable_tmux_prefill_last_cmd.bash:20` | `has_control_bytes` | script-local | bin/executable_tmux_prefill_last_cmd.bash:48 |
| 73 | `bin/executable_xrandr_manager.bash:26` | `get_connected_outputs` | script-local | bin/executable_xrandr_manager.bash:237,260,331,422,499,531,624,787,908 |
| 74 | `bin/executable_xrandr_manager.bash:31` | `get_disconnected_outputs` | script-local | bin/executable_xrandr_manager.bash:265,629 |
| 75 | `bin/executable_xrandr_manager.bash:36` | `get_primary_output` | script-local | bin/executable_xrandr_manager.bash:516 |
| 76 | `bin/executable_xrandr_manager.bash:41` | `extract_mode` | script-local | bin/executable_xrandr_manager.bash:276,870 |
| 77 | `bin/executable_xrandr_manager.bash:51` | `get_available_modes` | script-local | bin/executable_xrandr_manager.bash:877 |
| 78 | `bin/executable_xrandr_manager.bash:61` | `extract_position` | script-local | bin/executable_xrandr_manager.bash:92,229,277,416,649 |
| 79 | `bin/executable_xrandr_manager.bash:67` | `get_display_dimensions` | script-local | bin/executable_xrandr_manager.bash:231,405,479 |
| 80 | `bin/executable_xrandr_manager.bash:75` | `get_display_offset` | script-local | bin/executable_xrandr_manager.bash:232,406,420 |
| 81 | `bin/executable_xrandr_manager.bash:83` | `is_primary_output` | script-local | bin/executable_xrandr_manager.bash:234,278,646,785 |
| 82 | `bin/executable_xrandr_manager.bash:89` | `is_output_enabled` | script-local | bin/executable_xrandr_manager.bash:784,906 |
| 83 | `bin/executable_xrandr_manager.bash:97` | `get_display_name` | script-local | bin/executable_xrandr_manager.bash:148 |
| 84 | `bin/executable_xrandr_manager.bash:145` | `get_display_label` | script-local | bin/executable_xrandr_manager.bash:645,783,820,866,900,915 |
| 85 | `bin/executable_xrandr_manager.bash:162` | `reload_desktop_environment` | script-local | bin/executable_xrandr_manager.bash:300,490,698,839,849,853,892,942,1008 |
| 86 | `bin/executable_xrandr_manager.bash:193` | `list_configs` | script-local | bin/executable_xrandr_manager.bash:733,990 |
| 87 | `bin/executable_xrandr_manager.bash:211` | `get_default_config` | script-local | bin/executable_xrandr_manager.bash:313,557,726,992 |
| 88 | `bin/executable_xrandr_manager.bash:218` | `set_default_config` | script-local | bin/executable_xrandr_manager.bash:772,998 |
| 89 | `bin/executable_xrandr_manager.bash:224` | `generate_layout_description` | script-local | bin/executable_xrandr_manager.bash:254 |
| 90 | `bin/executable_xrandr_manager.bash:245` | `save_config` | script-local | bin/executable_xrandr_manager.bash:769,978 |
| 91 | `bin/executable_xrandr_manager.bash:272` | `save_output_config` | script-local | bin/executable_xrandr_manager.bash:259 |
| 92 | `bin/executable_xrandr_manager.bash:290` | `load_config` | script-local | bin/executable_xrandr_manager.bash:561,747,982 |
| 93 | `bin/executable_xrandr_manager.bash:304` | `delete_config` | script-local | bin/executable_xrandr_manager.bash:986 |
| 94 | `bin/executable_xrandr_manager.bash:327` | `apply_config_file` | script-local | bin/executable_xrandr_manager.bash:299 |
| 95 | `bin/executable_xrandr_manager.bash:344` | `build_output_args` | script-local | bin/executable_xrandr_manager.bash:337 |
| 96 | `bin/executable_xrandr_manager.bash:364` | `add_mode_args` | script-local | bin/executable_xrandr_manager.bash:352 |
| 97 | `bin/executable_xrandr_manager.bash:377` | `add_position_args` | script-local | bin/executable_xrandr_manager.bash:353 |
| 98 | `bin/executable_xrandr_manager.bash:388` | `execute_xrandr_command` | script-local | bin/executable_xrandr_manager.bash:340,489 |
| 99 | `bin/executable_xrandr_manager.bash:402` | `calculate_middle_axis` | script-local | bin/executable_xrandr_manager.bash:462 |
| 100 | `bin/executable_xrandr_manager.bash:411` | `get_displays_left_to_right` | script-local | bin/executable_xrandr_manager.bash:434,466 |
| 101 | `bin/executable_xrandr_manager.bash:428` | `find_next_clockwise` | script-local | bin/executable_xrandr_manager.bash:542 |
| 102 | `bin/executable_xrandr_manager.bash:453` | `rearrange_displays` | script-local | bin/executable_xrandr_manager.bash:585,688,1005 |
| 103 | `bin/executable_xrandr_manager.bash:498` | `get_current_state` | script-local | bin/executable_xrandr_manager.bash:504,572 |
| 104 | `bin/executable_xrandr_manager.bash:503` | `save_state` | script-local | bin/executable_xrandr_manager.bash:588,1018 |
| 105 | `bin/executable_xrandr_manager.bash:508` | `load_previous_state` | script-local | bin/executable_xrandr_manager.bash:571 |
| 106 | `bin/executable_xrandr_manager.bash:513` | `handle_disconnection` | script-local | bin/executable_xrandr_manager.bash:598 |
| 107 | `bin/executable_xrandr_manager.bash:528` | `select_new_primary` | script-local | bin/executable_xrandr_manager.bash:523 |
| 108 | `bin/executable_xrandr_manager.bash:551` | `handle_connection` | script-local | bin/executable_xrandr_manager.bash:610 |
| 109 | `bin/executable_xrandr_manager.bash:569` | `auto_configure` | script-local | bin/executable_xrandr_manager.bash:1002,1020 |
| 110 | `bin/executable_xrandr_manager.bash:592` | `detect_disconnections` | script-local | bin/executable_xrandr_manager.bash:579 |
| 111 | `bin/executable_xrandr_manager.bash:604` | `detect_connections` | script-local | bin/executable_xrandr_manager.bash:582 |
| 112 | `bin/executable_xrandr_manager.bash:620` | `list_outputs` | script-local | bin/executable_xrandr_manager.bash:713,1011 |
| 113 | `bin/executable_xrandr_manager.bash:641` | `format_output_info` | script-local | bin/executable_xrandr_manager.bash:623 |
| 114 | `bin/executable_xrandr_manager.bash:660` | `dmenu_main_menu` | script-local | bin/executable_xrandr_manager.bash:1014 |
| 115 | `bin/executable_xrandr_manager.bash:711` | `dmenu_list_outputs` | script-local | bin/executable_xrandr_manager.bash:701 |
| 116 | `bin/executable_xrandr_manager.bash:723` | `dmenu_load_config_menu` | script-local | bin/executable_xrandr_manager.bash:679 |
| 117 | `bin/executable_xrandr_manager.bash:752` | `dmenu_save_config_menu` | script-local | bin/executable_xrandr_manager.bash:682 |
| 118 | `bin/executable_xrandr_manager.bash:778` | `dmenu_display_settings_menu` | script-local | bin/executable_xrandr_manager.bash:685 |
| 119 | `bin/executable_xrandr_manager.bash:817` | `dmenu_single_display_menu` | script-local | bin/executable_xrandr_manager.bash:812 |
| 120 | `bin/executable_xrandr_manager.bash:863` | `dmenu_select_mode` | script-local | bin/executable_xrandr_manager.bash:842 |
| 121 | `bin/executable_xrandr_manager.bash:897` | `dmenu_select_position` | script-local | bin/executable_xrandr_manager.bash:845 |
| 122 | `bin/executable_xrandr_manager.bash:952` | `show_usage` | script-local | bin/executable_xrandr_manager.bash:1025 |
| 123 | `bin/executable_xrandr_manager.bash:973` | `main` | script-local | bin/executable_xrandr_manager.bash:1031 |
| 124 | `bin/helper/backup.bash:5` | `rclone_systemd` | helper-module private | bin/executable_helper.bash:227 |
| 125 | `bin/helper/backup.bash:22` | `rclone_to_backup` | helper-module private | bin/executable_helper.bash:229,231 |
| 126 | `bin/helper/bash_exec.zsh:22` | `hh_colors` | Zsh public shim | — |
| 127 | `bin/helper/bash_exec.zsh:26` | `hh_unar` | Zsh public shim | bin/helper/shell.bash:42,47,51,65 |
| 128 | `bin/helper/bash_exec.zsh:33` | `hh_upgrade_system` | Zsh public shim | — |
| 129 | `bin/helper/bash_exec.zsh:37` | `hh_yay_no_cache` | Zsh public shim | — |
| 130 | `bin/helper/bash_exec.zsh:41` | `hh_adb_pull_music` | Zsh public shim | — |
| 131 | `bin/helper/bash_exec.zsh:45` | `hh_unzip_books` | Zsh public shim | bin/helper/utils.bash:69,81 |
| 132 | `bin/helper/bash_exec.zsh:49` | `hh_cut_video` | Zsh public shim | — |
| 133 | `bin/helper/bash_exec.zsh:53` | `hh_gpg_decrypt` | Zsh public shim | bin/helper/utils.bash:102 |
| 134 | `bin/helper/bash_exec.zsh:57` | `hh_gpg_encrypt` | Zsh public shim | bin/helper/utils.bash:117 |
| 135 | `bin/helper/bash_exec.zsh:64` | `hh_rsync_ssh` | Zsh public shim | bin/helper/bash_exec.zsh:73; bin/helper/transfer.bash:29,30,46,47,48,49,190; dot_bash_completion.d/transfer.bash:82; dot_zshrc:135,136 |
| 136 | `bin/helper/bash_exec.zsh:68` | `hh_rm_ssh` | Zsh public shim | bin/helper/transfer.bash:114,123,124,125; dot_bash_completion.d/transfer.bash:123; dot_zshrc:137 |
| 137 | `bin/helper/bash_exec.zsh:77` | `hh_i3_save_chezmoi_ws` | Zsh public shim | bin/helper/i3.bash:45 |
| 138 | `bin/helper/bash_exec.zsh:81` | `hh_i3_save_ws` | Zsh public shim | bin/helper/i3.bash:109 |
| 139 | `bin/helper/bash_exec.zsh:85` | `hh_i3_restore_ws` | Zsh public shim | bin/helper/i3.bash:158 |
| 140 | `bin/helper/firefox.bash:8` | `_ff_find_profiles_ini` | helper-module private | bin/helper/firefox.bash:117 |
| 141 | `bin/helper/firefox.bash:20` | `_ff_parse_profiles_ini` | helper-module private | bin/helper/firefox.bash:140 |
| 142 | `bin/helper/firefox.bash:24` | `__emit` | helper-module private | bin/helper/firefox.bash:29,31,40,41 |
| 143 | `bin/helper/firefox.bash:48` | `_ff_launch` | helper-module private | bin/helper/firefox.bash:218 |
| 144 | `bin/helper/firefox.bash:67` | `_ff_profile_is_open` | helper-module private | bin/helper/firefox.bash:135,157,171 |
| 145 | `bin/helper/firefox.bash:90` | `_ff_launch_sandboxed` | helper-module private | bin/helper/firefox.bash:207,249 |
| 146 | `bin/helper/firefox.bash:101` | `_ff_profile_picker` | helper-module private | bin/executable_helper.bash:217 |
| 147 | `bin/helper/firefox.bash:225` | `_ff_open_link` | helper-module private | bin/executable_helper.bash:215 |
| 148 | `bin/helper/git.bash:5` | `hh_git_cleanout` | public hh_ implementation | — |
| 149 | `bin/helper/i3.bash:9` | `_i3_get_host` | helper-module private | bin/helper/i3.bash:60,128,176 |
| 150 | `bin/helper/i3.bash:20` | `_i3_check_ws_num` | helper-module private | bin/helper/i3.bash:123,172,173 |
| 151 | `bin/helper/i3.bash:28` | `_i3_clean_layout` | helper-module private | bin/helper/i3.bash:91,140 |
| 152 | `bin/helper/i3.bash:43` | `hh_i3_save_chezmoi_ws` | public hh_ implementation | bin/helper/bash_exec.zsh:78 |
| 153 | `bin/helper/i3.bash:107` | `hh_i3_save_ws` | public hh_ implementation | bin/helper/bash_exec.zsh:82 |
| 154 | `bin/helper/i3.bash:156` | `hh_i3_restore_ws` | public hh_ implementation | bin/helper/bash_exec.zsh:86 |
| 155 | `bin/helper/shell.bash:8` | `hh_colors` | public hh_ implementation | bin/helper/bash_exec.zsh:23 |
| 156 | `bin/helper/storage.bash:5` | `hh_sshfsctl` | public hh_ implementation (wrapper: runs `~/bin/sshfs.bash "$@"`, `storage.bash:8`) | — |
| 157 | `bin/helper/storage.bash:11` | `hh_gio_mount` | public hh_ implementation | — |
| 158 | `bin/helper/storage.bash:36` | `hh_gio_umount` | public hh_ implementation | — |
| 159 | `bin/helper/system.bash:9` | `get_display` | helper-module private | **— (F1: no caller, unreachable)** |
| 160 | `bin/helper/system.bash:14` | `set_us_ru_layout` | helper-module private | bin/executable_helper.bash:150,175 |
| 161 | `bin/helper/system.bash:24` | `set_us_ge_layout` | helper-module private | bin/executable_helper.bash:153 |
| 162 | `bin/helper/system.bash:34` | `set_background` | helper-module private | bin/executable_helper.bash:187,188; dot_config/i3/config.tmpl:78 |
| 163 | `bin/helper/system.bash:39` | `polybar_start` | helper-module private | bin/executable_helper.bash:146,147,223; dot_config/i3/config.tmpl:102 |
| 164 | `bin/helper/system.bash:47` | `send_notification_brightnes` | helper-module private | bin/executable_helper.bash:110,114 |
| 165 | `bin/helper/system.bash:61` | `send_notification_volume` | helper-module private | bin/executable_helper.bash:144 |
| 166 | `bin/helper/system.bash:81` | `set_volume` | helper-module private | bin/executable_helper.bash:143 |
| 167 | `bin/helper/system.bash:84` | `print_usage` | helper-module private | bin/executable_helper.bash:127; bin/helper/system.bash:104 |
| 168 | `bin/helper/tmux.bash:5` | `tmux_ide_session` | helper-module private | bin/executable_helper.bash:236,237 |
| 169 | `bin/helper/tmux.bash:64` | `tmux_main_session` | helper-module private | bin/executable_helper.bash:234 |
| 170 | `bin/helper/tmux_commands.bash:10` | `hh_tmux_restore` | public hh_ implementation | — |
| 171 | `bin/helper/tmux_commands.bash:49` | `hh_git_watch` | public hh_ implementation | bin/helper/tmux.bash:45,57,135 |
| 172 | `bin/helper/tmux_last_cmd.bash:10` | `_tmux_log_last_cmd` | approved Bash plumbing | bin/helper/tmux_last_cmd.bash:25,26; bin/helper/tmux_last_cmd.zsh:19,20 |
| 173 | `bin/helper/tmux_last_cmd.bash:46` | `_tmux_pane_hist_path` | approved Bash plumbing | bin/helper/tmux_last_cmd.bash:62,78; bin/helper/tmux_last_cmd.zsh:51,80 |
| 174 | `bin/helper/tmux_last_cmd.bash:54` | `_tmux_pane_hist_claim` | approved Bash plumbing | bin/helper/tmux_last_cmd.bash:70,80; bin/helper/tmux_last_cmd.zsh:72,82 |
| 175 | `bin/helper/tmux_last_cmd.bash:60` | `_tmux_pane_hist_sync` | approved Bash plumbing | bin/helper/tmux_last_cmd.bash:94,95; bin/helper/tmux_last_cmd.zsh:90,91 |
| 176 | `bin/helper/tmux_last_cmd.zsh:5` | `_tmux_log_last_cmd` | approved Zsh plumbing | bin/helper/tmux_last_cmd.bash:25,26; bin/helper/tmux_last_cmd.zsh:19,20 |
| 177 | `bin/helper/tmux_last_cmd.zsh:34` | `_tmux_pane_hist_path` | approved Zsh plumbing | bin/helper/tmux_last_cmd.bash:62,78; bin/helper/tmux_last_cmd.zsh:51,80 |
| 178 | `bin/helper/tmux_last_cmd.zsh:42` | `_tmux_pane_hist_claim` | approved Zsh plumbing | bin/helper/tmux_last_cmd.bash:70,80; bin/helper/tmux_last_cmd.zsh:72,82 |
| 179 | `bin/helper/tmux_last_cmd.zsh:49` | `_tmux_pane_hist_detect` | approved Zsh plumbing | bin/helper/tmux_last_cmd.zsh:64,69 |
| 180 | `bin/helper/tmux_last_cmd.zsh:63` | `_tmux_pane_hist_addhistory` | approved Zsh plumbing | bin/helper/tmux_last_cmd.zsh:92,93 |
| 181 | `bin/helper/tmux_last_cmd.zsh:68` | `_tmux_pane_hist_sync` | approved Zsh plumbing | bin/helper/tmux_last_cmd.bash:94,95; bin/helper/tmux_last_cmd.zsh:90,91 |
| 182 | `bin/helper/transfer.bash:9` | `hh_rsync_ssh` | public hh_ implementation | bin/helper/bash_exec.zsh:65,73; bin/helper/transfer.bash:190; dot_bash_completion.d/transfer.bash:82; dot_zshrc:135,136 |
| 183 | `bin/helper/transfer.bash:97` | `hh_rm_ssh` | public hh_ implementation | bin/helper/bash_exec.zsh:69; dot_bash_completion.d/transfer.bash:123; dot_zshrc:137 |
| 184 | `bin/helper/utils.bash:5` | `hh_upgrade_system` | public hh_ implementation | bin/helper/bash_exec.zsh:34 |
| 185 | `bin/helper/utils.bash:43` | `hh_yay_no_cache` | public hh_ implementation | bin/helper/bash_exec.zsh:38 |
| 186 | `bin/helper/utils.bash:51` | `hh_adb_pull_music` | public hh_ implementation | bin/helper/bash_exec.zsh:42 |
| 187 | `bin/helper/utils.bash:56` | `hh_unzip_books` | public hh_ implementation | bin/helper/bash_exec.zsh:46 |
| 188 | `bin/helper/utils.bash:87` | `hh_cut_video` | public hh_ implementation | bin/helper/bash_exec.zsh:50 |
| 189 | `bin/helper/utils.bash:97` | `hh_gpg_decrypt` | public hh_ implementation | bin/helper/bash_exec.zsh:54 |
| 190 | `bin/helper/utils.bash:113` | `hh_gpg_encrypt` | public hh_ implementation | bin/helper/bash_exec.zsh:58 |
| 191 | `dot_bash_completion.d/helper.bash:3` | `_helper_script` | approved Bash plumbing | dot_bash_completion.d/helper.bash:11 |
| 192 | `dot_bash_completion.d/transfer.bash:10` | `_ssh_config_hosts` | approved Bash plumbing | dot_bash_completion.d/transfer.bash:72,116 |
| 193 | `dot_bash_completion.d/transfer.bash:16` | `_flush` | approved Bash plumbing | dot_bash_completion.d/transfer.bash:35,39 |
| 194 | `dot_bash_completion.d/transfer.bash:46` | `_rsync_ssh_complete` | approved Bash plumbing | dot_bash_completion.d/transfer.bash:82,83 |
| 195 | `dot_bash_completion.d/transfer.bash:89` | `_rm_ssh_complete` | approved Bash plumbing | dot_bash_completion.d/transfer.bash:123 |
| 196 | `dot_bashrc:48` | `_bashrc_git_branch` | approved Bash plumbing | dot_bashrc:99 |
| 197 | `dot_xsessionrc:14` | `apply_xsession_input_settings` | helper-module private (sourced) | bin/helper/system.bash:16,26; dot_xsessionrc:38 |
| 198 | `dot_zshrc:28` | `_ctrl_d_exit` | approved Zsh plumbing | dot_zshrc:40,41 |
| 199 | `dot_zshrc:42` | `_reset_ctrl_d_count` | approved Zsh plumbing | dot_zshrc:45,46 |
| 200 | `modify_dot_gitconfig:43` | `passthrough` | script-local | modify_dot_gitconfig:49,59 |
| 201 | `bin/helper/shell.bash:40` | `hh_unar` | public hh_ implementation | bin/helper/bash_exec.zsh:27 |
| 202 | `bin/executable_polybar_volume_all.bash:208` | `flush` (AWK) | embedded AWK, `list_all_devices` program (in `get_devices` at `dc61d977`; split out by #70) | `bin/executable_polybar_volume_all.bash:219,236` (same AWK program, incl. `END`) |
| 203 | `bin/executable_polybar_volume_all.bash:346` | `flush` (AWK) | embedded AWK, `list_all_streams` program (in `list_streams` at `dc61d977`; split out by #70) | `bin/executable_polybar_volume_all.bash:355,373` (same AWK program, incl. `END`) |
| 204 | `bin/executable_tmux_osc52_pbcopy.py:16` | `main` (Python) | script-local | `bin/executable_tmux_osc52_pbcopy.py:42` (`__main__`) |
| 205 | `dot_vimrc:140` | `MoveToNextComma` (Vimscript) | editor config | `dot_vimrc:134` (`xnoremap <C-w>`) |
| 206 | `dot_vimrc:145` | `MoveToPrevComma` (Vimscript) | editor config | `dot_vimrc:137` (`xnoremap <C-b>`) |

### Appendix A.1 — definitions added after `dc61d977` (not in the counts)

The same anchored scan over the 108 current non-test, non-Markdown paths
finds 209 hits (202 at `dc61d977`). `hh_unar` now matches it (it was added
by hand before), and these six are new. They are listed for completeness
only; §4.1 counts and the 206 rows above still describe `dc61d977`. Each
has a same-file caller.

| # | Definition | Name | Class | References outside body |
|---|------------|------|-------|-------------------------|
| A.1-1 | `bin/executable_polybar_volume_all.bash:160` | `is_user_stream` | script-local (added by #70) | bin/executable_polybar_volume_all.bash:338,677,678,679,680,681 |
| A.1-2 | `bin/executable_polybar_volume_all.bash:203` | `list_all_devices` | script-local (added by #70) | bin/executable_polybar_volume_all.bash:198 |
| A.1-3 | `bin/executable_polybar_volume_all.bash:299` | `fx_entry` | script-local (added by #70) | bin/executable_polybar_volume_all.bash:320 |
| A.1-4 | `bin/executable_polybar_volume_all.bash:344` | `list_all_streams` | script-local (added by #70) | bin/executable_polybar_volume_all.bash:340 |
| A.1-5 | `bin/executable_tmux_resurrect_save_filter.bash:33` | `pane_cwd` | script-local (added by 9452b3b) | bin/executable_tmux_resurrect_save_filter.bash:68 |
| A.1-6 | `bin/executable_tmux_resurrect_save_filter.bash:50` | `live_pid` | script-local (added by 9452b3b) | bin/executable_tmux_resurrect_save_filter.bash:66 |

## Appendix B — tracked path manifest

All 131 `git ls-tree -r` entries at `dc61d977`. "Historical last change" is
`git log -1 --date=short` for the path. It is **not** the inspection date;
every path was inspected on 2026-11-05 at the depth given.

**Historical snapshot.** This table is the `dc61d977` tree and was not
re-inventoried in the 2026-11-14 refresh. Since then,
`tests/test_retired_desktop_integration.bash` was removed (900aea9), and
these paths were added: `bin/executable_tmux_bootstrap_cleanup.bash`,
`bin/executable_tmux_resurrect_save_filter.bash` (9452b3b),
`.github/workflows/tests.yml`, `tests/run_all.bash`, `tests/lib/common.bash`,
`tests/lib/tmux_fixture.bash`, `tests/test_lib_common.bash`,
`tests/test_tmux_harness.bash`, `tests/test_polybar_chezmoi_widget.bash`,
and `.claude/skills/` Markdown.

| # | Path | Role | Inspection / disposition | Historical last change |
|---|------|------|--------------------------|------------------------|
| 1 | `.chezmoiignore` | chezmoi target filter (template) | Read: OS/host scope source for §3 | 2026-11-02 6aacb61 |
| 2 | `.github/workflows/validate.yml` | CI workflow | Read: lint/syntax pattern limits recorded (§5.4) | 2026-09-09 a925c3f |
| 3 | `.gitignore` | repo metadata | Read; no executable association | 2026-11-02 6aacb61 |
| 4 | `.gitmodules` | repo metadata | Read; no executable association | 2026-06-17 6ba1065 |
| 5 | `AGENTS.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-10-07 273cb97 |
| 6 | `CLAUDE.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-10-27 ee66e2d |
| 7 | `Library/LaunchAgents/local.tmux.plist.tmpl` | macOS LaunchAgent (template) | G1 association A54 | 2026-09-25 19f8a0c |
| 8 | `TODO.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-11-02 6aacb61 |
| 9 | `ai-wrapper` | submodule gitlink (db66133) | Excluded: not traversed; gitlink unchanged | 2026-10-27 56796c0 |
| 10 | `bin/executable_asusctl_rofi.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 11 | `bin/executable_check_dir_usage.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 12 | `bin/executable_firefox_rofi.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 13 | `bin/executable_helper.bash` | owned dispatcher + interactive loader | G1 chain B1; G2 definitions + dispatch actions | 2026-11-02 6aacb61 |
| 14 | `bin/executable_i3_workspaces.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-03 e020f24 |
| 15 | `bin/executable_input_device_handler.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-18 23783ed |
| 16 | `bin/executable_polybar-supervisor.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 17 | `bin/executable_polybar_chezmoi_widget.sh` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-31 bd8ac4e |
| 18 | `bin/executable_polybar_lang_menu.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-03 e020f24 |
| 19 | `bin/executable_polybar_system_stats.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-18 23783ed |
| 20 | `bin/executable_polybar_volume_all.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-05 a5e3726 |
| 21 | `bin/executable_sshfs-mount.sh` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 22 | `bin/executable_sshfs.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 23 | `bin/executable_tmux_boot.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-11-05 dc61d97 |
| 24 | `bin/executable_tmux_git_branch.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 25 | `bin/executable_tmux_osc52_pbcopy.py` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-12 73ebbb1 |
| 26 | `bin/executable_tmux_pane_hist_release.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-09-28 fe0112c |
| 27 | `bin/executable_tmux_pipe_pane_init.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-12 73ebbb1 |
| 28 | `bin/executable_tmux_prefill_last_cmd.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-11-05 dc61d97 |
| 29 | `bin/executable_xrandr_dmenu_test.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-03 f0fdcb3 |
| 30 | `bin/executable_xrandr_keymap_watcher.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-03 e020f24 |
| 31 | `bin/executable_xrandr_manager.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-10-03 e020f24 |
| 32 | `bin/executable_yt_playlist_mp3.bash` | owned executable script | G1 chain (§3.2); G2 definitions (App. A) | 2026-06-18 23783ed |
| 33 | `bin/helper/README.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-11-02 6aacb61 |
| 34 | `bin/helper/aliases.shrc` | shared alias file | Read: alias hh_cp_ssh not here; aliases wrap ls/grep/xclip/vim/xev/unzip | 2026-11-02 6aacb61 |
| 35 | `bin/helper/backup.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-06-03 f0fdcb3 |
| 36 | `bin/helper/bash_exec.zsh` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 37 | `bin/helper/common.bash` | exported variable module | G2 variables (§4.3) | 2026-06-03 f0fdcb3 |
| 38 | `bin/helper/firefox.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-06-03 f0fdcb3 |
| 39 | `bin/helper/git.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 40 | `bin/helper/i3.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 41 | `bin/helper/shell.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 42 | `bin/helper/storage.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 43 | `bin/helper/system.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-06-18 23783ed |
| 44 | `bin/helper/tmux.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 45 | `bin/helper/tmux_commands.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 46 | `bin/helper/tmux_last_cmd.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-05 dc61d97 |
| 47 | `bin/helper/tmux_last_cmd.zsh` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-05 dc61d97 |
| 48 | `bin/helper/transfer.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 49 | `bin/helper/utils.bash` | helper module (sourced) | G2 definitions (App. A); tool deps §3.2 | 2026-11-02 6aacb61 |
| 50 | `bin/modify_dot_env.tmpl` | chezmoi modify_ script for ~/bin/.env | G2 variables; requires bash/awk | 2026-09-23 900106a |
| 51 | `docs/README.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-10-31 0d46a7f |
| 52 | `docs/agent-skill-distribution.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-10-31 0d46a7f |
| 53 | `docs/ai-agent-sandboxing.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-10-31 0d46a7f |
| 54 | `docs/completed/2025-11-18-helper-bash-refactor.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 55 | `docs/completed/2025-12-05-xrandr-screen-management.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 56 | `docs/completed/2025-12-18-unify-ai-agent-rules.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 57 | `docs/helper_refactor_plan.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 58 | `docs/plans/2026-03-28-bulletproof-skill-improvements.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 59 | `docs/plans/2026-04-02-ai-rules-repository-migration.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 60 | `docs/plans/2026-06-10-repo-split-ai-wrapper-context.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-17 6ba1065 |
| 61 | `docs/plans/2026-06-10-repo-split-ai-wrapper.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-17 6ba1065 |
| 62 | `docs/repository-overview.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-18 79477bf |
| 63 | `docs/systemd-services.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-11-05 dc61d97 |
| 64 | `docs/xrandr-manager.md` | documentation / agent rules | Excluded from orphan scope (non-deployed; .chezmoiignore docs/, TODO.md) | 2026-06-03 f0fdcb3 |
| 65 | `dot_bash_completion.d/helper.bash` | Bash completion | G2 approved plumbing (App. A) | 2026-06-18 23783ed |
| 66 | `dot_bash_completion.d/transfer.bash` | Bash completion | G2 approved plumbing (App. A) | 2026-11-02 6aacb61 |
| 67 | `dot_bash_profile` | login shell rc | Read: sources ~/.bashrc; no external executable | 2026-09-23 900106a |
| 68 | `dot_bashrc` | interactive shell rc | G1 A64/A65; G2 variables + plumbing | 2026-11-02 6aacb61 |
| 69 | `dot_config/.keep` | empty directory marker | No content | 2026-06-03 f0fdcb3 |
| 70 | `dot_config/alacritty/alacritty.toml.tmpl` | Alacritty config (template) | G1 declarative (consumer alacritty) | 2026-09-25 c86e029 |
| 71 | `dot_config/chezmoi/.keep` | empty directory marker | No content | 2026-06-03 f0fdcb3 |
| 72 | `dot_config/chezmoi/chezmoi.toml.tmpl` | chezmoi config template | G1 declarative (consumer chezmoi; git autoCommit/autoPush) | 2026-09-09 a925c3f |
| 73 | `dot_config/dunst/dunstrc` | dunst config | G1 A61 | 2026-06-03 f0fdcb3 |
| 74 | `dot_config/environment.d/create_rclone-bisync.conf` | create_ env file (rclone-bisync.conf) | G2 BISYNC_* variables; EnvironmentFile of 8 rclone units | 2026-09-25 c86e029 |
| 75 | `dot_config/i3/config.tmpl` | i3 config (template) | G1 associations A1–A32, window rules §3.3 | 2026-10-31 bd8ac4e |
| 76 | `dot_config/i3/workspaces/workspace_4-dragoncave.json` | i3 append_layout JSON | G1 non-executing (§3.3) | 2026-06-03 f0fdcb3 |
| 77 | `dot_config/i3/workspaces/workspace_4-dragonlady.json` | i3 append_layout JSON | G1 non-executing (§3.3) | 2026-09-04 aab096d |
| 78 | `dot_config/keepassxc/modify_keepassxc.ini` | chezmoi modify_ script (python3), KeePassXC protected | G1 A67; gated by .chezmoiignore on existing keepassxc.ini | 2026-09-23 900106a |
| 79 | `dot_config/libinput-gestures.conf` | libinput-gestures config | G1 A62 | 2026-10-03 e020f24 |
| 80 | `dot_config/polybar/config-dragoncave.ini` | polybar per-host include | G1 declarative; consumed via include-file config.ini.tmpl:19 | 2026-06-03 f0fdcb3 |
| 81 | `dot_config/polybar/config-dragonlady.ini` | polybar per-host include | G1 declarative; consumed via include-file config.ini.tmpl:19 | 2026-06-03 f0fdcb3 |
| 82 | `dot_config/polybar/config.ini.tmpl` | polybar config (template) | G1 A33–A38 | 2026-10-03 e020f24 |
| 83 | `dot_config/private_gtk-3.0/settings.ini` | declarative desktop settings | G1 declarative (§3.4) | 2026-06-03 f0fdcb3 |
| 84 | `dot_config/private_gtk-4.0/settings.ini` | declarative desktop settings | G1 declarative (§3.4) | 2026-06-03 f0fdcb3 |
| 85 | `dot_config/private_mimeapps.list` | XDG MIME associations | G1 non-executing desktop-ID associations (§3.3) | 2026-10-31 bd8ac4e |
| 86 | `dot_config/private_user-dirs.dirs` | declarative desktop settings | G1 declarative (§3.4) | 2026-06-03 f0fdcb3 |
| 87 | `dot_config/systemd/user/failure-notification@.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 88 | `dot_config/systemd/user/rclone-encrypt-cloud-bisync-resync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 89 | `dot_config/systemd/user/rclone-encrypt-cloud-bisync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 90 | `dot_config/systemd/user/rclone-encrypt-cloud-bisync.timer` | systemd user timer | G1: activates same-name .service (no executable itself) | 2026-06-03 f0fdcb3 |
| 91 | `dot_config/systemd/user/rclone-linux-cloud-bisync-resync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 92 | `dot_config/systemd/user/rclone-linux-cloud-bisync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 93 | `dot_config/systemd/user/rclone-linux-cloud-bisync.timer` | systemd user timer | G1: activates same-name .service (no executable itself) | 2026-06-03 f0fdcb3 |
| 94 | `dot_config/systemd/user/rclone-media-cloud-bisync-resync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 95 | `dot_config/systemd/user/rclone-media-cloud-bisync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 96 | `dot_config/systemd/user/rclone-media-cloud-bisync.timer` | systemd user timer | G1: activates same-name .service (no executable itself) | 2026-06-03 f0fdcb3 |
| 97 | `dot_config/systemd/user/rclone-minecraft-local-bisync-resync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 98 | `dot_config/systemd/user/rclone-minecraft-local-bisync.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 99 | `dot_config/systemd/user/rclone-minecraft-local-bisync.timer` | systemd user timer | G1: activates same-name .service (no executable itself) | 2026-06-03 f0fdcb3 |
| 100 | `dot_config/systemd/user/sshfs@.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 101 | `dot_config/systemd/user/success-notification@.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 102 | `dot_config/systemd/user/syncthing.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 103 | `dot_config/systemd/user/tmux.service` | systemd user unit | G1 association (§3.1) | 2026-09-25 19f8a0c |
| 104 | `dot_config/systemd/user/yt-mp3.service` | systemd user unit | G1 association (§3.1) | 2026-06-03 f0fdcb3 |
| 105 | `dot_config/systemd/user/yt-mp3.timer` | systemd user timer | G1: activates same-name .service (no executable itself) | 2026-06-03 f0fdcb3 |
| 106 | `dot_config/tmux/tmux.conf.tmpl` | tmux config (template) | G1 A39–A47 | 2026-11-05 dc61d97 |
| 107 | `dot_dir_colors` | dircolors database | G1 declarative (consumer dircolors via rc files) | 2026-06-03 f0fdcb3 |
| 108 | `dot_local/share/applications/calculator.desktop` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 109 | `dot_local/share/applications/calendar.desktop` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 110 | `dot_local/share/applications/chromium-insecure.desktop` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 111 | `dot_local/share/applications/com.uploadedlobster.peek.desktop` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 112 | `dot_local/share/applications/firefox.desktop.tmpl` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 113 | `dot_local/share/applications/opera-insecure.desktop` | desktop entry | G1 associations A55–A60 | 2026-06-03 f0fdcb3 |
| 114 | `dot_vimrc` | Vim config | G1 declarative (consumer vim); G2 Vimscript functions | 2026-06-03 f0fdcb3 |
| 115 | `dot_xsessionrc` | X session rc (sourced) | G1 A63; G2 GDK_SCALE, apply_xsession_input_settings | 2026-10-03 e020f24 |
| 116 | `dot_zshrc` | interactive shell rc | G1 A64/A65; G2 variables + plumbing | 2026-11-02 6aacb61 |
| 117 | `modify_dot_gitconfig` | chezmoi modify_ script for ~/.gitconfig | G1 A66 (git); G2 passthrough | 2026-10-07 273cb97 |
| 118 | `run_always_install-ai-wrapper.bash` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-09-09 a925c3f |
| 119 | `run_always_manage-local-symlink.bash.tmpl` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-09-09 a925c3f |
| 120 | `run_always_setup-git-hooks.bash` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-06-17 6ba1065 |
| 121 | `run_once_create_firefox_profiles.bash` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-06-03 f0fdcb3 |
| 122 | `run_once_install-tpm-plugins.bash` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-09-28 fe0112c |
| 123 | `run_onchange_enable-tmux-service.bash.tmpl` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-09-28 fe0112c |
| 124 | `run_onchange_load-tmux-launchagent.bash.tmpl` | chezmoi run_ installer | G1 A68 (installer interfaces); not executed | 2026-09-25 19f8a0c |
| 125 | `tests/lib/shell_fixture.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-11-05 dc61d97 |
| 126 | `tests/pty_drive.py` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-11-05 dc61d97 |
| 127 | `tests/test_agent_skill_distribution.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-10-31 0d46a7f |
| 128 | `tests/test_hh_public_api.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-11-05 dc61d97 |
| 129 | `tests/test_retired_desktop_integration.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5). **Removed in 900aea9** | 2026-10-31 bd8ac4e |
| 130 | `tests/test_shell_helper_isolation.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-11-05 dc61d97 |
| 131 | `tests/test_tmux_preservation.bash` | regression test / fixture | Excluded from orphan inventory; executed as evidence (§5) | 2026-11-05 dc61d97 |
