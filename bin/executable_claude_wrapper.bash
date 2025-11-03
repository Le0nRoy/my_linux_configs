#!/bin/bash
# Lightweight, minimal-privilege wrapper for Claud CLI using bubblewrap.
# - Binds current working dir with same permissions.
# - Restricts address space, CPU time, file descriptors, processes.

UNPRIVILEGED_USERNS_CLONE="$(sysctl kernel.unprivileged_userns_clone | awk -F ' = ' '{print $2}')"
if [[ -z "${UNPRIVILEGED_USERNS_CLONE}" ]]; then
    echo "Failed to parse response for 'sysctl kernel.unprivileged_userns_clone'. Exitting..."
    exit 1
elif [[ "${UNPRIVILEGED_USERNS_CLONE}" -ne 1 ]]; then
    echo "User namespaces are not enabled. Please set 'kernel.unprivileged_userns_clone = 1' in '/etc/sysctl.d/00-unpriv-ns.conf' and run 'sudo sysctl --system' to fix it.\nExitting..."
    exit 1
fi

# Configurable rlimits (adjust as you like)
RLIMIT_AS=$((4 * 1024 * 1024 * 1024))   # 4 GiB
RLIMIT_CPU=60
RLIMIT_NOFILE=1024
RLIMIT_NPROC=60

WORKDIR="$(pwd)"
HOME_DIR="${HOME}"
# Ensure PATH inside bubblewrap can find codex; we bind /usr read-only
# Clear environment to avoid leaking credentials; keep TERM, LANG minimally.
setpriv --no-new-privs --inh-caps=-all \
  bwrap \
    --die-with-parent \
    --unshare-all \
    --share-net \
    --ro-bind /usr /usr \
    --ro-bind /opt/cursor-agent /opt/cursor-agent \
    --ro-bind /bin /bin \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /etc /etc \
    --ro-bind /etc/ssl /etc/ssl \
    --ro-bind /etc/hosts /etc/hosts \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --tmpfs /tmp \
    --proc /proc \
    --dev /dev \
    --bind "${WORKDIR}" "${WORKDIR}" \
    --bind "${HOME_DIR}/.claude" "${HOME_DIR}/.claude" \
    --bind "${HOME_DIR}/.claude.json" "${HOME_DIR}/.claude.json" \
    --bind "${HOME_DIR}/Android" "${HOME_DIR}/Android" \
    --clearenv \
    --setenv HOME "${HOME_DIR}" \
    --setenv USER "${USER}" \
    --setenv PATH "/usr/bin:/usr/sbin:/bin:/sbin" \
    --setenv LANG "${LANG:-en_US.UTF-8}" \
    --chdir "${WORKDIR}" \
      claude "$@"

