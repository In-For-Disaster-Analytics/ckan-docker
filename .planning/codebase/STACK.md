# Technology Stack

**Analysis Date:** 2026-02-14

## Languages

**Primary:**
- Python 3.10 - Core CKAN application and all extensions
- Python 3.9 - Development compatibility (supported by ckanext-oauth2)

**Secondary:**
- HTML/Jinja2 - Template rendering for web UI
- JavaScript - Client-side functionality (minimal frontend framework deps)
- SQL - PostgreSQL database schema and migrations

## Runtime

**Environment:**
- Docker containerized deployment (production and development)
- CKAN 2.9.11 (production config), 2.11 (production Dockerfile base)
- Python 3.10 runtime in Docker images

**Package Manager:**
- pip - Python package management
- uv - Used in development for running tests and managing dependencies (see CLAUDE.md)
- setuptools - Extension packaging (setup.py, pyproject.toml for setup)

**Lockfile:**
- pip uses requirements files (not automated lockfiles like poetry.lock)
- Extensions use pyproject.toml (ckanext-oauth2) or setup.py for dependency declaration

## Frameworks

**Core:**
- CKAN 2.9.11 - Data catalog framework (main application)
- Flask 3.0.3 - Web framework (CKAN is built on Flask)

**API & Views:**
- Werkzeug 3.0.6 - WSGI toolkit (Flask dependency)
- WebAssets 2.0 - Static asset management
- Jinja2 3.1.6 - Template engine

**Authentication & Sessions:**
- Flask-Login 0.6.3 - User session management
- Flask-Session 0.8.0 - Session backend abstraction
- Flask-WTF 1.2.1 - CSRF protection for forms
- Flask-Babel 4.0.0 - Internationalization

**ORM & Database:**
- SQLAlchemy 1.4.52 - Python ORM and database toolkit
- Psycopg2 2.9.9 - PostgreSQL adapter

**OAuth2 & Security:**
- PyJWT 2.8.0 - JWT token encoding/decoding
- cryptography 43.0.0+ - Cryptographic operations
- oauthlib 3.3.1+ - OAuth2 protocol library
- requests-oauthlib 2.0.0+ - OAuth2 support for requests library
- Passlib 1.7.4 - Password hashing

**Testing:**
- pytest 8.4.2+ - Test runner (ckanext-oauth2)
- pytest-factoryboy 2.8.1+ - Test factory fixtures (ckanext-oauth2)
- httpretty 1.1.4+ - HTTP mocking for tests (ckanext-oauth2)
- parameterized 0.9.0+ - Parameterized test support (ckanext-oauth2)

**Build & Development:**
- Alembic 1.13.2 - Database migration tool
- setuptools 61.0+ - Package building

## Key Dependencies

**Critical:**
- CKAN 2.9.11+ - Core data catalog framework, underpins all functionality
- SQLAlchemy 1.4.52 - Database ORM and query building
- requests 2.32.3 - HTTP client library for API calls to external services (Tapis, OAuth2 providers)
- PyJWT 2.8.0 - JWT token verification for OAuth2 integration

**Infrastructure:**
- RQ 1.16.2 - Redis-backed job queue (background task execution)
- Babel 2.15.0 - Translation/i18n framework
- Bleach 6.1.0 - HTML sanitization
- Markdown 3.6 - Markdown to HTML conversion
- Feedgen 1.0.0 - Atom/RSS feed generation
- pysolr 3.9.0 - Solr search client (search functionality)

**Geospatial:**
- Shapely 2.0.6 - Geometric object operations
- pyproj 3.6.1 (Python 3.9+) - Coordinate transformation
- OWSLib 0.32.0 (Python 3.10+) - OGC Web Services client
- geojson 3.1.0 - GeoJSON encoding/decoding
- lxml 2.3+ - XML processing

**Utilities:**
- python-dateutil 2.9.0.post0 - Date utilities
- python-magic 0.4.27 - File type detection
- simplejson 3.19.2 - JSON serialization
- PyYAML 6.0.1 - YAML parsing
- msgspec 0.18.6 - MessagePack serialization
- typing-extensions 4.12.2 - Type hint backports
- packaging 24.1 - Version parsing
- pytz 2025.2+ - Timezone handling
- tzlocal 5.2 - Local timezone detection
- certifi 2024.7.4+ - SSL certificate bundle
- click 8.1.7 - CLI framework
- zope.interface 6.4.post2 - Interface definitions

**Frontend Assets:**
- json5 - JSON5 parsing (ckanext-potree, for cloud point data)
- jQuery UI - JavaScript UI widgets (ckanext-potree)

## Configuration

**Environment:**
- Configuration via environment variables defined in `.env.prod.config` and `.env.dev.config`
- Secrets in `.env.prod.secrets` and `.env.dev.secrets` (not committed)
- Template: `.env.secrets.example`

**Key Configuration Variables:**
- CKAN_VERSION - CKAN application version
- CKAN_SITE_URL - Base URL for CKAN instance
- CKAN_SITE_ID - Site identifier
- CKAN_STORAGE_PATH - Directory for file storage
- CKAN_SOLR_URL - Solr search engine endpoint
- CKAN_REDIS_URL - Redis cache/queue endpoint
- CKAN_DATAPUSHER_URL - DataPusher data processing service
- CKAN_OAUTH2_* - OAuth2 configuration (endpoints, credentials, field mappings)
- CKANEXT__SPATIAL__* - Spatial extension configuration
- CKANEXT__TACC_THEME__* - TACC theme URLs
- CKAN___SCHEMING__* - Dataset schema definitions

**Build:**
- `ckan/Dockerfile` - Production image (base: ckan/ckan-base:2.11)
- `ckan/Dockerfile.dev` - Development image (base: ckan/ckan-dev:2.11)
- `postgresql/Dockerfile` - PostgreSQL 12 Alpine base image
- `ckan/requirements/ckanext-spatial.txt` - Spatial extension dependencies

## Services

**Core Services (Docker Compose):**

- **CKAN (ckan/ckan-dev or ckan)** - Main application server on port 5000
  - Health check: HTTP GET to `/api/action/status_show`
  - Volumes: `/var/lib/ckan` (storage), source extensions

- **PostgreSQL (db)** - Database server
  - Image: postgres:12-alpine
  - Databases created: `ckan` (CKAN), `datastore` (CKAN read-only copy)
  - Test databases for CI/CD

- **Solr (solr)** - Search and indexing on port 8983
  - Image: ckan/ckan-solr:2.9-solr9-spatial
  - Spatial query support enabled

- **Redis (redis)** - Caching and job queue
  - Image: redis:6
  - Database 1 for CKAN sessions/cache and harvest MQ

- **DataPusher (datapusher)** - Data processing service on port 8800
  - Image: ckan/ckan-base-datapusher:0.0.20
  - Processes uploaded tabular data

## Platform Requirements

**Development:**
- Docker and Docker Compose
- Python 3.10 (for local development outside containers)
- uv package manager (for running tests via CLAUDE.md instructions)
- Optional: local PostgreSQL 12 (if not using Docker)

**Production:**
- Docker and Docker Compose deployment
- External file storage: TACC Corral file system (mounted to `/data/ckan`)
- Nginx reverse proxy (port 8443 for SSL)
- Network connectivity to TACC OAuth2 service (portals.tapis.io)
- Network connectivity to Tapis file API (portals.tapis.io/v3/files)

---

*Stack analysis: 2026-02-14*
