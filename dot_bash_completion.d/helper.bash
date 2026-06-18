# Bash completion for helper.bash

_helper_script() {
    local cur
    _init_completion || return

    local cmds
    cmds="$(sed --sandbox -En 's/^\s+"(.*)"\)/\1/p' "${HOME}/bin/helper.bash")"
    mapfile -t COMPREPLY < <(compgen -W "${cmds}" -- "${cur}")
}
complete -F _helper_script helper.bash
