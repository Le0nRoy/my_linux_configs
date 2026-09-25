# Portable tmux user commands, sourced by both bash (via helper.bash's
# module loop) and zsh (via dot_zshrc's helper loop). Keep syntax to
# the bash/zsh common subset.

# Restore the last saved tmux state and attach. If a live server is
# already up, just attach. Otherwise kick the OS-native service that
# owns the server (LaunchAgent on macOS, systemd --user on Linux) —
# tmux_boot.bash will spawn a server and fire tmux-resurrect's
# restore.sh, then this function attaches.
tmux_restore() {
    # Nested tmux would fail with "sessions should be nested with care".
    if [[ -n "${TMUX:-}" ]]; then
        echo "tmux_restore: already inside tmux (\$TMUX=${TMUX})" >&2
        return 1
    fi

    if tmux list-sessions >/dev/null 2>&1; then
        tmux attach
        return
    fi

    case "$(uname -s)" in
        Darwin)
            launchctl kickstart "gui/$(id -u)/local.tmux" || return
            ;;
        Linux)
            systemctl --user start tmux.service || return
            ;;
        *)
            echo "tmux_restore: unsupported OS $(uname -s)" >&2
            return 1
            ;;
    esac

    # Poll for tmux_boot.bash to spawn the server + resurrect populate
    # sessions. 30 * 0.2s = 6s upper bound; typically resolves in < 1s.
    for _ in $(seq 1 30); do
        tmux list-sessions >/dev/null 2>&1 && break
        sleep 0.2
    done

    tmux attach
}

# Watch git branch + short status in the current pane. Same command
# tmux_ide_session pre-runs in its "dev" pane, factored out for reuse.
# Falls back to a shell loop on hosts without the GNU `watch` utility
# (default macOS install).
git_watch() {
    if command -v watch >/dev/null 2>&1; then
        watch 'git branch --show-current; git status --short'
    else
        while :; do
            clear
            git branch --show-current
            git status --short
            sleep 2
        done
    fi
}
