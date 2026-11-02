# zsh entry points for public helpers whose bodies need Bash semantics
# (mapfile, word splitting of unquoted args, failed-glob handling,
# printf %q for remote commands). Sourced by dot_zshrc.
#
# Each wrapper runs the unchanged module in a child `bash -c`: the child
# inherits cwd, environment and stdin; stdout, stderr, exit status and
# quoted/empty arguments pass through untouched; module internals
# (_i3_* etc.) never enter this shell. The child enables the shared
# aliases before sourcing the module, so bodies expand them exactly as in
# an interactive bash. `&&` stops a failed source from calling an
# undefined function. $0 inside the child is the module path.
#
# Helpers that change caller state (hh_gio_mount/hh_gio_umount cwd,
# hh_sshfsctl shell options) or are portable (hh_git_cleanout,
# hh_tmux_restore, hh_git_watch) are sourced in-process by dot_zshrc.
# Wrappers are defined only for modules present on this host (macOS skips
# the Linux-only i3/utils modules).

if (( $+commands[bash] )); then
    if [[ -r "${HOME}/bin/helper/shell.bash" ]]; then
        hh_colors() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_colors "$@"' \
                "${HOME}/bin/helper/shell.bash" "$@"
        }
        hh_ex() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_ex "$@"' \
                "${HOME}/bin/helper/shell.bash" "$@"
        }
    fi

    if [[ -r "${HOME}/bin/helper/utils.bash" ]]; then
        hh_upgrade_system() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_upgrade_system "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_yay_no_cache() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_yay_no_cache "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_adb_pull_music() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_adb_pull_music "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_unzip_books() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_unzip_books "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_cut_video() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_cut_video "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_gpg_decrypt() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_gpg_decrypt "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
        hh_gpg_encrypt() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_gpg_encrypt "$@"' \
                "${HOME}/bin/helper/utils.bash" "$@"
        }
    fi

    if [[ -r "${HOME}/bin/helper/transfer.bash" ]]; then
        hh_rsync_ssh() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_rsync_ssh "$@"' \
                "${HOME}/bin/helper/transfer.bash" "$@"
        }
        hh_rm_ssh() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_rm_ssh "$@"' \
                "${HOME}/bin/helper/transfer.bash" "$@"
        }
        # Same alias transfer.bash defines for bash.
        alias hh_cp_ssh='hh_rsync_ssh'
    fi

    if [[ -r "${HOME}/bin/helper/i3.bash" ]]; then
        hh_i3_save_chezmoi_ws() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_i3_save_chezmoi_ws "$@"' \
                "${HOME}/bin/helper/i3.bash" "$@"
        }
        hh_i3_save_ws() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_i3_save_ws "$@"' \
                "${HOME}/bin/helper/i3.bash" "$@"
        }
        hh_i3_restore_ws() {
            bash -c 'shopt -s expand_aliases; [[ -r ~/bin/helper/aliases.shrc ]] && source ~/bin/helper/aliases.shrc; source "$0" && hh_i3_restore_ws "$@"' \
                "${HOME}/bin/helper/i3.bash" "$@"
        }
    fi
fi
