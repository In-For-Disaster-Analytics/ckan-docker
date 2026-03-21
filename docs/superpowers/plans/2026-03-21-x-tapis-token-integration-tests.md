# X-Tapis-Token Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create integration tests that verify the CKAN API accepts `X-Tapis-Token` and `Authorization: Bearer` headers end-to-end against the live production server (`https://ckan.tacc.utexas.edu`).

**Architecture:** Pure HTTP client tests using `pytest` and `requests`. A session-scoped fixture obtains a real Tapis JWT from the token endpoint, then tests call CKAN API endpoints directly. No local CKAN stack is needed.

**Tech Stack:** Python, pytest, requests

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `tests/__init__.py` | Create | Makes `tests/` a package |
| `tests/integration/__init__.py` | Create | Makes `tests/integration/` a package |
| `tests/integration/conftest.py` | Create | Session-scoped fixtures: `ckan_url`, `jwt_token`, `authed_session` |
| `tests/integration/test_api_auth.py` | Create | Five test cases covering valid/invalid/missing token scenarios |
| `.env.integration.example` | Create | Template of required environment variables |

---

## Task 1: Create directory structure and env template

**Files:**
- Create: `tests/__init__.py`
- Create: `tests/integration/__init__.py`
- Create: `.env.integration.example`

- [ ] **Step 1: Create package init files**

```bash
mkdir -p tests/integration
touch tests/__init__.py
touch tests/integration/__init__.py
```

- [ ] **Step 2: Create `.env.integration.example`**

Create `.env.integration.example` at the repo root with this exact content:

```bash
# Integration test credentials - copy to .env.integration and fill in values
# DO NOT commit .env.integration

TACC_USERNAME=your_tacc_username
TACC_PASSWORD=your_tacc_password
TAPIS_BASE_URL=https://portals.tapis.io
CKAN_SITE_URL=https://ckan.tacc.utexas.edu
TEST_ORG_NAME=your_org_name  # org where test user has editor or admin role
```

- [ ] **Step 3: Verify `.env.integration` is gitignored**

Check `.gitignore` contains `.env.integration`. If not, add it:

```bash
grep '.env.integration' .gitignore || echo '.env.integration' >> .gitignore
```

- [ ] **Step 4: Commit**

```bash
git add tests/__init__.py tests/integration/__init__.py .env.integration.example .gitignore
git commit -m "chore: scaffold integration test directory and env template"
```

---

## Task 2: Write fixtures in conftest.py

**Files:**
- Create: `tests/integration/conftest.py`

- [ ] **Step 1: Write `conftest.py`**

Create `tests/integration/conftest.py` with the following content:

```python
import os
import pytest
import requests


@pytest.fixture(scope="session")
def ckan_url():
    url = os.environ.get("CKAN_SITE_URL")
    if not url:
        pytest.skip("CKAN_SITE_URL not set — export it before running integration tests")
    return url.rstrip("/")


@pytest.fixture(scope="session")
def jwt_token():
    username = os.environ.get("TACC_USERNAME")
    password = os.environ.get("TACC_PASSWORD")
    base_url = os.environ.get("TAPIS_BASE_URL", "https://portals.tapis.io")

    if not username or not password:
        pytest.skip("TACC_USERNAME and TACC_PASSWORD must be set to run integration tests")

    resp = requests.post(
        f"{base_url}/v3/oauth2/tokens",
        headers={"Content-Type": "application/json"},
        json={"username": username, "password": password, "grant_type": "password"},
        timeout=30,
    )
    if not resp.ok:
        pytest.skip(f"Failed to obtain Tapis JWT: {resp.status_code} {resp.text}")

    token = resp.json().get("result", {}).get("access_token", {}).get("access_token")
    if not token:
        pytest.skip(f"Unexpected Tapis token response structure: {resp.json()}")

    return token


@pytest.fixture(scope="session")
def authed_session(jwt_token):
    session = requests.Session()
    session.headers.update({"X-Tapis-Token": jwt_token})
    return session
```

- [ ] **Step 2: Commit**

```bash
git add tests/integration/conftest.py
git commit -m "test(integration): add session fixtures for Tapis JWT and authed session"
```

---

## Task 3: Write failing test stubs

**Files:**
- Create: `tests/integration/test_api_auth.py`

- [ ] **Step 1: Write test stubs (all failing/xfail)**

Create `tests/integration/test_api_auth.py`:

```python
import os
import uuid
import pytest
import requests


def _api(ckan_url, action):
    return f"{ckan_url}/api/3/action/{action}"


class TestXTapisTokenAuth:

    def test_x_tapis_token_organization_list(self, authed_session, ckan_url):
        """X-Tapis-Token header authenticates user and returns their orgs."""
        resp = authed_session.get(
            _api(ckan_url, "organization_list_for_user"),
            params={"all_fields": "true"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True

    def test_bearer_token_organization_list(self, jwt_token, ckan_url):
        """Authorization: Bearer header authenticates user and returns their orgs."""
        resp = requests.get(
            _api(ckan_url, "organization_list_for_user"),
            headers={"Authorization": f"Bearer {jwt_token}"},
            params={"all_fields": "true"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True

    def test_x_tapis_token_package_create(self, authed_session, ckan_url):
        """X-Tapis-Token header allows creating a dataset; dataset is purged on teardown."""
        org_name = os.environ.get("TEST_ORG_NAME")
        if not org_name:
            pytest.skip("TEST_ORG_NAME not set")

        dataset_name = f"test-integration-{uuid.uuid4().hex[:8]}"

        try:
            resp = authed_session.post(
                _api(ckan_url, "package_create"),
                json={
                    "name": dataset_name,
                    "owner_org": org_name,
                    "title": "Integration test dataset",
                },
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["success"] is True
            assert data["result"]["name"] == dataset_name
        finally:
            # Always purge, even if create failed partially
            authed_session.post(
                _api(ckan_url, "dataset_purge"),
                json={"id": dataset_name},
            )

    def test_no_token_organization_list_is_anonymous(self, ckan_url):
        """Without a token, organization_list_for_user returns 200 with empty list."""
        resp = requests.get(
            _api(ckan_url, "organization_list_for_user"),
            params={"all_fields": "true"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["result"] == []

    def test_invalid_token_returns_401_or_error(self, ckan_url):
        """A garbage X-Tapis-Token is rejected: either HTTP 401 or success:false."""
        resp = requests.get(
            _api(ckan_url, "organization_list_for_user"),
            headers={"X-Tapis-Token": "this-is-not-a-valid-token"},
        )
        # CKAN may return HTTP 401 directly, or wrap the error as 200+success:false
        if resp.status_code == 200:
            assert resp.json()["success"] is False, (
                f"Expected success:false for invalid token, got: {resp.json()}"
            )
        else:
            assert resp.status_code == 401, (
                f"Expected 401 for invalid token, got: {resp.status_code}"
            )
```

- [ ] **Step 2: Verify tests are collected (no import errors)**

```bash
pytest tests/integration/ --collect-only
```

Expected output: 5 tests collected with no import errors.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_api_auth.py
git commit -m "test(integration): add X-Tapis-Token API auth integration tests"
```

---

## Task 4: Run the tests against production

**Prerequisites before running:**
- Copy `.env.integration.example` to `.env.integration`
- Fill in `TACC_USERNAME`, `TACC_PASSWORD`, `TEST_ORG_NAME`
- Confirm the test user has **editor or admin** role in `TEST_ORG_NAME`

- [ ] **Step 1: Export credentials and run**

```bash
source .env.integration
pytest tests/integration/ -v
```

Expected output: all 5 tests pass.

- [ ] **Step 2: Verify cleanup worked**

After the test run, confirm no test datasets remain:

```bash
curl -s "${CKAN_SITE_URL}/api/3/action/package_search?q=test-integration-" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['count'])"
```

Expected: `0`

- [ ] **Step 3: If any test fails, diagnose before fixing**

Common failures:
- `test_x_tapis_token_package_create` fails with "Not authorized" → test user lacks editor role in `TEST_ORG_NAME`
- `test_invalid_token_returns_401_or_error` fails → check what status code and body CKAN actually returns; update assertion if needed
- All tests skip → credentials not exported; run `source .env.integration` first

---

## Task 5: Verify gitignore and final commit

- [ ] **Step 1: Confirm `.env.integration` is not tracked**

```bash
git status .env.integration
```

Expected: either "nothing to commit" (file doesn't exist) or shown as untracked (not staged).

- [ ] **Step 2: Final commit if anything remains unstaged**

```bash
git add -p  # review any remaining changes
git commit -m "test(integration): finalize X-Tapis-Token integration tests"
```
