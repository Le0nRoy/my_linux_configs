#!/bin/bash
# Helper Storage Module - Mount and unmount operations
# No dependencies

function hh_sshfsctl() {
    # Open the interactive SSHFS mount manager (~/bin/sshfs.bash)
    # Usage: hh_sshfsctl [mount|umount|status|help]
    "${HOME}/bin/sshfs.bash" "$@"
}

function hh_gio_mount() {
    # Mount phone/device via GIO and change to mount point
    local phone_path
    phone_path="$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')"
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        gio mount "${phone_path}"
    fi
    local mount_point
    mount_point="$(gio info "${phone_path}" | awk '/local path/{print $3}')"
    cd "${mount_point}" || exit 1
}

function hh_gio_umount() {
    # Unmount phone/device via GIO
    local phone_path
    phone_path="$(gio mount -li | grep activation_root | awk 'sub("^.*=", "")')"
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        local mount_point
        mount_point="$(gio info "${phone_path}" | awk '/local path/{print $3}')"
        if [[ "${PWD}" == "${mount_point}" ]]; then
            cd "${HOME}" || exit 1
        fi
        gio mount -u "${phone_path}"
    fi
}
