# Codebase Structure

**Analysis Date:** 2026-02-14

## Directory Layout

```
ckan/
├── ckan/                              # CKAN Docker image build configuration
│   ├── Dockerfile                     # Production image (CKAN 2.11 base + extensions)
│   ├── Dockerfile.dev                 # Development image (with live code reloading)
│   ├── docker-entrypoint.d/           # Initialization scripts run at container startup
│   ├── patches/                       # Patches applied to CKAN core and extensions
│   └── requirements/                  # Additional Python dependencies
│
├── src/                               # Custom CKAN extensions (mounted as volumes in dev)
│   ├── ckanext-oauth2/                # OAuth2 authentication extension
│   │   └── ckanext/oauth2/
│   │       ├── plugin.py              # Plugin entry point (IAuthenticator, IBlueprint)
│   │       ├── oauth2.py              # OAuth2Helper class (token lifecycle, JWT)
│   │       ├── views.py               # Flask blueprint for /user/login and /oauth2/callback
│   │       ├── db.py                  # SQLAlchemy model for user_token table
│   │       ├── cli.py                 # CLI commands (ckan oauth2 *)
│   │       ├── constants.py           # Constants (REDIRECT_URL, CAME_FROM_FIELD)
│   │       ├── templates/             # Jinja2 templates for OAuth2 UI
│   │       ├── migration/             # Alembic database migrations
│   │       ├── tests/                 # Unit and integration tests
│   │       └── __init__.py            # Package initialization
│   │
│   ├── ckanext-tacc_theme/            # TACC branding and UI customization
│   │   └── ckanext/tacc_theme/
│   │       ├── plugin.py              # IConfigurer (templates/assets/resources)
│   │       ├── templates/             # Custom Jinja2 templates (base, home, packages)
│   │       ├── public/                # Static assets (CSS, images, JS)
│   │       ├── assets/                # Webassets resources
│   │       ├── fanstatic/             # Resource files bundled by CKAN
│   │       └── tests/                 # Theme plugin tests
│   │
│   ├── ckanext-dso_scheming/          # Dataset schema definitions (DSO, MINT, SUBSIDE)
│   │   └── ckanext/dso_scheming/
│   │       ├── plugin.py              # IConfigurer (registers schema files)
│   │       ├── ckan_dataset.yaml      # Base CKAN dataset schema
│   │       ├── mint_dataset.yaml      # MINT-specific dataset schema
│   │       ├── subside_dataset.yaml   # SUBSIDE-specific dataset schema
│   │       ├── presets.json           # Field presets for all schemas
│   │       ├── mint_presets.json      # MINT-specific field presets
│   │       ├── templates/             # Schema-specific templates
│   │       └── tests/                 # Schema plugin tests
│   │
│   ├── ckanext-tapisfilestore/        # Integration with TACC Tapis file system
│   │   └── ckanext/tapisfilestore/
│   │       ├── plugin.py              # IBlueprint, IResourceController
│   │       ├── views.py               # File serving endpoints
│   │       ├── templates/             # Tapis file UI templates
│   │       └── tests/                 # Plugin tests
│   │
│   └── ckanext-potree/                # 3D point cloud visualization (Potree.js)
│       └── ckanext/potree/
│           ├── plugin.py              # IResourceView (3D scene viewer registration)
│           ├── views.py               # Scene endpoints (/dataset/potree/<id>)
│           ├── helpers.py             # Helper functions for template logic
│           ├── public/potree/         # Potree library assets
│           ├── templates/             # Scene viewer templates
│           └── tests/                 # Plugin tests
│
├── nginx/                             # Nginx reverse proxy configuration
│   └── setup/                         # SSL/TLS setup scripts
│
├── postgresql/                        # PostgreSQL Docker image configuration
│   └── docker-entrypoint-initdb.d/    # Database initialization scripts
│
├── scripts/                           # Utility scripts for operations
│   ├── database/                      # Database backup/restore utilities
│   │   ├── backup-db.sh               # Creates timestamped PostgreSQL dumps
│   │   └── restore-db.sh              # Restores from backup dumps
│   └── tapis-oauth/                   # OAuth2 client management
│       ├── create-client.sh           # Registers OAuth2 client with Tapis
│       └── get-jwt.sh                 # Retrieves JWT token for API testing
│
├── docker-compose.yml                 # Production deployment (external storage, no volumes)
├── docker-compose.dev.yml             # Development deployment (volume mounts for hot reload)
├── .env.dev.config                    # Development environment config (CKAN plugins, OAuth2)
├── .env.dev.secrets                   # Development secrets (OAuth2 client secret, DB creds)
├── .env.prod.config                   # Production environment config
├── .env.prod.secrets                  # Production secrets
├── .env.secrets.example               # Template for secrets files
├── CLAUDE.md                          # Development guidance for Claude Code
├── README.md                          # High-level overview
├── README-Docker.md                   # Docker deployment instructions
└── architecture-diagram.md            # Mermaid diagrams of system architecture
```

## Directory Purposes

**ckan/:**
- Purpose: Docker image build configuration and startup scripts
- Contains: Dockerfile definitions, entrypoint scripts, patches, dependencies
- Key files: `Dockerfile` (production), `Dockerfile.dev` (development)

**src/:**
- Purpose: Custom CKAN extensions providing OAuth2, theming, schemas, and integrations
- Contains: Five extension packages, each following standard CKAN extension structure
- Key files: Each extension's `plugin.py` (entry point)

**src/ckanext-oauth2/:**
- Purpose: Authentication layer - OAuth2 token lifecycle and JWT verification
- Contains: OAuth2Helper (core logic), Flask blueprint, SQLAlchemy models
- Key files:
  - `oauth2.py`: OAuth2Helper class (token exchange, JWT parsing, user identification)
  - `plugin.py`: Plugin registration and IAuthenticator implementation
  - `views.py`: HTTP endpoints for login flow
  - `db.py`: user_token table schema and ORM

**src/ckanext-tacc_theme/:**
- Purpose: Visual branding and UI customization for TACC deployment
- Contains: Custom templates, static assets, CSS
- Key files:
  - `plugin.py`: Registers template directory and public assets
  - `templates/`: Overrides CKAN base templates
  - `public/images/`: TACC logos and branding

**src/ckanext-dso_scheming/:**
- Purpose: Dataset schema definitions for different project types (DSO, MINT, SUBSIDE)
- Contains: YAML schema files, field presets, templates
- Key files:
  - `ckan_dataset.yaml`: Base dataset schema (title, description, tags, resources)
  - `mint_dataset.yaml`: Extended schema for MINT modeling projects
  - `subside_dataset.yaml`: Extended schema for SUBSIDE datasets
  - `presets.json`: Common field definitions (dropdown options, validators)

**src/ckanext-tapisfilestore/:**
- Purpose: Serve files from TACC Corral file system (tapis:// URLs)
- Contains: File streaming logic, OAuth2 token injection for Tapis API
- Key files:
  - `plugin.py`: Flask blueprint for `/tapis-file/<path>` endpoint
  - `views.py`: HTTP streaming and content-type handling

**src/ckanext-potree/:**
- Purpose: 3D point cloud visualization using Potree.js library
- Contains: Scene viewer templates, Potree.js assets, 3D rendering logic
- Key files:
  - `plugin.py`: Registers as IResourceView for `.json` scenes
  - `views.py`: Scene viewer endpoints and editor
  - `public/potree/`: Potree.js library (pre-built from GitHub release)

**nginx/:**
- Purpose: Reverse proxy configuration for HTTPS/TLS termination
- Contains: Nginx config, SSL certificate setup
- Key files: `setup/`: Scripts for certificate generation

**postgresql/:**
- Purpose: PostgreSQL database Docker image
- Contains: Initialization scripts for CKAN and datastore schemas
- Key files: `docker-entrypoint-initdb.d/`: Runs SQL on first container startup

**scripts/:**
- Purpose: Operational utilities for database and OAuth2 management
- Contains: Backup/restore scripts, OAuth2 client registration
- Key files:
  - `backup-db.sh`: Creates timestamped PostgreSQL dumps
  - `create-client.sh`: Registers CKAN as OAuth2 client with Tapis
  - `get-jwt.sh`: Retrieves JWT token for manual API testing

## Key File Locations

**Entry Points:**
- `docker-compose.yml`: Production service definitions (CKAN, DataPusher, PostgreSQL, Solr, Redis)
- `docker-compose.dev.yml`: Development service definitions (with volume mounts)
- `ckan/docker-entrypoint.d/`: Scripts executed at container startup (schema setup, migrations)
- `ckan/Dockerfile`: Production image with extensions pre-installed
- `ckan/Dockerfile.dev`: Development image with volume mounts for hot reload

**Configuration:**
- `.env.dev.config`: Development environment variables (CKAN plugins, OAuth2 endpoints, Solr/Redis URLs)
- `.env.dev.secrets`: Development secrets (OAuth2 client ID/secret, database passwords)
- `.env.prod.config`: Production environment configuration
- `.env.prod.secrets`: Production secrets (must not be committed)

**Core Logic:**
- `src/ckanext-oauth2/ckanext/oauth2/oauth2.py`: OAuth2Helper class - token handling, JWT, user identification
- `src/ckanext-oauth2/ckanext/oauth2/plugin.py`: IAuthenticator implementation - user identification hook
- `src/ckanext-oauth2/ckanext/oauth2/views.py`: Flask blueprint - `/user/login`, `/oauth2/callback` routes
- `src/ckanext-oauth2/ckanext/oauth2/db.py`: user_token table - OAuth2 token persistence
- `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py`: File serving via Tapis API

**Testing:**
- `src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py`: OAuth2Helper tests (token exchange, JWT)
- `src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py`: Plugin integration tests
- `src/ckanext-oauth2/ckanext/oauth2/tests/test_db.py`: Database model tests
- `src/ckanext-tacc_theme/ckanext/tacc_theme/tests/test_plugin.py`: Theme plugin tests
- `src/ckanext-dso_scheming/ckanext/dso_scheming/tests/test_plugin.py`: Schema plugin tests
- `src/ckanext-tapisfilestore/ckanext/tapisfilestore/tests/test_plugin.py`: File serving tests
- `src/ckanext-potree/ckanext/potree/tests/test_plugin.py`: 3D viewer tests

## Naming Conventions

**Files:**
- Plugin entry points: `plugin.py` (required by CKAN)
- HTTP endpoints: `views.py` (Flask blueprint routes)
- Database models: `db.py` (SQLAlchemy ORM)
- Test files: `test_<module>.py` (pytest convention)
- Templates: `templates/<category>/<name>.html` (Jinja2)
- Static assets: `public/<type>/<name>.<ext>` or `fanstatic/` (CKAN bundling)

**Directories:**
- Extension root: `ckanext-<name>/` (in `src/` directory)
- Package directory: `ckanext/<name>/` (namespace package)
- Tests: `tests/` subdirectory (pytest discovers by pattern)
- Templates: `templates/` subdirectory
- Static assets: `public/`, `fanstatic/`, `assets/` subdirectories
- Migrations: `migration/<ext_name>/versions/` (Alembic)

**Classes:**
- Plugins: `<Name>Plugin` (e.g., `OAuth2Plugin`, `TaccThemePlugin`)
- Domain objects: Singular descriptive name (e.g., `UserToken`)
- Helpers: Named functions (e.g., `is_potree_resource()`, `safe_oauth2_get_stored_token()`)

**Functions:**
- Private/internal: `_function_name()` (leading underscore)
- Public API: `function_name()` (no underscore)
- Test functions: `test_<feature>()` (pytest convention)
- Flask routes: `route_handler_name()` (descriptive)

## Where to Add New Code

**New Feature (e.g., Export to CSV):**
- Primary code: Create in appropriate extension directory or new extension
- Plugin hook: Implement in extension's `plugin.py` (e.g., `IPackageController`)
- Templates: `src/ckanext-<name>/ckanext/<name>/templates/<category>/`
- Tests: `src/ckanext-<name>/ckanext/<name>/tests/test_<feature>.py`
- Example: Adding new export format → `src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/` for UI

**New HTTP Endpoint:**
- Implementation: Add route to Flask blueprint in extension's `views.py` or create new blueprint
- Register: Return blueprint from plugin's `get_blueprint()` method
- Template: Create template in `templates/` for response rendering
- Tests: `test_<endpoint>.py` testing route, parameters, auth
- Example: New OAuth2 scopes endpoint → `src/ckanext-oauth2/ckanext/oauth2/views.py` + `plugin.py`

**New Component/Module (e.g., Custom Validator):**
- Implementation: Create file in extension's main directory
- Import/Export: Import in `__init__.py` or module using it
- Tests: Separate test file with parametrized test cases
- Documentation: Add docstring to class/function
- Example: Token refresh logic → already in `src/ckanext-oauth2/ckanext/oauth2/oauth2.py`

**Utilities/Helpers:**
- Shared helpers: `src/ckanext-potree/ckanext/potree/helpers.py` (not extension-specific)
- Template helpers: Return dict from plugin's `get_helpers()` method
- Location: Keep in extension that owns the feature
- Reusable across extensions: Consider centralizing or creating shared extension

**Database Migration:**
- Tool: Alembic (configured in extension root)
- Location: `src/ckanext-oauth2/ckanext/oauth2/migration/oauth2/versions/`
- Naming: `<timestamp>_<description>.py` (auto-generated by `alembic revision -m`)
- Apply: `ckan db upgrade -p oauth2` (in Docker container)

**Tests:**
- Location: `src/ckanext-<name>/ckanext/<name>/tests/`
- Pattern: `test_<module>.py` with `test_<feature>()` functions
- Fixtures: Use `conftest.py` for shared test setup
- Mocking: Use `unittest.mock`, `httpretty` for HTTP mocking
- Example: `src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py`

## Special Directories

**ckan/docker-entrypoint.d/:**
- Purpose: Initialization scripts run at container startup
- Generated: No, manually maintained
- Committed: Yes, version controlled
- Examples: `01_setup_datapusher.sh`, `03_setup_oauth2.sh`
- Run as: `ckan` user (non-root)

**ckan/patches/:**
- Purpose: Patches applied to CKAN core and extensions
- Generated: No, manually created
- Committed: Yes
- Format: Standard diff patches (created with `diff -u`)
- Applied at: Docker image build time in Dockerfile

**.env files:**
- Purpose: Configuration passed to Docker containers
- Generated: No, created from `.env.secrets.example` template
- Committed: `.env.*.example` (templates), NOT `.env.*.secrets` (contains secrets)
- Usage: `docker-compose --env-file` loads both config and secrets files
- Important: Never commit `.env.dev.secrets` or `.env.prod.secrets`

**src/ckanext-oauth2/migration/:**
- Purpose: Alembic database migrations for user_token table
- Generated: Via `alembic revision -m "message"`
- Committed: Yes, version controlled
- Location: `src/ckanext-oauth2/ckanext/oauth2/migration/oauth2/versions/`
- Applied: `ckan db upgrade -p oauth2` command

**src/ckanext-*/public/ and fanstatic/:**
- Purpose: Static assets (CSS, JS, images) served by CKAN
- Generated: Potree assets downloaded from GitHub release during build
- Committed: Yes (source files), downloaded assets not committed
- Path mapping: `public/` → `/base/`, `fanstatic/` → bundled by webassets

---

*Structure analysis: 2026-02-14*
