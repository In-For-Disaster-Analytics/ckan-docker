"""
Tests for plugin.py.

Tests are written using the pytest library (https://docs.pytest.org), and you
should read the testing guidelines in the CKAN docs:
https://docs.ckan.org/en/2.9/contributing/testing.html

To write tests for your extension you should install the pytest-ckan package:

    pip install pytest-ckan

This will allow you to use CKAN specific fixtures on your tests.

For instance, if your test involves database access you can use `clean_db` to
reset the database:

    import pytest

    from ckan.tests import factories

    @pytest.mark.usefixtures("clean_db")
    def test_some_action():

        dataset = factories.Dataset()

        # ...

For functional tests that involve requests to the application, you can use the
`app` fixture:

    from ckan.plugins import toolkit

    def test_some_endpoint(app):

        url = toolkit.url_for('myblueprint.some_endpoint')

        response = app.get(url)

        assert response.status_code == 200


To temporary patch the CKAN configuration for the duration of a test you can use:

    import pytest

    @pytest.mark.ckan_config("ckanext.myext.some_key", "some_value")
    def test_some_action():
        pass
"""
import pytest
from unittest.mock import patch, Mock
import ckanext.tacc_theme.plugin as plugin


def test_plugin():
    pass


class TestTaccThemePlugin:
    """Test class for TaccThemePlugin"""

    def setup_method(self):
        """Set up test fixtures"""
        self.plugin = plugin.TaccThemePlugin()

    def test_safe_oauth2_get_stored_token_when_oauth2_available(self):
        """Test safe_oauth2_get_stored_token when OAuth2 helper is available"""
        mock_token = Mock()
        mock_token.access_token = "test_token_123"
        
        with patch('ckan.plugins.toolkit.h.oauth2_get_stored_token', return_value=mock_token):
            result = self.plugin.safe_oauth2_get_stored_token()
            assert result == mock_token

    def test_safe_oauth2_get_stored_token_when_oauth2_unavailable(self):
        """Test safe_oauth2_get_stored_token when OAuth2 helper is not available (AttributeError)"""
        with patch('ckan.plugins.toolkit.h', spec=[]):  # h object without oauth2_get_stored_token attribute
            result = self.plugin.safe_oauth2_get_stored_token()
            assert result is None

    def test_safe_oauth2_get_stored_token_when_oauth2_raises_exception(self):
        """Test safe_oauth2_get_stored_token when OAuth2 helper raises an exception"""
        with patch('ckan.plugins.toolkit.h.oauth2_get_stored_token', side_effect=Exception("OAuth2 error")):
            result = self.plugin.safe_oauth2_get_stored_token()
            assert result is None

    def test_get_helpers_includes_safe_oauth2_helper(self):
        """Test that get_helpers includes the safe_oauth2_get_stored_token helper"""
        helpers = self.plugin.get_helpers()
        assert 'safe_oauth2_get_stored_token' in helpers
        assert helpers['safe_oauth2_get_stored_token'] == self.plugin.safe_oauth2_get_stored_token
