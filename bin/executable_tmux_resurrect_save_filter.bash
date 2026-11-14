#!/bin/bash
# Called by tmux-resurrect via @resurrect-hook-post-save-layout with the
# path of the snapshot it just wrote, before it compares that file with
# `last` and moves the `last` link. Rewrites the file in place:
#
# 1. Drops bootstrap sessions (_tmux_boot_<pid>, _main_boot_<pid>): they
#    are placeholders, and a saved one is restored as a real session on
#    every later boot.
# 2. Fills an empty pane path. tmux reports #{pane_current_path} from the
#    pane's foreground process; on macOS it has no fallback when that
#    process cannot be inspected (Linux falls back to the pane's shell),
#    so resurrect saved `:` and restored the pane with `-c ""`, which
#    tmux resolves against the server's cwd — `/` under launchd. The
#    pane's own shell (#{pane_pid}) is asked instead: /proc on Linux,
#    lsof on macOS.
# 3. If nothing is left (a server holding only bootstrap sessions), puts
#    the previous snapshot's bytes back, so resurrect sees no change and
#    keeps `last` instead of replacing it with an empty snapshot.
#
# Bash 3.2 compatible (macOS /bin/bash). Any failure leaves the file as
# resurrect wrote it.
set -uo pipefail

file="${1:-}"
[[ -f "${file}" ]] || exit 0
last="$(dirname "${file}")/last"
BOOT_RE='^_(tmux|main)_boot_[0-9]+$'
# lsof lives in /usr/sbin on macOS; the launchd/systemd PATH lacks it.
PATH="${PATH}:/usr/sbin:/usr/bin"

# pane_cwd <pid>: working directory of a process, empty when unknown.
# /proc first (Linux), then lsof (macOS has no /proc).
pane_cwd() {
    local dir
    dir=$(readlink "/proc/$1/cwd" 2>/dev/null)
    [[ -n "${dir}" ]] || dir=$(lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)
    printf '%s' "${dir}"
}

tmp="${file}.filter.$$"
paths="${file}.paths.$$"
trap 'rm -f "${tmp}" "${paths}"' EXIT

# Shell PIDs from one list-panes: display-message does not fail for a
# pane that is gone (it answers with the current pane), so a pane closed
# since the save would get another pane's directory.
live=$(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_pid}' 2>/dev/null) || live=""

# live_pid <session> <window> <pane>: the pane's shell PID, if it is live.
live_pid() {
    local s w p pid
    while IFS=$'\t' read -r s w p pid; do
        if [[ "${s}" == "$1" && "${w}" == "$2" && "${p}" == "$3" ]]; then
            printf '%s' "${pid}"
            return 0
        fi
    done <<<"${live}"
    return 1
}

# One "session<TAB>window<TAB>pane<TAB>path" line per pane whose saved
# path is empty. Written unescaped, like resurrect's own save (a
# backslash in a path does not survive resurrect's restore either).
awk -F '\t' '$1 == "pane" && $8 == ":" { print $2 "\t" $3 "\t" $6 }' "${file}" \
| while IFS=$'\t' read -r session window pane; do
    pid=$(live_pid "${session}" "${window}" "${pane}") || continue
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    dir=$(pane_cwd "${pid}")
    [[ "${dir}" == /* ]] || continue
    printf '%s\t%s\t%s\t%s\n' "${session}" "${window}" "${pane}" "${dir}"
done > "${paths}"

awk -F '\t' -v OFS='\t' -v boot="${BOOT_RE}" -v paths="${paths}" '
    BEGIN {
        while ((getline line < paths) > 0) {
            split(line, f, "\t")
            dir[f[1] "\t" f[2] "\t" f[3]] = f[4]
        }
    }
    ($1 == "pane" || $1 == "window") && $2 ~ boot { next }
    $1 == "grouped_session" && ($2 ~ boot || $3 ~ boot) { next }
    $1 == "pane" && $8 == ":" && (($2 "\t" $3 "\t" $6) in dir) {
        $8 = ":" dir[$2 "\t" $3 "\t" $6]
    }
    { print }
' "${file}" > "${tmp}" || exit 0

if ! grep -q '^pane' "${tmp}" && [[ -f "${last}" ]] && grep -q '^pane' "${last}"; then
    cat "${last}" > "${file}"
else
    cat "${tmp}" > "${file}"
fi
exit 0
