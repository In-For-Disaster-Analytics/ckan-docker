import os
import uuid
import pytest
import requests

# Run only with: pytest tests/integration/ -v
# Requires: CKAN_SITE_URL, TACC_USERNAME, TACC_PASSWORD, TEST_ORG_NAME env vars
# These tests hit the live production server and must NOT run in CI without credentials.


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
        assert len(data["result"]) > 0, "Authenticated user should belong to at least one org"

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
        assert len(data["result"]) > 0, "Authenticated user should belong to at least one org"

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
            # Soft-delete the dataset. UUID naming ensures no name conflicts on reruns.
            purge_resp = authed_session.post(
                _api(ckan_url, "package_delete"),
                json={"id": dataset_name},
            )
            if not purge_resp.ok or not purge_resp.json().get("success"):
                import warnings
                warnings.warn(f"Cleanup failed for dataset {dataset_name}: {purge_resp.text}")

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
