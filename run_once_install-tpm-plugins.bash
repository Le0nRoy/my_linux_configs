#!/bin/bash
# Bootstrap the tmux plugin manager (tpm) and install the plugins declared
# in tmux.conf.tmpl (tmux-resurrect, tmux-continuum). Runs once on
# `chezmoi apply` — safe to re-run: git clone is idempotent-guarded and
# install_plugins is a no-op when everything is present.
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"
# Pin to a tag so a future upstream compromise is not silently adopted on
# the next chezmoi apply on a fresh host. Bump the tag when tpm ships a
# release worth taking, and update TPM_TAG_SHA to the tag's commit SHA.
TPM_TAG="v3.1.0"
TPM_TAG_SHA="7bdb7ca33c9cc6440a600202b50142f401b6fe21"

if [[ ! -d "${TPM_DIR}" ]]; then
    git clone --depth 1 --branch "${TPM_TAG}" https://github.com/tmux-plugins/tpm "${TPM_DIR}"
fi

# Verify tpm's cloned HEAD SHA against the pinned commit. Refuses to
# proceed if the upstream tag was force-pushed to a different commit —
# defends against a supply-chain compromise where an attacker rewrites
# the tag between two fresh chezmoi apply runs.
actual_sha=$(git -C "${TPM_DIR}" rev-parse HEAD)
if [[ "${actual_sha}" != "${TPM_TAG_SHA}" ]]; then
    echo "tpm SHA mismatch: expected ${TPM_TAG_SHA}, got ${actual_sha}" >&2
    echo "Refusing to install plugins. Investigate before bumping TPM_TAG_SHA." >&2
    exit 1
fi

# tpm's install_plugins queries a live tmux server via `tmux
# show-environment TMUX_PLUGIN_MANAGER_PATH`. `chezmoi apply` has no
# server. Spin one up on an isolated socket (custom TMUX_TMPDIR) so the
# user's active server — if any — is not disturbed, install, tear down.
# TMUX_PLUGIN_MANAGER_PATH is set inside tmux.conf itself, so loading
# the config alone is enough — no per-session `set-environment` needed.

# unset variables set by live tmux session to allow script invocation from live tmux session
unset TMUX TMUX_PANE
sock_dir=$(mktemp -d)
export TMUX_TMPDIR="${sock_dir}"
trap 'tmux kill-server 2>/dev/null || true; rm -rf "${sock_dir}"' EXIT

tmux new-session -d -s _tpm_install

"${TPM_DIR}/bin/install_plugins"
