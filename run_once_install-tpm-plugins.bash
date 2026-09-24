#!/bin/bash
# Bootstrap the tmux plugin manager (tpm) and install the plugins declared
# in tmux.conf.tmpl (tmux-resurrect, tmux-continuum). Runs once on
# `chezmoi apply` — safe to re-run: git clone is idempotent-guarded and
# install_plugins is a no-op when everything is present.
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"

if [[ ! -d "${TPM_DIR}" ]]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "${TPM_DIR}"
fi

# tpm's install_plugins queries a live tmux server via `tmux
# show-environment TMUX_PLUGIN_MANAGER_PATH`. `chezmoi apply` has no
# server. Spin one up on an isolated socket (custom TMUX_TMPDIR) so the
# user's active server — if any — is not disturbed, install, tear down.
sock_dir=$(mktemp -d)
export TMUX_TMPDIR="${sock_dir}"
trap 'tmux kill-server 2>/dev/null || true; rm -rf "${sock_dir}"' EXIT

tmux new-session -d -s _tpm_install \
    \; set-environment -g TMUX_PLUGIN_MANAGER_PATH "${HOME}/.tmux/plugins/"

"${TPM_DIR}/bin/install_plugins"
