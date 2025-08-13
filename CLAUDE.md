# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Docker Environment Setup

**Development Mode:**
```bash
# Build and start development environment
docker compose -f docker-compose.dev.yml build
docker compose -f docker-compose.dev.yml up -d

# Access development CKAN container
docker compose -f docker-compose.dev.yml exec ckan-dev bash

# Add sysadmin user in development
docker compose -f docker-compose.dev.yml exec ckan-dev ckan sysadmin add <username>
```

**Production Mode:**
```bash
# Build and start production environment
docker compose build
docker compose up -d

# Access production CKAN container
docker compose exec ckan bash

# Add sysadmin user in production
docker compose exec ckan ckan sysadmin add <username>
```

### Database Management

**Backup Database:**
```bash
# Run backup script (creates timestamped dumps)
./scripts/database/backup-db.sh [output_directory]
```

**Restore Database:**
```bash
docker compose exec db pg_restore -U ckan -d ckan -c -v /path/to/backup.dump
```

### Authentication and API

**Get JWT Token:**
```bash
# Get Tapis OAuth2 JWT token for API access
JWT=$(./scripts/tapis-oauth/get-jwt.sh username password)
```

**Create OAuth2 Client:**
```bash
# Create OAuth2 client for CKAN instance
bash -x scripts/tapis-oauth/create-client.sh tacc_username tacc_password client-name http://hostname:5000/oauth2/callback
```

### Extension Development

**Test CKAN Extensions:**
```bash
# Navigate to extension directory and run tests
cd src/ckanext-<extension-name>
pytest --ckan-ini=test.ini
```

## Architecture Overview

This is a Docker-based CKAN deployment with the following architecture:

### Core Services
- **CKAN**: Main application server (port 5000)
- **DataPusher**: Data processing service (port 8800) 
- **PostgreSQL**: Primary database with CKAN and datastore databases
- **Solr**: Search and indexing engine (port 8983)
- **Redis**: Caching and session storage
- **Nginx**: Reverse proxy with SSL (port 8443)

### Custom CKAN Extensions
- **ckanext-tacc_theme**: TACC-specific theming and UI customizations
- **ckanext-dso_scheming**: Dataset schema definitions for DSO and MINT projects
- **ckanext-tapisfilestore**: Integration with Tapis file system for serving files via `tapis://` URLs

### External Integrations
- **TACC OAuth2**: Authentication via Tapis OAuth2 service
- **TACC Corral**: High-performance file system for dataset storage
- **MINT/DYNAMO Dashboard**: Integration with modeling and analysis platforms

## Configuration Management

The project uses environment-based configuration:

### Environment Files
- `.env.dev.config` + `.env.dev.secrets`: Development configuration
- `.env.prod.config` + `.env.prod.secrets`: Production configuration
- `.env.secrets.example`: Template for secrets files

### Key Configuration Variables
- `CKAN_SITE_URL`: Base URL for CKAN instance (default: http://localhost:5000)
- `CKAN_OAUTH2_CLIENT_ID` + `CKAN_OAUTH2_CLIENT_SECRET`: OAuth2 credentials
- Database credentials: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `CKAN_DB`, `DATASTORE_DB`

## File Structure

### Docker Configuration
- `docker-compose.yml`: Production deployment
- `docker-compose.dev.yml`: Development deployment with volume mounts
- `ckan/Dockerfile`: Production CKAN image
- `ckan/Dockerfile.dev`: Development CKAN image with live code reloading

### Custom Extensions
All custom extensions are located in `src/` directory:
- Each extension follows standard CKAN extension structure
- Extensions are mounted as volumes in development mode
- Extensions are copied into the image in production mode

### Database Scripts
- `scripts/database/backup-db.sh`: Database backup utility
- `scripts/database/restore-db.sh`: Database restore utility

### OAuth2 Scripts
- `scripts/tapis-oauth/`: Scripts for managing Tapis OAuth2 clients and tokens

## Development Workflow

1. **Local Development**: Use `docker-compose.dev.yml` for development with live code reloading
2. **Extension Development**: Edit files in `src/ckanext-*` directories, changes reflect immediately
3. **Theme Development**: Edit `src/ckanext-tacc_theme` for UI customizations
4. **Schema Changes**: Modify `src/ckanext-dso_scheming` for dataset schema definitions
5. **File Integration**: Use `src/ckanext-tapisfilestore` for Tapis file system integration

## Important Notes

- Default sysadmin credentials are defined in `.env.secrets` files and must be changed for production use
- CKAN URL configuration must be consistent across `CKAN_SITE_URL` and OAuth2 client settings
- All services are containerized and communicate via internal Docker networks
- File storage uses TACC Corral external file system rather than local storage
- Authentication is handled via TACC's centralized OAuth2 system

## URL and Hostname Configuration

If using custom hostnames (e.g., `ckan.tacc.cloud` instead of `localhost`):
1. Add hostname to `/etc/hosts`: `127.0.0.1 ckan.tacc.cloud`
2. Update `CKAN_SITE_URL` environment variable
3. Update OAuth2 client configuration to match new hostname