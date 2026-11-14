#!/bin/bash
# Helper Storage Module - Mount and unmount operations
# No dependencies

function hh_sshfsctl() {
    # Open the interactive SSHFS mount manager (~/bin/sshfs.bash)
    # Usage: hh_sshfsctl [mount|umount|status|help]
    "${HOME}/bin/sshfs.bash" "$@"
}

function hh_gio_mount() {
    # Mount phone/device via GIO and change to its mount point.
    # Errors go to stderr and return non-zero; the caller's shell is never
    # exited and its directory is left alone on failure.
    local phone_path mount_point
    phone_path="$(gio mount -li | sed -n 's/^.*activation_root=//p' | head -n 1)"
    if [[ -z "${phone_path}" ]]; then
        echo "hh_gio_mount: no device found (gio mount -li)" >&2
        return 1
    fi
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        gio mount "${phone_path}" || return
    fi
    mount_point="$(gio info "${phone_path}" | sed -n 's/^local path: //p' | head -n 1)"
    if [[ -z "${mount_point}" ]]; then
        echo "hh_gio_mount: ${phone_path} has no local path" >&2
        return 1
    fi
    if [[ ! -d "${mount_point}" ]]; then
        echo "hh_gio_mount: mount point ${mount_point} is not a directory" >&2
        return 1
    fi
    cd "${mount_point}"
}

function hh_gio_umount() {
    # Unmount phone/device via GIO; leaves the mount point first if the
    # caller is inside it.
    local phone_path mount_point
    phone_path="$(gio mount -li | sed -n 's/^.*activation_root=//p' | head -n 1)"
    if [[ -z "${phone_path}" ]]; then
        echo "hh_gio_umount: no device found (gio mount -li)" >&2
        return 1
    fi
    if ! gio info "${phone_path}" > /dev/null 2>&1; then
        echo "hh_gio_umount: ${phone_path} is not mounted" >&2
        return 1
    fi
    mount_point="$(gio info "${phone_path}" | sed -n 's/^local path: //p' | head -n 1)"
    if [[ -n "${mount_point}" && "${PWD}/" == "${mount_point%/}/"* ]]; then
        cd "${HOME}" || return
    fi
    gio mount -u "${phone_path}"
}
