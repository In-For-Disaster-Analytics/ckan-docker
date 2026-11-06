# Deployment

## Architecture

```
User -> ckan.tacc.utexas.edu -> host nginx -> CKAN container
                                TLS/CORS      localhost:5000
```

### CKAN host

Hosts the Docker Compose deployment. Nginx runs on the host, terminates TLS for `ckan.tacc.utexas.edu`, and proxies directly to the CKAN container on `127.0.0.1:5000`.

- Nginx config: `/etc/nginx/conf.d/ckan-tacc-utexas.conf` and `/etc/nginx/conf.d/00-ckan-rate-limits.conf`
- Source of truth: [docs/nginx/ckan-tacc-utexas.conf](nginx/ckan-tacc-utexas.conf) and [docs/nginx/00-ckan-rate-limits.conf](nginx/00-ckan-rate-limits.conf). Change nginx through a PR to these files, then deploy with `scripts/nginx/deploy.sh` (see [Nginx](#nginx)); do not hand-edit the files on the host.
- SSL: Let's Encrypt (Certbot managed)
- Proxies to: `http://127.0.0.1:5000`
- Upload limit: `client_max_body_size 10G`
- Serves LiDAR files directly from `/corral/utexas/BCS24011/ckan/lidar_files`
- Handles CORS headers and media file range requests (video/audio seeking)

## Docker Compose

Deployed at `/srv/ckan-tacc-images` on the CKAN host (currently 129.114.97.55).

### Services

| Service     | Image / Build              | Port | Network          |
|-------------|----------------------------|------|------------------|
| ckan        | `ckan/Dockerfile`          | 5000 | ckannet, dbnet, solrnet, redisnet |
| datapusher  | `ckan/ckan-base-datapusher:0.0.20` | 8800 | ckannet, dbnet |
| db          | `postgresql/`              | -    | dbnet (internal) |
| solr        | `ckan/ckan-solr:2.11-solr9-spatial` | 8983 | solrnet (internal) |
| redis       | `redis:6`                  | -    | redisnet (internal) |

### Data Volumes

- CKAN resources: `/data/ckan/resources` -> `/var/lib/ckan/resources`
- CKAN storage: `/data/ckan/storage` -> `/var/lib/ckan/storage`
- CKAN webassets: local container filesystem, intentionally not on Corral/NFS
- PostgreSQL: `pg_data` (Docker volume)
- Solr: `solr_data` (Docker volume)

### Configuration

- Production config: `.env.prod.config` + `.env.prod.secrets`
- Development config: `.env.dev.config` + `.env.dev.secrets`
- Secrets template: `.env.secrets.example`

### Common Commands

```bash
# SSH into the CKAN host
ssh root@129.114.97.55

# Navigate to the deployment directory
cd /srv/ckan-tacc-images

# Use the webassets/nginx fix branch, not main
BRANCH=117-ckan-html-pages-fail-when-webassets-cache-is-mounted-on-corralnfs-without-ckan-write-permissions
git fetch origin
git switch "$BRANCH" || git switch --track "origin/$BRANCH"
git pull --ff-only

# Rebuild and restart
docker compose build
docker compose up -d

# View logs
docker compose logs -f ckan

# Access CKAN container
docker compose exec ckan bash

# Add sysadmin user
docker compose exec ckan ckan sysadmin add <username>

# Restart nginx (on host, not in Docker)
systemctl reload nginx
```

### Nginx

The host nginx config lives in this repo and is installed with a script, so edits are reviewed and the host does not drift.

```bash
cd /srv/ckan-tacc-images
git pull --ff-only
sudo scripts/nginx/deploy.sh --check   # show the diff, change nothing
sudo scripts/nginx/deploy.sh           # back up, install, nginx -t, reload
```

The script backs up the current files to `/root/nginx-backup-<timestamp>-<id>/`, installs both files, validates with `nginx -t`, and reloads (existing connections stay open). If any step fails it restores the backup and does not reload. It also comments out any `ckan_*` rate-limit zone lines still in `/etc/nginx/nginx.conf`, since those zones now live in `00-ckan-rate-limits.conf` (a zone defined twice is a config error). To undo a deploy, copy the files from the backup folder back and run `nginx -t && systemctl reload nginx`.

`$blocked_bot` (used by the site file) is defined in the host's `/etc/nginx/nginx.conf`, which is not managed here.

#### Rate limiting

Requests rejected by a limit get `429 Too Many Requests` from nginx itself (its plain error page). The design:

- Requests **with a query string** (facets, search, pagination) are the expensive, crawlable ones. Only they count against the strict `ckan_search` (per client) and `ckan_search_global` (all clients) zones. Plain page views, such as an organization page and its tabs, skip those zones because the zone key is empty for them, and are limited only by the generous `ckan_general` zones.
- The `*_global` zones are shared by every visitor. Keep them well above what a few people browsing at once can produce, or one crawler burst will 429 everyone.
- Query strings over 500 characters are rejected outright (crawler-generated facet combinations), and the denied ranges and `$blocked_bot` return 403.

To see which zone is rejecting requests and from where:

```bash
sudo grep -h 'limiting' /var/log/nginx/ckan.error.log | tail -500 | grep -oE 'by zone "[a-z_]+"' | sort | uniq -c | sort -rn
sudo awk '$9==429 {print $1}' /var/log/nginx/ckan.access.log | sort | uniq -c | sort -rn | head -8
```

### Validation

```bash
# Local container/API paths
curl -o /dev/null -s -w "local_api:%{time_total} code:%{http_code}\n" \
  http://127.0.0.1:5000/api/3/action/status_show
curl -o /dev/null -s -w "local_home:%{time_total} code:%{http_code}\n" \
  http://127.0.0.1:5000/

# Public paths through host nginx
curl -k -o /dev/null -s -w "public_api:%{time_total} code:%{http_code}\n" \
  https://ckan.tacc.utexas.edu/api/3/action/status_show
curl -k -o /dev/null -s -w "public_home:%{time_total} code:%{http_code}\n" \
  https://ckan.tacc.utexas.edu/
```

Both `local_home` and `public_home` must return `code:200`; those rendered-page checks catch webassets permission failures that API-only checks miss.
