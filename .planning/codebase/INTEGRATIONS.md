# External Integrations

**Analysis Date:** 2026-02-14

## APIs & External Services

**TACC OAuth2 (Tapis):**
- Service: Tapis OAuth2 provider at portals.tapis.io
- What it's used for: User authentication and authorization via OAuth2 protocol
- SDK/Client: requests-oauthlib (Python library), custom OAuth2Helper in ckanext-oauth2
- Auth:
  - Environment: CKAN_OAUTH2_CLIENT_ID, CKAN_OAUTH2_CLIENT_SECRET
  - Location: `.env.prod.secrets` and `.env.dev.secrets`
  - Files: `src/ckanext-oauth2/ckanext/oauth2/oauth2.py` - OAuth2Helper class
  - Dev credentials in `.env.dev.config` (localhost-ckan client for testing)

**Tapis File API:**
- Service: https://portals.tapis.io/v3/files/* (Tapis file operations)
- What it's used for: Proxying file operations and serving files from Tapis file system
- SDK/Client: requests library for HTTP calls
- Auth: X-Tapis-Token header or OAuth2 token from CKAN session
- Files: `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py`
- Endpoints:
  - `https://portals.tapis.io/v3/files/ops/{file_path}` - File metadata/operations
  - `https://portals.tapis.io/v3/files/content/{file_path}` - File download

**MINT/DYNAMO Dashboard:**
- Service: https://mint.tacc.utexas.edu (modeling/analysis platform)
- What it's used for: Integration link in TACC theme for modeling projects
- Configuration: CKANEXT__TACC_THEME__DYNAMO_DASHBOARD_URL
- Files: `src/ckanext-tacc_theme/` theme templates

**Ensemble Manager API:**
- Service: https://ensemble-manager.mint.tacc.utexas.edu/v1 (modeling ensemble management)
- What it's used for: Integration with ensemble modeling workflows
- Configuration: CKANEXT__TACC_THEME__ENSEMBLE_MANAGER_API_URL
- Files: `src/ckanext-tacc_theme/` theme templates

## Data Storage

**Databases:**

**Primary - PostgreSQL (Main CKAN):**
- Type: PostgreSQL 12
- Connection: postgres://ckan:ckan@db/ckan (dev), production via environment variables
- Client: SQLAlchemy ORM (psycopg2 adapter)
- Environment: POSTGRES_DB, POSTGRES_HOST, CKAN_DB
- Location: Docker service `db` in docker-compose.yml
- Initialization: `postgresql/docker-entrypoint-initdb.d/` scripts

**Datastore - PostgreSQL (Read-only):**
- Type: PostgreSQL (same instance as CKAN database)
- Connection: postgresql://datastore_ro:datastore@db/datastore
- Purpose: Read-only copy of CKAN data for analysis
- Environment: DATASTORE_DB, TEST_CKAN_DATASTORE_READ_URL, TEST_CKAN_DATASTORE_WRITE_URL
- Initialization: `postgresql/docker-entrypoint-initdb.d/20_create_datastore.sh`

**Test Databases:**
- CKAN test: postgres://ckan:ckan@db/ckan_test
- Datastore test: postgresql://datastore_ro:datastore@db/datastore_test
- Environment: TEST_CKAN_SQLALCHEMY_URL, TEST_CKAN_DATASTORE_WRITE_URL, TEST_CKAN_DATASTORE_READ_URL
- Initialization: `postgresql/docker-entrypoint-initdb.d/30_setup_test_databases.sh`

**File Storage:**
- Type: External file system (TACC Corral)
- Location: Mounted to `/data/ckan` on host, exposed as `/var/lib/ckan` in container
- Configuration: CKAN_STORAGE_PATH=/var/lib/ckan
- Purpose: Dataset file storage and uploads
- Note: Not using local filesystem - uses external TACC infrastructure

**Dynamic Files via Tapis:**
- Type: TACC Tapis file system (portals.tapis.io)
- Purpose: Serve files via tapis:// URLs in datasets
- Integration: ckanext-tapisfilestore proxies requests through Tapis API
- Authentication: OAuth2 token from CKAN session or X-Tapis-Token header
- Files: `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py`

## Caching & Sessions

**Redis:**
- Type: Redis 6
- Service: Internal Docker service `redis:6`
- Connection: redis://redis:6379/1
- Purposes:
  - CKAN session/cache backend: Database 1
  - Harvest job queue: Database 1
- Environment: CKAN_REDIS_URL, TEST_CKAN_REDIS_URL
- Configuration: CKAN__HARVEST__MQ__HOSTNAME, CKAN__HARVEST__MQ__PORT, CKAN__HARVEST__MQ__REDIS_DB

## Search & Indexing

**Solr:**
- Type: Apache Solr 9 with spatial support
- Service: Docker image ckan/ckan-solr:2.9-solr9-spatial
- Connection: http://solr:8983/solr/ckan
- Purpose: Full-text search and spatial queries on datasets
- Environment: CKAN_SOLR_URL, TEST_CKAN_SOLR_URL
- Configuration: CKANEXT__SPATIAL__SEARCH__BACKEND=solr-bbox
- Client: pysolr library
- Web UI: http://localhost:8983 (accessible in development)

## Authentication & Identity

**Auth Provider:**
- Service: TACC Tapis OAuth2 (https://portals.tapis.io)
- Implementation: OAuth2 protocol with JWT token support
- CKAN Extension: ckanext-oauth2
- Location: `src/ckanext-oauth2/ckanext/oauth2/`

**OAuth2 Configuration:**
- Authorization Endpoint: https://portals.tapis.io/v3/oauth2/authorize
- Token Endpoint: https://portals.tapis.io/v3/oauth2/tokens
- User Profile Endpoint: https://portals.tapis.io/v3/oauth2/userinfo
- Scope: openid profile email
- JWT Support: Enabled (CKAN_OAUTH2_JWT_ENABLE=true)
- JWT Algorithm: Default HS256 (configurable for RS256, ES256)
- JWT Username Field: 'tapis/username'
- Response Unwrapping: Tapis API wraps responses in "result" envelope
  - Token response path: `result.access_token`
  - Profile response path: `result`

**User Profile Field Mapping:**
- Username field: 'username'
- Email field: 'email'
- Full name field: 'given_name'
- First name field: 'given_name'
- Last name field: 'last_name'
- Group membership field: (optional, for group assignment)

**Local Authentication:**
- Fallback: CKAN local user accounts (when OAuth2 disabled)
- Session Token: auth_tkt cookie-based authentication
- Location: `src/ckanext-oauth2/ckanext/oauth2/plugin.py` (OAuth2Plugin)

## Data Processing

**DataPusher:**
- Service: ckan/ckan-base-datapusher:0.0.20
- Purpose: Automatic processing of uploaded tabular data (CSV, XLS, etc.)
- Connection: http://datapusher:8800
- Environment: CKAN_DATAPUSHER_URL, CKAN__DATAPUSHER__CALLBACK_URL_BASE
- Health check: HTTP GET to http://127.0.0.1:8800
- Integration: Automatic when files uploaded to CKAN

## Email & Communications

**SMTP:**
- Type: SMTP server
- Server: smtp.corporateict.domain:25 (production)
- From Address: ckan@localhost
- STARTTLS: Enabled
- Purpose: Notification emails, user signup confirmations
- Environment: CKAN_SMTP_SERVER, CKAN_SMTP_STARTTLS, CKAN_SMTP_MAIL_FROM
- Configuration: CKAN core config via environment variables

## Webhooks & Callbacks

**Incoming:**
- OAuth2 Callback: `/oauth2/callback` endpoint handles OAuth2 provider redirects
- Location: `src/ckanext-oauth2/ckanext/oauth2/views.py`
- CKAN Status: `/api/action/status_show` health check endpoint

**Outgoing:**
- DataPusher Callback: CKAN notifies DataPusher of completion
- Callback Base URL: CKAN__DATAPUSHER__CALLBACK_URL_BASE
- Development: http://ckan-dev:5000
- Production: https://ckan.tacc.utexas.edu

## CI/CD & Deployment

**Hosting:**
- Docker Compose deployment (production and development)
- Target deployment: TACC infrastructure
- Reverse Proxy: Nginx (configured separately, handles SSL on port 8443)

**Build System:**
- Extension Installation: pip install -e git+URL (during Docker build)
- Database Migrations: Alembic (run via `ckan db upgrade -p plugin_name`)
- Extension Setup: python setup.py develop for local extensions
- Build Context: Dockerfile copies extensions from `src/` directory

**Extension Installation (Dockerfile):**
```dockerfile
# Third-party extensions from GitHub
RUN pip3 install -e 'git+https://github.com/In-For-Disaster-Analytics/ckanext-oauth2.git@0.9.2#egg=ckanext-oauth2'
RUN pip3 install -e "git+https://github.com/ckan/ckanext-spatial.git#egg=ckanext-spatial"
RUN pip3 install -e "git+https://github.com/ckan/ckanext-showcase.git#egg=ckanext-showcase"
RUN pip3 install -e "git+https://github.com/ckan/ckanext-pages.git#egg=ckanext-pages"
RUN pip3 install -e "git+https://github.com/ckan/ckanext-scheming.git#egg=ckanext-scheming"

# Local extensions
COPY --chown=ckan:ckan-sys src/ckanext-tacc_theme ${APP_DIR}/src/ckanext-tacc_theme
RUN cd ${APP_DIR}/src/ckanext-tacc_theme && python3 setup.py develop --user
```

## Environment Configuration

**Required Environment Variables (Production):**
- CKAN_OAUTH2_CLIENT_ID - OAuth2 client identifier
- CKAN_OAUTH2_CLIENT_SECRET - OAuth2 client secret (sensitive)
- CKAN_SITE_URL - Public CKAN instance URL
- POSTGRES_USER, POSTGRES_PASSWORD - Database credentials (sensitive)
- All CKAN_OAUTH2_* variables for Tapis OAuth2 endpoints

**Secrets Location:**
- `.env.prod.secrets` - Production secrets (not committed)
- `.env.dev.secrets` - Development secrets (not committed)
- Template: `.env.secrets.example` (shows required keys without values)
- Location in `.gitignore` to prevent accidental commits

**Optional Configuration:**
- CKAN_OAUTH2_JWT_ENABLE - Enable JWT token verification (true/false)
- CKAN_OAUTH2_JWT_PUBLIC_KEY - Public key for JWT RS256/ES256 verification
- CKAN_OAUTH2_JWT_ALGORITHM - JWT algorithm (HS256, RS256, ES256, etc.)
- OAUTHLIB_INSECURE_TRANSPORT - Allow non-HTTPS in development (for testing)
- REQUESTS_CA_BUNDLE - Custom SSL certificate bundle path

---

*Integration audit: 2026-02-14*
