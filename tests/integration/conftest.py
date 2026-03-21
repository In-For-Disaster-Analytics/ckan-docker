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
