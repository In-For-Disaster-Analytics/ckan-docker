# Testing Patterns

**Analysis Date:** 2026-02-14

## Test Framework

**Runner:**
- pytest 8.4.2+
- Config: `pytest.ini` in extension root (`src/ckanext-oauth2/pytest.ini`)

**Assertion Library:**
- pytest built-in assertions via `assert` statements
- Context managers: `pytest.raises()` for exception testing

**Run Commands:**

```bash
# From extension root (src/ckanext-oauth2/)
# All tests
CKAN_INI=test.ini uv run pytest

# Verbose output
CKAN_INI=test.ini uv run pytest -v

# With coverage
CKAN_INI=test.ini uv run pytest --cov=ckanext.oauth2

# Specific test file
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py

# Specific test class
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin

# Specific test method
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_method_name -v
```

**Configuration Details:**
- `pytest.ini` adds `--ckan-ini test.ini` automatically
- Sets `testpaths = ckanext/oauth2/tests`
- Python naming conventions: `python_files = test_*.py`, `python_functions = test_*`, `python_classes = Test*`
- Warnings filtered: `ignore::UserWarning`, `ignore::DeprecationWarning`
- Markers defined: `ckan_config` for tests requiring CKAN configuration

## Test File Organization

**Location:**
- Co-located with source code: `ckanext/oauth2/tests/` parallel to `ckanext/oauth2/`
- Each module has corresponding test file

**Naming:**
- Files: `test_*.py` (test_oauth2.py, test_db.py, test_plugin.py, test_jwt_rs256.py)
- Classes: `Test*` (TestOAuth2Plugin, TestDB)
- Methods: `test_*` (test_minimum_conf, test_get_token, test_identify_user_exists_no_sysadmin)

**Structure:**
```
src/ckanext-oauth2/
├── ckanext/
│   └── oauth2/
│       ├── oauth2.py
│       ├── plugin.py
│       ├── db.py
│       ├── views.py
│       └── tests/
│           ├── __init__.py
│           ├── test_oauth2.py
│           ├── test_db.py
│           ├── test_plugin.py
│           ├── test_jwt_rs256.py
│           └── test_controller.py
└── pytest.ini
```

## Test Structure

**Suite Organization:**
```python
# test_oauth2.py pattern
@pytest.fixture
def oauth2_setup():
    """Set up shared test data and mocks"""
    user_field = 'nickName'
    fullname_field = 'fullname'
    email_field = 'mail'
    profile_api_url = 'https://test/oauth2/user'
    group_field = 'groups'

    # Store originals for cleanup
    original_toolkit = oauth2.toolkit
    original_User = oauth2.model.User

    # Mock critical dependencies
    oauth2.toolkit = MagicMock()

    yield {
        'user_field': user_field,
        'fullname_field': fullname_field,
        'email_field': email_field,
        'profile_api_url': profile_api_url,
        'group_field': group_field
    }

    # Cleanup - restore originals
    oauth2.toolkit = original_toolkit
    oauth2.model.User = original_User


class TestOAuth2Plugin:
    """Test class for OAuth2Plugin"""

    def _helper(self, oauth2_setup, fullname_field=True, mail_field=True, conf=None, missing_conf=None, jwt_enable=False):
        """Setup helper creates configured OAuth2Helper with test config"""
        oauth2.db = MagicMock()
        oauth2.jwt = MagicMock()

        oauth2.toolkit.config = {
            'ckan.oauth2.legacy_idm': 'false',
            'ckan.oauth2.authorization_endpoint': 'https://test/oauth2/authorize/',
            'ckan.oauth2.token_endpoint': 'https://test/oauth2/token/',
            'ckan.oauth2.client_id': 'client-id',
            'ckan.oauth2.client_secret': 'client-secret',
            'ckan.oauth2.profile_api_url': oauth2_setup['profile_api_url'],
            'ckan.oauth2.profile_api_user_field': oauth2_setup['user_field'],
            'ckan.oauth2.profile_api_mail_field': oauth2_setup['email_field'],
        }
        if conf is not None:
            oauth2.toolkit.config.update(conf)
        if missing_conf is not None:
            del oauth2.toolkit.config[missing_conf]

        helper = OAuth2Helper(oauth2.toolkit.config)

        if fullname_field:
            helper.profile_api_fullname_field = oauth2_setup['fullname_field']

        if jwt_enable:
            helper.jwt_enable = True
            helper.jwt_algorithm = 'HS256'
            helper.jwt_secret = 'test-secret'

        return helper
```

**Patterns:**
- Setup: Fixture provides shared config and mocks via `@pytest.fixture`
- Helper methods: `_helper()` creates configured test instances
- Teardown: Fixtures cleanup mocks in yield cleanup block
- Parameterization: `@pytest.mark.parametrize()` tests multiple input combinations

## Mocking

**Framework:** `unittest.mock` (Python standard library)

**Patterns:**
```python
# Import mocking utilities
from unittest.mock import patch, MagicMock, Mock

# Mock with decorator
@patch('ckanext.oauth2.oauth2.OAuth2Session')
def test_get_token(self, OAuth2Session, oauth2_setup):
    OAuth2Session().fetch_token.return_value = OAUTH2TOKEN
    # Test code

# Mock with context manager
with patch('ckanext.oauth2.oauth2.OAuth2Session') as oauth2_session_mock:
    oauth2_session_mock().fetch_token.side_effect = MissingCodeError("Missing code")

# Mock environment variables
@patch.dict(os.environ, {'OAUTHLIB_INSECURE_TRANSPORT': ''})
def test_get_token_insecure(self, oauth2_setup):
    # Test code

# Mock objects in fixture
oauth2.toolkit = MagicMock()
oauth2.model.User = MagicMock()
oauth2.db = MagicMock()
```

**What to Mock:**
- CKAN framework objects: `toolkit`, `model.User`, `model.Session`
- External libraries: `OAuth2Session`, `jwt`, `requests`
- Database models: `db.UserToken`, database session
- Environment-specific behavior: HTTP requests, file I/O

**What NOT to Mock:**
- Configuration dictionaries that should be validated
- Helper methods within the class being tested (use real implementations)
- Return values from mocked methods unless testing the mock behavior itself
- CKAN constants and utility functions

**Example from test_oauth2.py:**
```python
def test_get_token(self, OAuth2Session, oauth2_setup):
    helper = self._helper(oauth2_setup)
    token = OAUTH2TOKEN
    OAuth2Session().fetch_token.return_value = OAUTH2TOKEN

    state = b64encode(json.dumps({'came_from': 'initial-page'}).encode('utf-8'))
    oauth2.toolkit.request = make_request(True, 'data.com', 'callback',
                                         {'state': state, 'code': 'code'})
    retrieved_token = helper.get_token()

    for key, value in token.items():
        assert key in retrieved_token
        assert value == retrieved_token[key]
```

## Fixtures and Factories

**Test Data:**
```python
# Constants used across tests
OAUTH2TOKEN = {
    'access_token': 'token',
    'token_type': 'Bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh_token',
}

# Request factory for simulating Flask requests
def make_request(secure, host, path, params):
    request = MagicMock()
    params_str = '&'.join(f'{k}={v}' for k, v in params.items())
    secure_str = 's' if secure else ''
    request.url = f'http{secure_str}://{host}/{path}?{params_str}'
    request.host = host
    request.host_url = f'http{secure_str}://{host}'
    request.params = params
    request.args = params
    return request
```

**Location:**
- Constants defined at module level in test file
- Helper functions defined before test classes
- Fixtures defined with `@pytest.fixture` decorator
- Fixture scope: function-level (default) with manual cleanup in fixture

## Coverage

**Requirements:** Not explicitly enforced in pytest.ini

**View Coverage:**
```bash
CKAN_INI=test.ini uv run pytest --cov=ckanext.oauth2 --cov-report=html
```

## Test Types

**Unit Tests:**
- Scope: Individual methods and helper functions
- Approach: Mock external dependencies, test specific behavior
- Example: `test_get_token()` tests OAuth2 token retrieval with mocked OAuth2Session
- Files: `test_oauth2.py`, `test_db.py` contain most unit tests

**Integration Tests:**
- Scope: Multiple components working together
- Approach: Mock framework but test real logic
- Example: `test_identify_user_exists_no_sysadmin()` tests user lookup + profile processing
- Use CKAN test fixtures: fixtures not heavily used in this codebase

**E2E Tests:**
- Framework: httpretty for HTTP mocking
- Usage: `@httpretty.activate` decorator enables HTTP request interception
- Example from test_oauth2.py:
```python
@httpretty.activate
@patch.dict(os.environ, {'OAUTHLIB_INSECURE_TRANSPORT': ''})
def test_get_token_insecure(self, oauth2_setup):
    # Register HTTP endpoints with httpretty
    # Test actual HTTP call behavior
```

## Common Patterns

**Async Testing:**
- Not applicable; CKAN extensions are synchronous

**Error Testing:**
```python
# Using pytest.raises context manager
@pytest.mark.parametrize("conf_to_remove", [
    "ckan.oauth2.authorization_endpoint",
    "ckan.oauth2.token_endpoint",
    "ckan.oauth2.client_id",
    "ckan.oauth2.client_secret",
    "ckan.oauth2.profile_api_url",
    "ckan.oauth2.profile_api_user_field",
    "ckan.oauth2.profile_api_mail_field",
])
def test_minimum_conf(self, oauth2_setup, conf_to_remove):
    with pytest.raises(ValueError):
        self._helper(oauth2_setup, missing_conf=conf_to_remove)

# Testing specific exception types
def test_identify_jwt_username_only_profile_fails(self, oauth2_setup):
    # ... setup ...
    exception_risen = False
    try:
        # Code that should raise
        helper.identify(token)
    except Exception as e:
        if isinstance(e, ValueError):
            assert 'expected message' in str(e)
        exception_risen = True

    assert exception_risen
```

**Parameterized Testing:**
```python
# Multiple test cases with different inputs
@pytest.mark.parametrize("username,fullname,email,fullname_field", [
    ('user1', 'User One', 'user1@example.com', True),
    ('user2', 'User Two', 'user2@example.com', False),
    ('user3', None, 'user3@example.com', True),
])
def test_identify_user_exists_no_sysadmin(self, oauth2_setup, username, fullname, email, fullname_field):
    # Test with each combination
    pass

# Boolean parameter variation
@pytest.mark.parametrize("sysadmin", [True, False])
def test_identify_user_exists_with_sysadmin(self, oauth2_setup, sysadmin):
    # Test sysadmin=True and sysadmin=False
    pass
```

## Development Dependencies

**Required for testing** (from `pyproject.toml` dev dependencies):
- `httpretty>=1.1.4` - HTTP request mocking
- `parameterized>=0.9.0` - Parameterized testing support
- `pytest>=8.4.2` - Test framework
- `pytest-factoryboy>=2.8.1` - Factory fixture support

## Test Command Examples

**From CLAUDE.md:**
```bash
# Run all tests
cd src/ckanext-oauth2
CKAN_INI=test.ini uv run pytest

# Run all tests with verbose output
CKAN_INI=test.ini uv run pytest -v

# Run tests with coverage
CKAN_INI=test.ini uv run pytest --cov=ckanext.oauth2

# Run a specific test file
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py

# Run a specific test class
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin

# Run a specific test method
CKAN_INI=test.ini uv run pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_method_name -v
```

**Key requirement:** `CKAN_INI=test.ini` environment variable must be set for CKAN's internal configuration loading, even though `pytest.ini` already references it.

---

*Testing analysis: 2026-02-14*
