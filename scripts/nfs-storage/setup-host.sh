#!/bin/bash
# setup-host.sh - Set up NFS Corral mount for CKAN data storage on a new server
#
# Run once with root access. Safe to re-run (idempotent).
# Does NOT create host-level users or groups -- container-side permissions
# are handled by the production Dockerfile. It only sets the numeric group
# on the data directories so the container user can read and write them.

set -euo pipefail

NFS_SOURCE="129.114.52.151:/corral/main/utexas/BCS24011/ckan"
MOUNT_POINT="/corral/utexas/BCS24011/ckan"
FSTAB_ENTRY="${NFS_SOURCE} ${MOUNT_POINT} nfs rw,nosuid,_netdev,rsize=1048576,wsize=1048576,intr,nfsvers=3,tcp 0 0"
DATA_SYMLINK="/data/ckan"
STORAGE_GID=826471

echo "=== CKAN NFS Corral Storage Setup ==="
echo ""

# 1. Check running as root
if [[ $EUID -ne 0 ]]; then
    echo "[FAIL] This script must be run as root (sudo bash setup-host.sh)"
    exit 1
fi
echo "[OK] Running as root"

# 2. Add fstab entry if not present
if grep -qF "${NFS_SOURCE}" /etc/fstab; then
    echo "[OK] fstab entry already present"
else
    echo "${FSTAB_ENTRY}" >> /etc/fstab
    echo "[OK] Added fstab entry:"
    echo "     ${FSTAB_ENTRY}"
fi

# 3. Create mount point directory
if [[ -d "${MOUNT_POINT}" ]]; then
    echo "[OK] Mount point ${MOUNT_POINT} already exists"
else
    mkdir -p "${MOUNT_POINT}"
    echo "[OK] Created mount point ${MOUNT_POINT}"
fi

# 4. Attempt NFS mount
if mount | grep -qF "${MOUNT_POINT}"; then
    echo "[OK] ${MOUNT_POINT} is already mounted"
else
    echo "     Attempting NFS mount..."
    if mount "${MOUNT_POINT}" 2>/dev/null; then
        echo "[OK] NFS mount successful"
    else
        echo "[WARN] NFS mount failed."
        echo "       Your server may not be whitelisted for Corral access."
        echo "       Contact TACC sysadmin to request access for this server to allocation BCS24011."
        echo "       Continuing with symlink setup so everything is ready when mount succeeds."
    fi
fi

# 5. Create /data/ckan symlink
if [[ -L "${DATA_SYMLINK}" ]]; then
    CURRENT_TARGET=$(readlink -f "${DATA_SYMLINK}")
    if [[ "${CURRENT_TARGET}" == "${MOUNT_POINT}" ]]; then
        echo "[OK] Symlink ${DATA_SYMLINK} -> ${MOUNT_POINT} already exists"
    else
        echo "[WARN] ${DATA_SYMLINK} is a symlink but points to ${CURRENT_TARGET}, not ${MOUNT_POINT}"
        echo "       Verify this is intentional or remove and re-run."
    fi
elif [[ -d "${DATA_SYMLINK}" ]]; then
    echo "[WARN] ${DATA_SYMLINK} exists as a directory (not a symlink)."
    echo "       If this is not the NFS mount, remove it and re-run to create a symlink."
elif [[ -e "${DATA_SYMLINK}" ]]; then
    echo "[WARN] ${DATA_SYMLINK} exists but is not a symlink or directory. Skipping."
else
    mkdir -p "$(dirname "${DATA_SYMLINK}")"
    ln -s "${MOUNT_POINT}" "${DATA_SYMLINK}"
    echo "[OK] Created symlink ${DATA_SYMLINK} -> ${MOUNT_POINT}"
fi

# 6. Set group ownership on the CKAN data directories
#
# Corral NFS squashes root, so root cannot chgrp here. The invoking user can:
# they own the data and are a member of the target group. Fall back to root
# only when the script is run from a root login with no SUDO_USER.
CHGRP_AS="${SUDO_USER:-root}"

run_as_chgrp_user() {
    if [[ "${CHGRP_AS}" == "root" ]]; then
        "$@"
    else
        sudo -u "${CHGRP_AS}" "$@"
    fi
}

if ! mount | grep -qF "${MOUNT_POINT}"; then
    echo "[WARN] ${MOUNT_POINT} is not mounted. Skipping group change."
    echo "       Re-run this script after the mount succeeds."
elif [[ "${CHGRP_AS}" != "root" ]] && ! id -G "${CHGRP_AS}" 2>/dev/null | tr ' ' '\n' | grep -qxF "${STORAGE_GID}"; then
    echo "[WARN] User ${CHGRP_AS} is not a member of group ${STORAGE_GID}."
    echo "       chgrp will fail. Ask the TACC sysadmin to add ${CHGRP_AS} to G-${STORAGE_GID}."
else
    echo "[OK] Changing group as user ${CHGRP_AS}"
    for DATA_DIR in "${MOUNT_POINT}/resources" "${MOUNT_POINT}/storage"; do
        if [[ ! -d "${DATA_DIR}" ]]; then
            echo "[WARN] ${DATA_DIR} does not exist. Skipping."
            continue
        fi

        # Entries owned by another user cannot be changed. Report them.
        FOREIGN=$(run_as_chgrp_user find "${DATA_DIR}" ! -user "${CHGRP_AS}" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${FOREIGN}" -gt 0 ]]; then
            echo "[WARN] ${FOREIGN} entries under ${DATA_DIR} are not owned by ${CHGRP_AS}."
            echo "       These need the TACC sysadmin or their owner."
        fi

        # Only touch entries with the wrong group, so re-runs stay cheap.
        WRONG=$(run_as_chgrp_user find "${DATA_DIR}" ! -group "${STORAGE_GID}" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${WRONG}" -eq 0 ]]; then
            echo "[OK] ${DATA_DIR} already has group ${STORAGE_GID}"
        elif run_as_chgrp_user find "${DATA_DIR}" ! -group "${STORAGE_GID}" -user "${CHGRP_AS}" \
                 -exec chgrp -h "${STORAGE_GID}" {} + 2>/dev/null; then
            echo "[OK] Set group ${STORAGE_GID} on ${WRONG} entries under ${DATA_DIR}"
        else
            echo "[WARN] chgrp did not fully succeed on ${DATA_DIR}."
            echo "       Ask the TACC sysadmin to set group ${STORAGE_GID} on this directory."
        fi

        # A non-root chgrp can clear setgid. The bit makes new files inherit
        # the group, so put it back.
        run_as_chgrp_user chmod g+s "${DATA_DIR}" 2>/dev/null \
            && echo "[OK] setgid bit set on ${DATA_DIR}" \
            || echo "[WARN] Could not set the setgid bit on ${DATA_DIR}"
    done
fi

# 7. Summary
echo ""
echo "=== Setup Summary ==="
echo "  fstab entry:  configured (includes _netdev)"
echo "  Mount point:  ${MOUNT_POINT}"
echo "  Data symlink: ${DATA_SYMLINK} -> ${MOUNT_POINT}"
echo "  Storage group: ${STORAGE_GID} (must match ckan/Dockerfile)"
echo ""
echo "Next steps:"
echo "  1. If mount failed, contact TACC sysadmin for allocation BCS24011 access"
echo "  2. Run: bash verify-nfs-storage.sh (no sudo needed)"
echo "  3. Start CKAN: docker compose up -d"
echo "  4. Run verify again to check container access"
