# Deployment

## Architecture

```
User -> ckan (129.114.97.106) -> ckan-tmp (129.114.97.55) -> Docker containers
         nginx reverse proxy       nginx reverse proxy        CKAN on port 5000
```

### ckan - 129.114.97.106 (old server)

Reverse proxy that forwards all traffic to the new server. Handles SSL termination and the public-facing `ckan.tacc.utexas.edu` domain.

- Nginx config: `/etc/nginx/conf.d/ckan-tacc-utexas.conf`
- Reference copy: [docs/nginx/ckan-tacc-utexas.conf](nginx/ckan-tacc-utexas.conf)
- SSL: Let's Encrypt (Certbot managed)
- Proxies to: `https://129.114.97.55`
- Upload limit: `client_max_body_size 10G`

### ckan-tmp - 129.114.97.55 (new server)

Hosts the Docker Compose deployment. Nginx runs on the host and proxies to the CKAN container on `localhost:5000`.

- Nginx config: `/etc/nginx/conf.d/ckan-tacc-utexas.conf`
- Reference copy: [docs/nginx/ckan-tmp-tacc-utexas.conf](nginx/ckan-tmp-tacc-utexas.conf)
- SSL: Let's Encrypt (Certbot managed)
- Upload limit: `client_max_body_size 10G`
- Serves LiDAR files directly from `/corral/utexas/BCS24011/ckan/lidar_files`
- Handles CORS headers and media file range requests (video/audio seeking)

## Docker Compose

Deployed at `/srv/ckan-tacc-images` on ckan-tmp (129.114.97.55).

### Services

| Service     | Image / Build              | Port | Network          |
|-------------|----------------------------|------|------------------|
| ckan        | `ckan/Dockerfile`          | 5000 | ckannet, dbnet, solrnet, redisnet |
| datapusher  | `ckan/ckan-base-datapusher:0.0.20` | 8800 | ckannet, dbnet |
| db          | `postgresql/`              | -    | dbnet (internal) |
| solr        | `ckan/ckan-solr:2.11-solr9-spatial` | 8983 | solrnet (internal) |
| redis       | `redis:6`                  | -    | redisnet (internal) |

### Data Volumes

- CKAN storage: `/data/ckan` (bind mount)
- PostgreSQL: `pg_data` (Docker volume)
- Solr: `solr_data` (Docker volume)

### Configuration

- Production config: `.env.prod.config` + `.env.prod.secrets`
- Development config: `.env.dev.config` + `.env.dev.secrets`
- Secrets template: `.env.secrets.example`

### Common Commands

```bash
# SSH into the new server
ssh root@129.114.97.55

# Navigate to the deployment directory
cd /srv/ckan-tacc-images

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
