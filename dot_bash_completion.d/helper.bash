# Bash completion for helper.bash

_helper_script() {
    local cur
    _init_completion || return

    COMPREPLY=($(compgen -W '$(sed --sandbox -En "s/^\s+\"(.*)\"\)/\1/p" "${HOME}/bin/helper.bash")' -- "${cur}"))
}
complete -F _helper_script helper.bash
