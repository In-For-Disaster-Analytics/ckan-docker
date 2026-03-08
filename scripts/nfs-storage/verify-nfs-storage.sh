#!/bin/bash
# verify-nfs-storage.sh - Verify NFS mount and CKAN container permissions
#
# Run after setup-host.sh to verify everything works. Does NOT require root.
# Designed as a one-time setup check, not a health monitor.

set -euo pipefail

MOUNT_POINT="/corral/utexas/BCS24011/ckan"
DATA_SYMLINK="/data/ckan"
EXPECTED_GID=826671
FAILURES=0

echo "=== NFS Mount Verification ==="
echo ""

# 1. NFS mount check
MOUNT_INFO=$(mount | grep "corral" || true)
if [[ -n "${MOUNT_INFO}" ]]; then
    echo "[OK] NFS mount is active:"
    echo "     ${MOUNT_INFO}"
    if echo "${MOUNT_INFO}" | grep -q "nfsvers=3"; then
        echo "[OK] Using NFSv3"
    else
        echo "[WARN] NFSv3 not detected in mount options -- expected nfsvers=3"
    fi
    if grep -qF "_netdev" /etc/fstab 2>/dev/null; then
        echo "[OK] fstab includes _netdev (boot-ordering protection)"
    else
        echo "[WARN] fstab missing _netdev -- server may hang on reboot if NFS is unavailable"
    fi
else
    echo "[FAIL] NFS mount not active at ${MOUNT_POINT}"
    echo "       Fix: sudo mount ${MOUNT_POINT}"
    echo "       If that fails, contact TACC sysadmin for allocation BCS24011 access."
    FAILURES=$((FAILURES + 1))
fi

echo ""

# 2. Symlink check
if [[ -e "${DATA_SYMLINK}" ]]; then
    REAL_PATH=$(readlink -f "${DATA_SYMLINK}")
    if [[ "${REAL_PATH}" == "${MOUNT_POINT}" ]]; then
        echo "[OK] ${DATA_SYMLINK} resolves to ${MOUNT_POINT}"
    else
        echo "[WARN] ${DATA_SYMLINK} resolves to ${REAL_PATH} (expected ${MOUNT_POINT})"
    fi
else
    echo "[FAIL] ${DATA_SYMLINK} does not exist"
    echo "       Fix: sudo ln -s ${MOUNT_POINT} ${DATA_SYMLINK}"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# 3. Host write check
echo "--- Host Write Access ---"
if touch "${DATA_SYMLINK}/.nfs-write-test" 2>/dev/null; then
    rm -f "${DATA_SYMLINK}/.nfs-write-test"
    echo "[OK] Host can write to ${DATA_SYMLINK}"
else
    echo "[FAIL] Host cannot write to ${DATA_SYMLINK}"
    echo "       Fix: Check group permissions on the NFS mount"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# 4. Directory check
echo "--- Expected Directories ---"
for dir in resources storage webassets; do
    if [[ -d "${DATA_SYMLINK}/${dir}" ]]; then
        echo "[OK] ${DATA_SYMLINK}/${dir}/ exists"
    else
        echo "[WARN] ${DATA_SYMLINK}/${dir}/ missing (CKAN creates it on first run)"
    fi
done

echo ""

# 5. Container checks
echo "=== Container Permission Verification ==="
echo ""

if docker compose ps --status running 2>/dev/null | grep -q "ckan"; then
    # 5a. Container user identity
    CONTAINER_ID_OUTPUT=$(docker compose exec -T ckan id 2>/dev/null || true)
    if [[ -n "${CONTAINER_ID_OUTPUT}" ]]; then
        echo "[INFO] Container user: ${CONTAINER_ID_OUTPUT}"
        if echo "${CONTAINER_ID_OUTPUT}" | grep -q "gid=${EXPECTED_GID}"; then
            echo "[OK] Container GID matches expected (${EXPECTED_GID})"
        else
            echo "[FAIL] Container GID does not match expected (${EXPECTED_GID})"
            echo "       Fix: Use production Dockerfile (not dev) which runs groupmod -g ${EXPECTED_GID} ckan-sys"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo "[WARN] Could not read container user identity"
    fi

    echo ""

    # 5b. Container write access
    if docker compose exec -T ckan touch /var/lib/ckan/.container-write-test 2>/dev/null; then
        docker compose exec -T ckan rm -f /var/lib/ckan/.container-write-test 2>/dev/null
        echo "[OK] Container can write to /var/lib/ckan"
    else
        echo "[FAIL] Container cannot write to /var/lib/ckan"
        echo "       Fix: Check that container GID (${EXPECTED_GID}) has write access to NFS mount"
        FAILURES=$((FAILURES + 1))
    fi

    echo ""

    # 5c. Container directory listing
    echo "--- Container /var/lib/ckan contents ---"
    docker compose exec -T ckan ls /var/lib/ckan/ 2>/dev/null || echo "[WARN] Could not list container /var/lib/ckan"
else
    echo "[SKIP] CKAN container not running -- start with 'docker compose up -d' and re-run"
fi

echo ""

# Summary
echo "=== Verification Summary ==="
if [[ ${FAILURES} -eq 0 ]]; then
    echo "All critical checks passed."
    exit 0
else
    echo "${FAILURES} critical check(s) failed. Review [FAIL] items above."
    exit 1
fi
