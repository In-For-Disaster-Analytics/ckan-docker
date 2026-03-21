# Integration Tests for X-Tapis-Token CKAN API Authentication

**Date:** 2026-03-21
**Branch:** fix/02--add-support-for-x-tapis-token-header-in-ckan-api

## Background

The `ckanext-oauth2` plugin already supports the `X-Tapis-Token` header as an authentication mechanism (alongside the standard `Authorization: Bearer` header). Unit tests covering the logic exist in `src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py`.

What is missing are integration tests that verify the end-to-end flow against the running production CKAN instance (`https://ckan.tacc.utexas.edu`), using real Tapis JWT tokens obtained from real credentials.

## Goal

Create integration tests that:

1. Obtain a real Tapis JWT using test user credentials from environment variables
2. Call CKAN API endpoints with `X-Tapis-Token` and `Authorization: Bearer` headers
3. Assert correct responses for valid, invalid, and missing tokens
4. Clean up any data created during tests

## File Structure

```
tests/integration/
  conftest.py              -- pytest fixtures
  test_api_auth.py         -- test cases
.env.integration.example   -- template for required environment variables
```

## Environment Variables

Tests rely on environment variables already being exported before `pytest` is invoked. The tests themselves do NOT call `load_dotenv()`. Callers are responsible for exporting variables (e.g., via `source .env.integration`).

Template at `.env.integration.example`:

```
TACC_USERNAME=...
TACC_PASSWORD=...
TAPIS_BASE_URL=https://portals.tapis.io
CKAN_SITE_URL=https://ckan.tacc.utexas.edu
TEST_ORG_NAME=...   # CKAN org the test user belongs to (user must have editor or admin role)
```

## conftest.py

Three session-scoped fixtures:

- `ckan_url` — reads `CKAN_SITE_URL` from environment; skips session with a clear message if missing
- `jwt_token` — calls `POST {TAPIS_BASE_URL}/v3/oauth2/tokens` with `TACC_USERNAME` and `TACC_PASSWORD`; extracts the JWT from `.result.access_token.access_token` in the response JSON; skips session with a clear message if credentials are missing or the token request fails
- `authed_session` — a `requests.Session` with `X-Tapis-Token: <jwt>` pre-set as a default header

## Test Cases

### `test_api_auth.py`

| Test | Method | Endpoint | Auth | Expected |
|------|--------|----------|------|----------|
| `test_x_tapis_token_organization_list` | GET | `organization_list_for_user` | `X-Tapis-Token` | 200, `success: true` |
| `test_bearer_token_organization_list` | GET | `organization_list_for_user` | `Authorization: Bearer` | 200, `success: true` |
| `test_x_tapis_token_package_create` | POST | `package_create` | `X-Tapis-Token` | 200, `success: true`; cleanup on teardown |
| `test_no_token_organization_list_is_anonymous` | GET | `organization_list_for_user` | none | 200, `success: true`, empty result list |
| `test_invalid_token_returns_401_or_error` | GET | `organization_list_for_user` | `X-Tapis-Token: garbage` | HTTP 401 OR HTTP 200 with `success: false` |

**Note on `test_no_token_organization_list_is_anonymous`:** unauthenticated calls to `organization_list_for_user` return 200 with an empty list on this CKAN instance (anonymous access is permitted but shows no orgs).

**Note on `test_invalid_token_returns_401_or_error`:** CKAN's `toolkit.abort(401)` may be caught by CKAN middleware and returned as a 200 with `{"success": false}` depending on middleware configuration. The test asserts that either the HTTP status is 401 OR the response body has `success: false` — both indicate the request was correctly rejected.

### Cleanup for `test_x_tapis_token_package_create`

- Dataset name must include a `uuid.uuid4()` suffix to avoid name conflicts across runs (e.g., `test-dataset-<uuid>`)
- On teardown (whether test passes or fails), call `package_purge` — not `package_delete`, which only soft-deletes and would cause name conflicts on subsequent runs

### Prerequisite for `test_x_tapis_token_package_create`

- `TEST_ORG_NAME` must name an org in which the test user has **editor or admin** role (member role is insufficient for `package_create`)
- The org must already exist; the tests do not create it

## Running the Tests

```bash
# First time setup
cp .env.integration.example .env.integration
# Fill in TACC_USERNAME, TACC_PASSWORD, TEST_ORG_NAME

# Run
source .env.integration
pytest tests/integration/ -v

# Or inline
TACC_USERNAME=myuser TACC_PASSWORD=mypass TEST_ORG_NAME=myorg \
  TAPIS_BASE_URL=https://portals.tapis.io \
  CKAN_SITE_URL=https://ckan.tacc.utexas.edu \
  pytest tests/integration/ -v
```

## Dependencies

- `pytest` (already used in the project)
- `requests` (already used in `ckanext-oauth2`)

No `python-dotenv` dependency. No local CKAN instance required. No `CKAN_INI` needed. Tests are pure HTTP client tests.

## Out of Scope

- Testing header priority (both `Authorization: Bearer` and `X-Tapis-Token` present) — covered by unit tests in `test_plugin.py`
- Testing CKAN authorization rules (who can create in which org)
- Testing token refresh behavior (covered by unit tests)
- Testing the browser-based OAuth2 flow
