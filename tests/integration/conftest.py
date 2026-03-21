import os
from pathlib import Path
import pytest
import requests

# Auto-load .env.integration from repo root if it exists.
# Variables already in the environment take precedence (os.environ.setdefault).
_env_file = Path(__file__).parent.parent.parent / ".env.integration"
if _env_file.exists():
    with open(_env_file) as _f:
        for _line in _f:
            _line = _line.strip()
            if _line and not _line.startswith("#"):
                _key, _, _val = _line.partition("=")
                _key = _key.removeprefix("export").strip()
                os.environ.setdefault(_key, _val.strip())


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
    yield session
    session.close()


@pytest.fixture(scope="session")
def bearer_session(jwt_token):
    session = requests.Session()
    session.headers.update({"Authorization": f"Bearer {jwt_token}"})
    yield session
    session.close()
