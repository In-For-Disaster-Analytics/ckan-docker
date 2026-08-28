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

   If the `chgrp` step fails, the invoking user does not own the files or is not in `G-826471`. Ask the TACC sysadmin for help.

   Run the script with `sudo`, not from a root login. Corral NFS squashes root, so root cannot change the group. The script tests one file first, then uses whichever identity works: root, or your own user. Your user must own the data and be a member of `G-826471`. Check with `id`.

   Files owned by uid 503 are a known case. That is the container uid from before the Dockerfile remap, and no host user owns it. Neither root nor your user can change those files. See "Files owned by uid 503" below.

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

## Storage Quota

Corral charges the disk quota to the group that owns the file. Moving the CKAN
data to group `826471` moves that usage to the new allocation and frees the old
one.

Confirm the quota is a group quota before you rely on this. A user quota does
not move with a `chgrp`:

```bash
quota -s                     # user quota
quota -g PT2050-DataX -s     # old group
quota -g G-826471 -s         # new group -- confirm it has free space
```

`setup-host.sh` changes the group in two passes:

1. `chgrp` on every directory in `DATA_DIRS`. This frees the old quota.
2. `setfacl` to grant group write. ACLs use extended attributes, which need
   space, so this runs only after pass 1.

Set `SET_ACL=0` to skip pass 2 if the ACL step fails while the quota is full:

```bash
sudo SET_ACL=0 bash setup-host.sh
```

`DATA_DIRS` at the top of the script lists the directories to move. It holds
`resources/` and `storage/` by default. Other directories under the mount, such
as the `.old` copies, keep the old group and its quota. Add them to `DATA_DIRS`
to move them too, or delete them if they are obsolete.

The setgid bit matters here. Without it, new uploads inherit the old group and
consume the old quota again.

### Files owned by uid 503

Some directories hold files owned by uid `503`. That is the stock `ckan` uid
from the base image, written by a container built from `Dockerfile.dev`, which
does not remap the uid. No host user owns uid 503, and Corral squashes root, so
neither identity can change or delete these files.

Run a container as uid 503 to work with them:

```bash
docker run --rm --user 503:826671 \
  -v /corral/utexas/BCS24011/ckan/resources.old:/target \
  alpine:3 sh -c 'ls /target | head; du -sh /target'
```

The NFS export uses AUTH_SYS, so the server accepts the uid the client sends.
This is confirmed to work on this deployment. Test write access first:

```bash
docker run --rm --user 503:826671 \
  -v /corral/utexas/BCS24011/ckan/resources.old:/target \
  alpine:3 sh -c 'touch /target/.wtest && rm /target/.wtest && echo WRITABLE'
```

Change the group of uid 503 files the same way. The container needs the target
group, so put it in the `--user` argument:

```bash
docker run --rm --user 503:826471 \
  -v /corral/utexas/BCS24011/ckan/resources.old:/target \
  alpine:3 sh -c 'chgrp -R 826471 /target'
```

This fails if the server uses `manage-gids`, because the server then looks up
the groups for uid 503 itself, and that uid does not exist there.

Use the production Dockerfile to prevent new files with uid 503.

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
- **Group ownership** on `resources/` and `storage/` is set to gid `826471` by `setup-host.sh`. The script runs this step as `$SUDO_USER`, because Corral NFS squashes root. It only changes entries with the wrong group, so re-runs are cheap. It also re-applies the setgid bit, so new files inherit the group
- **Group write access** comes from a POSIX ACL entry, `group:G-826471:rwx`. These directories have an extended ACL, so `chmod g+w` changes only the mask and leaves `group::` at `r-x`. `setfacl` is necessary. A matching `default:` entry makes new files inherit the access

Note that CKAN does not depend on the group to write. The container user has uid `863242`, the same uid as the data owner, so it matches the `user::rwx` ACL entry. The group grants access to other members of `G-826471`.

Check the result with:
```bash
getfacl /corral/utexas/BCS24011/ckan/storage
# Expected: group:G-826471:rwx and default:group:G-826471:rwx
```
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
