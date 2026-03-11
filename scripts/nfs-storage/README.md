# NFS Corral Storage Setup for CKAN

Mount TACC Corral NFS storage on a new server so the CKAN Docker container can read and write dataset files. The NFS export provides persistent storage at `/var/lib/ckan` inside the container, backed by TACC's Corral filesystem (allocation BCS24011).

## Prerequisites

- Root access on the target server
- Docker and docker compose installed
- Production CKAN image built (uses `ckan/Dockerfile` which remaps GID to 826671)

## Quick Start

1. Copy the `scripts/nfs-storage/` directory to the server.

2. Run the setup script as root:

   ```bash
   sudo bash setup-host.sh
   ```

3. If the NFS mount fails, the server is not whitelisted for Corral access. Contact TACC sysadmin to request access for your server to allocation BCS24011.

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
       | Docker bind mount (docker-compose.yml)
       v
Container: /var/lib/ckan
       accessed by ckan user (uid=503, gid=826671)
```

- **NFS mount** brings Corral storage to the host at `/corral/utexas/BCS24011/ckan`
- **Symlink** `/data/ckan` points to the mount (matches docker-compose.yml volume definition)
- **Docker bind mount** maps `/data/ckan` on the host to `/var/lib/ckan` in the container
- **Container user** `ckan` (uid=503, gid=826671) accesses files via group permissions
- **GID remapping** is handled by the production Dockerfile: `groupmod -g 826671 ckan-sys` changes the base image's default GID (502) to match TACC's Corral group

Files on Corral are owned by various TACC user UIDs but share the `ckan-sys` group (826671). The container accesses everything through group permissions.

## Troubleshooting

### Mount fails: "Permission denied" or timeout

The server is not whitelisted for Corral NFS access. Contact TACC sysadmin to request access for your server's IP to allocation BCS24011.

### Permission denied inside container

The wrong Dockerfile was used. The dev Dockerfile (`ckan/Dockerfile.dev`) does NOT remap the GID. Use the production Dockerfile (`ckan/Dockerfile`) which includes `groupmod -g 826671 ckan-sys`.

Verify with:
```bash
docker compose exec ckan id
# Expected: uid=503(ckan) gid=826671(ckan-sys)
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
| `/var/lib/ckan` | Storage path inside CKAN container |
| `/var/lib/ckan/resources` | CKAN resource files |
| `/var/lib/ckan/storage` | CKAN file storage |
| `/var/lib/ckan/webassets` | CKAN compiled web assets |
