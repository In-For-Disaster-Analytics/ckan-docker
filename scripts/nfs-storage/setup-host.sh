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

# Directories whose group accounting moves to STORAGE_GID. Corral charges the
# quota to the group that owns the file, so every directory listed here moves
# its usage off the old group. Add directories to move more.
DATA_DIRS=(
    "${MOUNT_POINT}/resources"
    "${MOUNT_POINT}/storage"
)

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
# Two identities can change the group, and which one works depends on the NFS
# export. Root can change any file, but Corral may squash root. The invoking
# user can change only the files they own, but is never squashed. Some files
# belong to uid 503, the container uid from before the Dockerfile remap, so
# the invoking user cannot touch those. Try root first, then the user.
CHGRP_USER="${SUDO_USER:-root}"

# chgrp_probe <dir> -- pick the identity that can change the group here.
# Tries root on a single entry, because a squashed root fails on every file
# and a full failing pass over a large tree is slow. Falls back to the user.
chgrp_probe() {
    local dir="$1" sample
    sample=$(find "${dir}" ! -group "${STORAGE_GID}" -print -quit 2>/dev/null || true)
    if [[ -z "${sample}" ]]; then
        echo "none"
    elif chgrp -h "${STORAGE_GID}" "${sample}" 2>/dev/null; then
        echo "root"
    else
        echo "${CHGRP_USER}"
    fi
}

# chgrp_pass <dir> <as-user> -- change the group on entries that need it.
# Prints the number of entries that still have the wrong group.
chgrp_pass() {
    local dir="$1" as_user="$2"
    if [[ "${as_user}" == "root" ]]; then
        find "${dir}" ! -group "${STORAGE_GID}" -exec chgrp -h "${STORAGE_GID}" {} + 2>/dev/null || true
    else
        sudo -u "${as_user}" find "${dir}" ! -group "${STORAGE_GID}" -user "${as_user}" \
            -exec chgrp -h "${STORAGE_GID}" {} + 2>/dev/null || true
    fi
    find "${dir}" ! -group "${STORAGE_GID}" 2>/dev/null | wc -l | tr -d ' '
}

if ! mount | grep -qF "${MOUNT_POINT}"; then
    echo "[WARN] ${MOUNT_POINT} is not mounted. Skipping group change."
    echo "       Re-run this script after the mount succeeds."
elif [[ "${CHGRP_USER}" != "root" ]] && ! id -G "${CHGRP_USER}" 2>/dev/null | tr ' ' '\n' | grep -qxF "${STORAGE_GID}"; then
    echo "[WARN] User ${CHGRP_USER} is not a member of group ${STORAGE_GID}."
    echo "       chgrp will fail. Ask the TACC sysadmin to add ${CHGRP_USER} to G-${STORAGE_GID}."
else
    # Pass 1: move the group. This frees the old group quota, so it runs to
    # completion on every directory before anything else is tried.
    for DATA_DIR in "${DATA_DIRS[@]}"; do
        if [[ ! -d "${DATA_DIR}" ]]; then
            echo "[WARN] ${DATA_DIR} does not exist. Skipping."
            continue
        fi

        BEFORE=$(find "${DATA_DIR}" ! -group "${STORAGE_GID}" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${BEFORE}" -eq 0 ]]; then
            echo "[OK] ${DATA_DIR} already has group ${STORAGE_GID}"
        else
            USED=$(chgrp_probe "${DATA_DIR}")
            LEFT=$(chgrp_pass "${DATA_DIR}" "${USED}")

            CHANGED=$((BEFORE - LEFT))
            echo "[OK] Set group ${STORAGE_GID} on ${CHANGED} of ${BEFORE} entries under ${DATA_DIR} (as ${USED})"
            if [[ "${LEFT}" -gt 0 ]]; then
                echo "[WARN] ${LEFT} entries still have the wrong group."
                echo "       They belong to another user, often uid 503 from a dev-image"
                echo "       container. Their quota stays with the old group."
                echo "       List them with:"
                echo "         find ${DATA_DIR} ! -group ${STORAGE_GID} -printf '%u %p\\n' | sort | uniq -c"
            fi
        fi

        # A non-root chgrp can clear setgid. The bit makes new files inherit
        # the group, so put it back. Without it new uploads land in the old
        # group and consume the old quota again.
        { chmod g+s "${DATA_DIR}" 2>/dev/null \
          || sudo -u "${CHGRP_USER}" chmod g+s "${DATA_DIR}" 2>/dev/null; } \
            && echo "[OK] setgid bit set on ${DATA_DIR}" \
            || echo "[WARN] Could not set the setgid bit on ${DATA_DIR}"
    done

    # Pass 2: grant the group write access. ACLs live in extended attributes,
    # which need space, so this runs only after pass 1 has freed the quota.
    # Set SET_ACL=0 to skip it.
    if [[ "${SET_ACL:-1}" != "1" ]]; then
        echo "[OK] SET_ACL=0. Skipping the ACL step."
    elif ! command -v setfacl >/dev/null 2>&1; then
        echo "[WARN] setfacl not found. Install acl to grant group write."
    else
        for DATA_DIR in "${DATA_DIRS[@]}"; do
            [[ -d "${DATA_DIR}" ]] || continue
            # These directories carry an extended ACL, so chmod g+w moves only
            # the mask and leaves group:: at r-x. setfacl is necessary. The
            # default entry makes new files inherit the access.
            if sudo -u "${CHGRP_USER}" setfacl -R -m "g:${STORAGE_GID}:rwx" "${DATA_DIR}" 2>/dev/null \
               && sudo -u "${CHGRP_USER}" find "${DATA_DIR}" -type d \
                      -exec setfacl -m "d:g:${STORAGE_GID}:rwx" {} + 2>/dev/null; then
                echo "[OK] Group ${STORAGE_GID} has rwx on ${DATA_DIR}"
            else
                echo "[WARN] Could not set the ACL on ${DATA_DIR}."
                echo "       Check the quota, then: getfacl ${DATA_DIR}"
            fi
        done
    fi
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
