# NFS Corral Storage Setup for CKAN

Mount TACC Corral NFS storage on a new server so the CKAN Docker container can read and write uploaded dataset files. The NFS export backs only the CKAN `resources/` and `storage/` directories; generated runtime paths such as `webassets/` stay local to the container.

## Prerequisites

- Root access on the target server
- Docker and docker compose installed
- Production CKAN image built (uses `ckan/Dockerfile` which remaps the CKAN user to uid `863242`, gid `826471`)

## Quick Start

1. Copy the `scripts/nfs-storage/` directory to the server.

2. Run the setup script as root:

   ```bash
   sudo bash setup-host.sh
   ```

   The script mounts Corral, creates the `/data/ckan` symlink, and sets group `826471` on the `resources/` and `storage/` directories.

3. If the NFS mount fails, the server is not whitelisted for Corral access. Contact TACC sysadmin to request access for your server to allocation BCS24011.

   If the `chgrp` step fails, Corral squashes root or denies group changes. Ask the TACC sysadmin to set group `826471` on the data directories.

4. Run the verification script (no sudo needed):

   ```bash
   bash verify-nfs-storage.sh
   ```

5. Start CKAN:

   ```bash
   docker compose up -d
   ```

6. Run verification again to confirm container access:

   ```bash
   bash verify-nfs-storage.sh
   ```

   All checks should show `[OK]`. Review any `[FAIL]` or `[WARN]` items.

## How It Works

```
NFS Server (129.114.52.151)
  /corral/main/utexas/BCS24011/ckan
       |
       | NFS mount (fstab)
       v
Host: /corral/utexas/BCS24011/ckan
       |
       | symlink
       v
Host: /data/ckan
       |
       | Docker bind mounts (docker-compose.yml)
       v
Container: /var/lib/ckan/resources
Container: /var/lib/ckan/storage
       accessed by ckan user (uid=863242, gid=826471)
```

- **NFS mount** brings Corral storage to the host at `/corral/utexas/BCS24011/ckan`
- **Symlink** `/data/ckan` points to the mount (matches docker-compose.yml volume definition)
- **Docker bind mounts** map `/data/ckan/resources` and `/data/ckan/storage` to the matching container subdirectories
- **Container user** `ckan` (uid=863242, gid=826471) accesses files via ownership/group permissions
- **Group ownership** on `resources/` and `storage/` is set to gid `826471` by `setup-host.sh`. The script only changes entries with the wrong group, so re-runs are cheap
- **UID/GID remapping** is handled by the production Dockerfile: `usermod -u 863242 ckan` and `groupmod -g 826471 ckan-sys`

Generated CKAN webassets are intentionally not stored on Corral/NFS. They are rebuilt by CKAN as needed and should remain writable inside the container filesystem.

## Troubleshooting

### Mount fails: "Permission denied" or timeout

The server is not whitelisted for Corral NFS access. Contact TACC sysadmin to request access for your server's IP to allocation BCS24011.

### Permission denied inside container

The wrong Dockerfile was used. The dev Dockerfile (`ckan/Dockerfile.dev`) does NOT remap the production UID/GID. Use the production Dockerfile (`ckan/Dockerfile`) which includes `usermod -u 863242 ckan` and `groupmod -g 826471 ckan-sys`.

Verify with:
```bash
docker compose exec ckan id
# Expected: uid=863242(ckan) gid=826471(ckan-sys)
# Wrong:    uid=503(ckan) gid=502(ckan-sys)
```

### Empty /var/lib/ckan after reboot

NFS mounted after Docker started. The `_netdev` fstab option (included by setup-host.sh) prevents this by telling the system to wait for network before mounting. If it still happens:

```bash
sudo mount /corral/utexas/BCS24011/ckan
docker compose restart
```

### Stale file handle errors

The NFS server was remounted or the export was recreated. Fix:

```bash
sudo umount /corral/utexas/BCS24011/ckan
sudo mount /corral/utexas/BCS24011/ckan
docker compose restart
```

## Configuration Reference

### fstab entry

```
129.114.52.151:/corral/main/utexas/BCS24011/ckan /corral/utexas/BCS24011/ckan nfs rw,nosuid,_netdev,rsize=1048576,wsize=1048576,intr,nfsvers=3,tcp 0 0
```

### Mount options

| Option | Purpose |
|--------|---------|
| `rw` | Read-write access |
| `nosuid` | Security: no setuid binaries from NFS |
| `_netdev` | Wait for network before mounting (prevents boot issues) |
| `rsize=1048576` | 1MB read buffer for performance |
| `wsize=1048576` | 1MB write buffer for performance |
| `intr` | Allow interrupted NFS operations (prevents hanging) |
| `nfsvers=3` | NFSv3 -- UIDs pass through directly (no idmapping) |
| `tcp` | TCP transport (more reliable than UDP) |

### Key paths

| Path | Description |
|------|-------------|
| `/corral/utexas/BCS24011/ckan` | NFS mount point on host |
| `/data/ckan` | Symlink to mount point (used by docker-compose.yml) |
| `/var/lib/ckan` | CKAN runtime path inside the container |
| `/var/lib/ckan/resources` | CKAN resource files |
| `/var/lib/ckan/storage` | CKAN file storage |
| `/var/lib/ckan/webassets` | CKAN compiled web assets, local to the container |
