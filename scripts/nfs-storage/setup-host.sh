#!/bin/bash
# setup-host.sh - Set up NFS Corral mount for CKAN data storage on a new server
#
# Run once with root access. Safe to re-run (idempotent).
# Does NOT create host-level users or groups -- container-side permissions
# are handled by the production Dockerfile.

set -euo pipefail

NFS_SOURCE="129.114.52.151:/corral/main/utexas/BCS24011/ckan"
MOUNT_POINT="/corral/utexas/BCS24011/ckan"
FSTAB_ENTRY="${NFS_SOURCE} ${MOUNT_POINT} nfs rw,nosuid,_netdev,rsize=1048576,wsize=1048576,intr,nfsvers=3,tcp 0 0"
DATA_SYMLINK="/data/ckan"

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

# 6. Summary
echo ""
echo "=== Setup Summary ==="
echo "  fstab entry:  configured (includes _netdev)"
echo "  Mount point:  ${MOUNT_POINT}"
echo "  Data symlink: ${DATA_SYMLINK} -> ${MOUNT_POINT}"
echo ""
echo "Next steps:"
echo "  1. If mount failed, contact TACC sysadmin for allocation BCS24011 access"
echo "  2. Run: bash verify-nfs-storage.sh (no sudo needed)"
echo "  3. Start CKAN: docker compose up -d"
echo "  4. Run verify again to check container access"
