"""
Tests for the Potree plugin.
"""
import pytest
from unittest.mock import Mock, patch
import json

from ckan.tests import factories
import ckan.plugins.toolkit as toolkit

import ckanext.potree.plugin as plugin
import ckanext.potree.helpers as helpers
import ckanext.potree.viewer as viewer


class TestPotreePlugin:
    """Test the PotreePlugin class."""
    
    def test_plugin_implements_interfaces(self):
        """Test that plugin implements required interfaces."""
        p = plugin.PotreePlugin()
        assert hasattr(p, 'update_config')
        assert hasattr(p, 'get_blueprint')
        assert hasattr(p, 'get_helpers')
    
    def test_get_helpers_returns_expected_functions(self):
        """Test that get_helpers returns the expected helper functions."""
        p = plugin.PotreePlugin()
        helper_functions = p.get_helpers()
        
        assert 'is_potree_resource' in helper_functions
        assert 'can_view_potree' in helper_functions
        assert helper_functions['is_potree_resource'] == helpers.is_potree_resource
        assert helper_functions['can_view_potree'] == helpers.can_view_potree


class TestPotreeHelpers:
    """Test helper functions."""
    
    def test_is_potree_resource_with_potree_format(self):
        """Test resource detection with potree format."""
        resource = {'format': 'potree-workspace'}
        assert helpers.is_potree_resource(resource) is True
        
        resource = {'format': 'potree-scene'}
        assert helpers.is_potree_resource(resource) is True
        
        resource = {'format': 'potree'}
        assert helpers.is_potree_resource(resource) is True
    
    def test_is_potree_resource_with_json_extension(self):
        """Test resource detection with JSON file extension."""
        resource = {'name': 'scene.json', 'format': 'json'}
        assert helpers.is_potree_resource(resource) is True
    
    def test_is_potree_resource_negative_cases(self):
        """Test resource detection negative cases."""
        assert helpers.is_potree_resource(None) is False
        assert helpers.is_potree_resource({}) is False
        
        resource = {'format': 'csv'}
        assert helpers.is_potree_resource(resource) is False
        
        resource = {'name': 'data.csv', 'format': 'csv'}
        assert helpers.is_potree_resource(resource) is False
    
    @patch('ckan.plugins.toolkit.check_access')
    def test_can_view_potree_authorized(self, mock_check_access):
        """Test can_view_potree when user is authorized."""
        mock_check_access.return_value = True
        result = helpers.can_view_potree('test-resource-id')
        assert result is True
        mock_check_access.assert_called_once_with('resource_show', {}, {'id': 'test-resource-id'})
    
    @patch('ckan.plugins.toolkit.check_access')
    def test_can_view_potree_not_authorized(self, mock_check_access):
        """Test can_view_potree when user is not authorized."""
        mock_check_access.side_effect = toolkit.NotAuthorized()
        result = helpers.can_view_potree('test-resource-id')
        assert result is False


class TestPotreeViewer:
    """Test viewer functions."""
    
    def test_is_potree_scene_resource_by_format(self):
        """Test _is_potree_scene_resource with format detection."""
        resource = {'format': 'potree-workspace'}
        assert viewer._is_potree_scene_resource(resource) is True
        
        resource = {'format': 'potree-scene'}
        assert viewer._is_potree_scene_resource(resource) is True
    
    def test_is_potree_scene_resource_by_extension(self):
        """Test _is_potree_scene_resource with JSON extension."""
        resource = {'name': 'workspace.json'}
        assert viewer._is_potree_scene_resource(resource) is True
    
    def test_is_potree_scene_resource_negative(self):
        """Test _is_potree_scene_resource negative cases."""
        resource = {'format': 'csv', 'name': 'data.csv'}
        assert viewer._is_potree_scene_resource(resource) is False
    
    @patch('requests.get')
    def test_fetch_scene_data_success(self, mock_get):
        """Test successful scene data fetching."""
        mock_response = Mock()
        mock_response.json.return_value = {'type': 'Potree', 'version': '1.8'}
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        resource = {'url': 'http://example.com/scene.json', 'url_type': 'link'}
        result = viewer._fetch_scene_data(resource)
        
        assert result == {'type': 'Potree', 'version': '1.8'}
        mock_get.assert_called_once_with('http://example.com/scene.json', timeout=10)
    
    @patch('requests.get')
    def test_fetch_scene_data_invalid_json(self, mock_get):
        """Test scene data fetching with invalid JSON."""
        mock_response = Mock()
        mock_response.json.side_effect = json.JSONDecodeError('Invalid JSON', 'doc', 0)
        mock_response.raise_for_status.return_value = None
        mock_get.return_value = mock_response
        
        resource = {'url': 'http://example.com/scene.json', 'url_type': 'link'}
        result = viewer._fetch_scene_data(resource)
        
        assert result is None
    
    @patch('requests.get')
    def test_fetch_scene_data_request_error(self, mock_get):
        """Test scene data fetching with request error."""
        mock_get.side_effect = Exception('Connection error')
        
        resource = {'url': 'http://example.com/scene.json', 'url_type': 'link'}
        result = viewer._fetch_scene_data(resource)
        
        assert result is None


@pytest.mark.usefixtures("clean_db", "with_plugins")
@pytest.mark.ckan_config("ckan.plugins", "potree")
class TestPotreeViews:
    """Test the Potree viewer routes."""
    
    def test_scene_viewer_route_exists(self, app):
        """Test that the scene viewer route is properly registered."""
        with app.test_client() as client:
            url = toolkit.url_for('potree.scene_viewer', resource_id='test-id')
            assert '/dataset/potree/test-id' in url
