# Architecture

**Analysis Date:** 2026-02-14

## Pattern Overview

**Overall:** Multi-layered Docker-based CKAN data portal with plugin-driven extensibility

**Key Characteristics:**
- CKAN 2.11 core with plugin-based architecture for extensibility
- OAuth2-based authentication with TACC Tapis identity provider
- Microservices architecture with PostgreSQL, Solr, Redis, and DataPusher
- Custom CKAN extensions for theming, schema validation, and 3D visualization
- Separation of metadata storage (PostgreSQL) from file storage (TACC Corral)

## Layers

**Web/HTTP Layer:**
- Purpose: Expose Flask-based REST API and web interface
- Location: CKAN server (port 5000), Nginx reverse proxy with SSL termination
- Contains: Flask blueprints, routes defined in extension plugins
- Depends on: CKAN plugins framework, authentication middleware
- Used by: External users, client applications, web browsers

**Authentication & Authorization Layer:**
- Purpose: OAuth2 authentication and token management
- Location: `src/ckanext-oauth2/ckanext/oauth2/`
- Contains: OAuth2Helper (token lifecycle), plugin hooks (IAuthenticator, IAuthFunctions), database models
- Depends on: Flask-Login, TACC Tapis OAuth2 provider, local PostgreSQL for token storage
- Used by: All HTTP requests via identify() plugin hook, template helpers for token access

**Application/Business Logic Layer:**
- Purpose: Core CKAN data management and extension coordination
- Location: CKAN base image (ckan/ckan-base:2.11) with custom plugins
- Contains: API action functions, dataset/resource management, plugin initialization
- Depends on: SQLAlchemy ORM, CKAN toolkit (abstraction layer), Redis for caching
- Used by: Web layer, DataPusher callbacks, CLI commands

**Data Access Layer:**
- Purpose: Persistent storage and search indexing
- Location: PostgreSQL (port 5432), Solr (port 8983), Redis (port 6379)
- Contains: Dataset metadata, datastore tables, search indices, cache/session data
- Depends on: Network connectivity between containers
- Used by: CKAN application, DataPusher service

**Extension/Plugin Layer:**
- Purpose: Augment core CKAN with custom functionality
- Location: `src/` directory with individual extension packages
- Contains: IPlugin implementations, custom templates, assets, database migrations
- Depends on: CKAN plugin interface definitions
- Used by: CKAN core during initialization and request processing

## Data Flow

**User Login Flow:**
1. User navigates to `/user/login` endpoint
2. OAuth2 plugin's `identify()` hook checks for Bearer token or session
3. If not authenticated, `views.login()` triggers OAuth2 `challenge()` (redirect to TACC authorization)
4. User authorizes in Tapis OAuth2 provider
5. Provider redirects to `/oauth2/callback` with authorization code
6. Callback handler exchanges code for token via `OAuth2Helper.get_token()`
7. Token unwrapped per `CKAN_OAUTH2_TOKEN_RESPONSE_PATH` configuration
8. User profile fetched via `OAuth2Helper.identify(token)` from Tapis userinfo endpoint
9. CKAN user created/updated, token stored in `user_token` table
10. Session established via `login_user()` from Flask-Login

**API Request Flow (Bearer Token):**
1. Request arrives with `Authorization: Bearer <JWT>` header
2. `identify()` hook extracts token from header
3. JWT verified per configuration (algorithm, public key/secret)
4. Token payload parsed for username field (`CKAN_OAUTH2_JWT_USERNAME_FIELD`)
5. CKAN user object loaded and set in `g.user`, `g.userobj`, `g.usertoken`
6. Token automatically refreshed before expiration if refresh_token available

**Dataset Storage & Retrieval:**
1. Dataset metadata stored in PostgreSQL via CKAN ORM
2. File URLs prefixed with `tapis://` routed to `TapisFilestorePlugin`
3. Tapis file requests intercepted by `/tapis-file/<path>` blueprint
4. OAuth token passed from `g.usertoken` to Tapis file service
5. File streamed from TACC Corral to client via Flask response

**Search Indexing:**
1. Dataset create/update triggers `IResourceController` hooks
2. Metadata indexed to Solr via CKAN's search API
3. Spatial metadata indexed using ckanext-spatial
4. Search queries executed against Solr backend via CKAN's search interface

**3D Resource Viewer:**
1. Potree plugin registers as IResourceView for `.json` scenes
2. Resource request routed to `/dataset/potree/<resource_id>`
3. Scene metadata retrieved from PostgreSQL
4. Potree.js assets served from extension public directory
5. 3D scene rendered client-side in browser

## Key Abstractions

**OAuth2Helper:**
- Purpose: Encapsulate OAuth2 protocol handling and token lifecycle
- Examples: `src/ckanext-oauth2/ckanext/oauth2/oauth2.py`
- Pattern: Stateless utility class initialized at plugin startup with configuration
- Responsibilities: Challenge flow, token exchange, user identification, token refresh, JWT parsing

**CKAN Plugin Interface:**
- Purpose: Extension points that allow custom code to integrate with CKAN
- Examples: `src/ckanext-*/ckanext/*/plugin.py`
- Pattern: Class-based plugins implementing CKAN interface mixins (IConfigurer, IBlueprint, etc.)
- Common implementations: Update config, register blueprints, provide template helpers, validate auth

**UserToken Domain Object:**
- Purpose: Map OAuth2 tokens to CKAN users in persistent storage
- Examples: `src/ckanext-oauth2/ckanext/oauth2/db.py`
- Pattern: SQLAlchemy ORM model with simple key-value lookup (user_name → token)
- Used by: Token refresh flow, token retrieval for Tapis file access

**Flask Blueprint:**
- Purpose: Register URL routes for custom endpoints
- Examples: `src/ckanext-oauth2/ckanext/oauth2/views.py`, `src/ckanext-potree/ckanext/potree/views.py`
- Pattern: Define blueprint routes in plugin's `get_blueprint()` method
- Routes: `/user/login`, `/oauth2/callback`, `/dataset/potree/<id>`, `/tapis-file/<path>`

**Template Helpers:**
- Purpose: Expose Python functions to Jinja2 templates
- Examples: `tacc_theme.safe_oauth2_get_stored_token()`, `potree.is_potree_resource()`
- Pattern: Dictionary returned from plugin's `get_helpers()` with function references
- Usage: Called in templates to fetch dynamic data or perform conditional rendering

## Entry Points

**Web Server:**
- Location: `ckan:5000` (port 5000 in docker-compose)
- Triggers: HTTP requests from users/clients
- Responsibilities: Route requests to appropriate CKAN action/view, execute authorization checks, render templates

**DataPusher Callback:**
- Location: DataPusher service (port 8800), callback to `http://ckan-dev:5000`
- Triggers: When CSV/JSON files are uploaded and need transformation
- Responsibilities: Extract and validate data, create datastore tables, index rows

**CLI Entry Points:**
- Location: `ckan` command in Docker container shell
- Triggers: Manual operations or initialization scripts in docker-entrypoint.d
- Examples: `ckan sysadmin add`, `ckan db upgrade -p oauth2`

**Docker Entrypoint Scripts:**
- Location: `ckan/docker-entrypoint.d/*.sh` (copied to `/docker-entrypoint.d/` in image)
- Triggers: Container startup
- Examples: `01_setup_datapusher.sh`, `03_setup_oauth2.sh`
- Responsibilities: Initialize extensions, load default data, configure services

## Error Handling

**Strategy:** Layered exception handling with user-facing feedback

**Patterns:**
- OAuth2 callback errors caught and flashed to user via `helpers.flash_error()`
- Database transaction rollbacks on callback failure: `model.Session.rollback()`
- JWT verification failures logged but don't block request (fall back to session auth)
- Token refresh failures trigger logout: set `g.user = None`, `logout_user()`
- Tapis file access errors caught in `_get_tapis_token()` with fallback to Bearer header

## Cross-Cutting Concerns

**Logging:** Standard Python logging module
- OAuth2: `log = logging.getLogger(__name__)` in each module
- Token operations logged at DEBUG level for troubleshooting
- Auth failures logged at ERROR level for security auditing

**Validation:** CKAN toolkit + Scheming extension
- Datasets validated against schema defined in `ckanext-dso_scheming` YAML files
- OAuth2 response validation: check required fields (username, email) present
- JWT validation: signature verification, algorithm checking, field extraction

**Authentication:** OAuth2 plugin provides two auth mechanisms
1. Bearer token via Authorization header (API/JWT flow)
2. Session cookie via Flask-Login (web UI flow)
- Both converge to `g.user`, `g.usertoken` for downstream code

**Authorization:** CKAN auth functions decorated with `@toolkit.auth_sysadmins_check`
- OAuth2 plugin restricts user creation/password reset to prevent local account management
- Resource access controlled by existing CKAN package/group permissions
- OAuth2 enables sysadmin assignment via `CKAN_OAUTH2_SYSADMIN_GROUP_NAME` group membership

---

*Architecture analysis: 2026-02-14*
