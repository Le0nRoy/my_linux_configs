#!/bin/bash
# Firefox profile rofi launcher — delegates to helper.bash (single source of truth)
exec "${HOME}/bin/helper.bash" firefox "$@"
