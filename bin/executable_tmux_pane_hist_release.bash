#!/bin/bash
# Release a per-pane shell history file (see bin/helper/tmux.bash and
# bin/helper/tmux_last_cmd.zsh) so a pane that later takes the same
# #S:#I.#P position does not inherit a dead pane's history.
#
# Usage:
#   tmux_pane_hist_release.bash <pane_id>          # pane exited (tmux pane-exited hook)
#   tmux_pane_hist_release.bash <pane_id> <file>   # pane moved away from <file>
#
# Each shell records which file it writes in ${state}/.owner.<pane_id>.
# A file is deleted (with its matching .last) only when no other LIVE
# pane still claims it — two panes swapping positions each write the
# other's file before they have both synced.
#
# Not called on kill-server / crash / kill-pane: tmux fires pane-exited
# only when the shell exits by itself, so files survive for resurrect.
set -euo pipefail

pane_id="${1:?pane id required}"
state="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/panes"
owner="${state}/.owner.${pane_id}"

if [[ $# -ge 2 ]]; then
    file="$2"
else
    [[ -r "${owner}" ]] || exit 0
    file=$(<"${owner}")
    rm -f "${owner}"
fi
[[ -n "${file}" && "${file}" == "${state}/"* ]] || exit 0

live=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)
for claim in "${state}"/.owner.*; do
    [[ -e "${claim}" ]] || continue
    claim_id="${claim##*/.owner.}"
    [[ "${claim_id}" == "${pane_id}" ]] && continue
    if ! grep -qxF -- "${claim_id}" <<<"${live}"; then
        # Pane is gone without firing pane-exited (killed); drop its claim.
        rm -f "${claim}"
        continue
    fi
    [[ "$(<"${claim}")" == "${file}" ]] && exit 0
done

rm -f "${file}" "${file%.*_history}.last"
