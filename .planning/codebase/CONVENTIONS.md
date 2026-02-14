# Coding Conventions

**Analysis Date:** 2026-02-14

## Naming Patterns

**Files:**
- Lowercase with underscores: `plugin.py`, `oauth2.py`, `test_oauth2.py`
- Test files follow pattern: `test_*.py` (e.g., `test_oauth2.py`, `test_db.py`, `test_plugin.py`)
- Modules organized under `ckanext.*` namespace hierarchy

**Functions:**
- Snake_case: `get_token()`, `query_profile_api_default()`, `create_user_object()`, `_unwrap_response()`
- Private/internal functions prefixed with underscore: `_unwrap_response()`, `_compliance_fix()`, `_fix_access_token()`, `_get_oauth2helper()`
- Helper functions use descriptive verbs: `generate_state()`, `get_came_from()`, `find_user()`

**Classes:**
- PascalCase: `OAuth2Helper`, `OAuth2Plugin`, `UserToken`, `TaccThemePlugin`
- Plugin classes inherit from `plugins.SingletonPlugin` and use descriptive names

**Variables:**
- Snake_case for regular variables: `user_name`, `access_token`, `profile_api_url`, `refresh_token`
- All caps for constants: `CAME_FROM_FIELD`, `INITIAL_PAGE`, `REDIRECT_URL`, `OAUTH2TOKEN`
- Configuration keys use dots for hierarchy: `ckan.oauth2.client_id`, `ckan.oauth2.jwt.enable`

**Types:**
- Use type hints in function signatures: `find_user(self, username: Optional[str], email: Optional[str]) -> Optional[model.User]`
- Type annotations used for return values and parameters in critical paths

## Code Style

**Formatting:**
- UTF-8 encoding declared at file start: `# -*- coding: utf-8 -*-`
- GNU Affero GPL v3 copyright headers included in all source files
- Line length not strictly enforced (flake8 config ignores E501)
- Four-space indentation

**Linting:**
- Tool: flake8
- Key setting: `ignore=E501` (line length warnings disabled)
- Command: `uv run flake8 ckanext/`
- Located in `setup.cfg` with matching rule in pyproject.toml

## Import Organization

**Order:**
1. Standard library imports: `os`, `logging`, `json`, `base64`, `urllib.parse`
2. Third-party imports: `requests`, `jwt`, `sqlalchemy`, `flask`, `oauthlib`, `click`
3. CKAN framework imports: `from ckan.plugins import toolkit`, `import ckan.model as model`, `from ckan.common import g`
4. Internal extension imports: `from .oauth2 import *`, `from ckanext.oauth2.db import`, `from ckanext.oauth2.constants import *`

**Pattern Examples:**
```python
# oauth2.py organization
from base64 import b64encode, b64decode, urlsafe_b64encode
from typing import Optional
import json
import logging
import os
import jwt
import requests
from urllib.parse import urljoin
from oauthlib.oauth2 import InsecureTransportError
from requests_oauthlib import OAuth2Session
from ckan.plugins import toolkit
from ckan.common import session, login_user
import ckan.model as model
import ckanext.oauth2.db as db
from .constants import *
```

**Path Aliases:**
- No import aliases used for standard patterns
- Module imports use `as` for clarity: `import ckan.model as model`, `import ckanext.oauth2.db as db`

## Error Handling

**Patterns:**
- Try-except blocks used to catch and log specific exceptions
- Re-raise exceptions after logging: `except Exception as e: log.error(...); raise`
- Broad exception catching used in user-facing code with graceful fallback
- Specific exception types caught for sensitive operations: `except requests.exceptions.SSLError as e:`
- Configuration validation throws `ValueError` with descriptive messages

**Examples from codebase:**
```python
# plugin.py - Error handling with logging
try:
    return self.oauth2helper.get_stored_token(user_name)
except Exception as e:
    log.error(f"Error getting stored token for user {user_name}: {e}")
    return None

# oauth2.py - Specific exception handling
except requests.exceptions.SSLError as e:
    if "verify failed" in str(e):
        raise InsecureTransportError()
    else:
        raise

# oauth2.py - Configuration validation
missing = [key for key in REQUIRED_CONF if getattr(self, key, "") == ""]
if missing:
    raise ValueError("Missing required oauth2 conf: %s" % ", ".join(missing))
```

## Logging

**Framework:** Python's built-in `logging` module with `getLogger(__name__)`

**Patterns:**
- Logger created at module level: `log = logging.getLogger(__name__)`
- Debug level for detailed operational flow: `log.debug(f'get_token: token_endpoint={self.token_endpoint}')`
- Info level for configuration and setup: `log.info('OAuth2 endpoint config: ...')`
- Warning level for recoverable issues: `log.warning(f'Token refresh unsuccessful for user {user_name}, logging out')`
- Error level for exceptions: `log.error(f"Error getting stored token for user {user_name}: {e}")`
- Use f-strings for formatting: `log.debug(f'Refreshing token for user {user_name}')`
- Use %-style formatting for multi-line logs: `log.info('OAuth2 profile field config: user_field=%s, mail_field=%s, ...', fields...)`

**Examples:**
```python
# Debug logging
log.debug(f'Init OAuth2 extension')
log.debug('Challenge: Redirecting challenge to page {0}'.format(auth_url))

# Info logging with configuration
log.info('OAuth2 endpoint config: profile_api_url=%s, authorization_endpoint=%s, token_endpoint=%s',
         self.profile_api_url, self.authorization_endpoint, self.token_endpoint)

# Warning logging
log.warning('The user is not currently logged...')
```

## Comments

**When to Comment:**
- Docstrings for public methods and classes
- Inline comments for non-obvious logic or workarounds
- Comments prefixed with TODO for planned work
- Comments explaining WHY, not WHAT

**JSDoc/Docstring Style:**
- Python docstrings for methods with triple quotes
- Format: `"""Single line description."""` or multi-line for complex functions
- Example from oauth2.py:
```python
def _unwrap_response(self, data, path):
    """Unwrap a nested API response by following a dot-separated path.

    If path is empty/None, returns data unchanged.
    """
```

- Legacy comment pattern: `# Just because of FIWARE Authentication`
- Compatibility comments: `# TODO search a better way to detect invalid certificates`

## Function Design

**Size:** Functions are typically 10-50 lines; larger functions break into helpers:
- `identify()` in oauth2.py is ~35 lines, handles complex OAuth2 authentication flow
- `create_user_object()` is ~25 lines with detailed field extraction logic
- `get_profile_from_jwt()` is ~60 lines due to multiple field extraction branches

**Parameters:**
- Methods use `self` for class instances
- Configuration passed via constructor `__init__()`: `OAuth2Helper(config)`
- Environment variables checked via `os.environ.get()`
- Optional parameters use type hints: `Optional[str]`, `Optional[model.User]`
- Keyword arguments used for configuration flags

**Return Values:**
- Methods return typed values: `Optional[model.User]`, `model.User`, dict
- Exceptions raised for error conditions rather than returning None
- Helper methods return toolkit responses: `toolkit.redirect_to()`, `toolkit.render()`
- None returned for missing/optional data with explicit logging

## Module Design

**Exports:**
- No explicit `__all__` in extensions; CKAN plugin discovery handles loading
- Plugin classes implement CKAN interfaces via `plugins.implements()`
- Helpers registered via `get_helpers()` returning a dict
- CLI commands registered via `get_commands()`

**Barrel Files:**
- No barrel file pattern used
- Each module has single responsibility:
  - `plugin.py`: Plugin interface implementation
  - `oauth2.py`: OAuth2 logic and token handling
  - `db.py`: Database models and ORM mapping
  - `views.py`: Flask blueprints and routes
  - `cli.py`: Command-line interface
  - `constants.py`: Shared constants

**Example from plugin.py:**
```python
from .oauth2 import *
import ckanext.oauth2.db as db
from ckanext.oauth2.views import get_blueprints
from ckanext.oauth2.cli import get_commands

class OAuth2Plugin(_OAuth2Plugin, plugins.SingletonPlugin):
    plugins.implements(plugins.IAuthenticator, inherit=True)
    plugins.implements(plugins.IAuthFunctions, inherit=True)
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.ITemplateHelpers)
```

## Configuration Handling

**Pattern:**
- Configuration loaded from `config` dict passed to `update_config()` method
- Environment variables take precedence: `os.environ.get('CKAN_OAUTH2_*', config.get('ckan.oauth2.*'))`
- All config keys normalized to lowercase strings with type conversion
- Booleans converted from string: `str(...).lower() in ("true", "1", "on")`

**Example from oauth2.py:**
```python
self.jwt_enable = str(os.environ.get('CKAN_OAUTH2_JWT_ENABLE', cfg.get('ckan.oauth2.jwt.enable',''))).strip().lower() in ("true", "1", "on")
self.jwt_algorithm = str(os.environ.get('CKAN_OAUTH2_JWT_ALGORITHM', cfg.get('ckan.oauth2.jwt.algorithm', 'HS256'))).strip()
```

---

*Convention analysis: 2026-02-14*
