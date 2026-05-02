# Debug: Corral EDQUOT on CKAN Resource Upload

## Symptom

Production CKAN raised `OSError: [Errno 122] Disk quota exceeded` when
creating resources, blocking uploads.

```
File "/srv/app/src/ckan/ckan/lib/uploader.py", line 379, in upload
    os.makedirs(directory)
...
mkdir(name, mode)
[Errno 122] Disk quota exceeded: '/var/lib/ckan/resources/1d9'
```

The same error reappeared later under a different path:

```
PermissionError: [Errno 13] Permission denied: '/var/lib/ckan/webassets/.webassets-cache/14026a1632531c2b1445ac9963f41c0b'
OSError: [Errno 122] Disk quota exceeded: '/var/lib/ckan/webassets/.webassets-cache'
```

`/var/lib/ckan` inside the CKAN container is bind-mounted from
`/data/ckan` on the host, which is itself an NFSv3 mount of the TACC
Corral allocation `BCS24011`:

```
129.114.52.151:/corral/main/utexas/BCS24011/ckan on /corral/utexas/BCS24011/ckan
type nfs (rw,nosuid,rsize=1048576,wsize=1048576,intr,nfsvers=3,tcp)
```

## Investigation

Phase 1 evidence (run on docker host):

| Check | Result | Conclusion |
|-------|--------|------------|
| `df -h /corral/utexas/BCS24011/ckan` | 70% used (12P free) | Corral filesystem not full |
| `df -i` | 81% inode used | Filesystem inode pool not exhausted |
| `du -sh resources` | 29G | Tree itself tiny |
| `stat resources` | owner `503:G-826671`, mode `0755` | Owned by container's default uid |
| `docker compose exec ckan id` | `uid=503(ckan) gid=826671(ckan-sys)` | Container writes as uid 503 |
| `sudo -u #863242 dd ... .qtest` at root | OK | uid 863242 has quota |
| `sudo -u #863242 mkdir resources/qt_863242` | EACCES | Group r-x only on resources |
| `docker compose exec ckan mkdir resources/qtestN` | EDQUOT | uid 503 has zero quota on Corral |
| `sudo chown ...` from host | EACCES (root_squash) | NFS export squashes root |

## Root Cause

NFSv3 transmits the raw numeric uid from the client. The CKAN container
shipped with default uid `503`, which is **not registered** in TACC's
user database for project `BCS24011`. Corral therefore treats writes
from uid 503 as quota-zero and returns `EDQUOT` for every write
beneath the project tree.

A secondary issue: directories newly created on the host inherited the
shell user's primary group (`PT2050-DataX`) instead of the BCS24011
group `826671`, because the parent directory had no setgid bit. Files
written into those subdirs were billed against the wrong project's
quota and again rejected with `EDQUOT`.

## Fix

### 1. Container uid mapped to a real TACC uid

Patched `ckan/Dockerfile`:

```dockerfile
RUN groupmod -g 826671 ckan-sys && echo "Modified group ID for ckan-sys to 826671"
RUN usermod  -u 863242 ckan    && echo "Modified user  ID for ckan to 863242"

RUN find /var/lib/ckan        -uid 503 ! -type l -exec chown 863242 {} \;
RUN find ${APP_DIR}           -uid 503 ! -type l -exec chown 863242 {} \;
RUN find /docker-entrypoint.d -uid 503 ! -type l -exec chown 863242 {} \;
RUN find /usr/local           -uid 503 ! -type l -exec chown 863242 {} \;
RUN find ${CKAN_STORAGE_PATH} -uid 503 ! -type l -exec chown 863242 {} \;
RUN find /srv/app             -uid 503 ! -type l -exec chown 863242 {} \;
```

Commit: `fe8db64 fix(docker): set ckan container uid to 863242 for Corral NFS writes`

### 2. Existing data tree rechowned via copy+swap

Root-squash on the NFS export prevents `chown` from the host even as
root. Plain user `chown` from the container is also blocked by POSIX
(non-root cannot transfer ownership). Workaround: copy the tree as
mosorio (uid 863242), so the new copy is born with the correct owner,
then atomically swap names.

```bash
docker compose stop ckan

cd /corral/utexas/BCS24011/ckan
cp -a resources resources.new        # owner 863242, gid 826671 (cp -a preserves gid for group members)
mv resources resources.old
mv resources.new resources

setfacl -R    -m g:826671:rwx resources
setfacl -R -d -m g:826671:rwx resources
find resources -type d -exec chmod g+s {} \;

docker compose up -d ckan
```

Keep `resources.old` until the next backup window confirms reads work.

### 3. NFS bind narrowed to data subdirectories

The original mount `/data/ckan:/var/lib/ckan` forced every subdirectory
of `/var/lib/ckan` (webassets, runtime caches, etc.) through NFS. Only
`resources/` and `storage/` actually need to persist on Corral; the
rest can live in the container's image layer where uid 863242 already
owns the paths.

`docker-compose.yml`:

```yaml
services:
  ckan:
    volumes:
      - /data/ckan/resources:/var/lib/ckan/resources
      - /data/ckan/storage:/var/lib/ckan/storage
      - pip_cache_py310:/root/.cache/pip
      - site_packages_py310:/usr/lib/python3.10/site-packages
```

An earlier attempt to overlay a named volume at `/var/lib/ckan/webassets`
on top of the wide bind mount was abandoned because runc could not
traverse the NFS-bound parent during container init (root-squash denied
the directory lookup).

## Why The Bug Surfaced Now

Earlier uwsgi/nginx fixes (`794f800`, `5f84c90`, `5e95674`) let large
uploads complete the request body phase instead of being killed by
harakiri. The uploader code path that calls `os.makedirs` is only
reached after the body finishes streaming, so the underlying NFS uid
mismatch had been masked by an earlier failure.

## Verification

```bash
docker compose exec ckan id                                 # uid=863242(ckan)
docker compose exec ckan touch /var/lib/ckan/resources/.qok && echo OK
docker compose exec ckan touch /var/lib/ckan/webassets/.qok  && echo OK
docker compose logs --tail=200 ckan | grep -iE 'quota|errno' || echo CLEAN
```

Then upload a real resource through the UI to confirm the end-to-end
flow.

## Follow-Up / Tech Debt

- Hardcoding mosorio's personal TACC uid into the production image
  ties CKAN's ability to write to one human's account. Open a TACC
  ticket to provision a dedicated service account in BCS24011 and
  switch the Dockerfile to that uid.
- Add a default ACL `g:826671:rwx` and the setgid bit on
  `/corral/utexas/BCS24011/ckan` so future top-level directories
  inherit the correct group automatically.
- Audit any remaining 503-owned directories under the Corral tree:
  `find /corral/utexas/BCS24011/ckan -maxdepth 2 -uid 503`.
