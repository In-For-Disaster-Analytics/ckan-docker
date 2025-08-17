import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit
from ckan.common import config
from ckanext.potree import views, helpers

class PotreePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.IBlueprint)
    plugins.implements(plugins.ITemplateHelpers)
    plugins.implements(plugins.IResourceView)

    # IConfigurer
    def update_config(self, config_):
        toolkit.add_template_directory(config_, 'templates')
        toolkit.add_public_directory(config_, 'public')

    # IBlueprint
    def get_blueprint(self):
        return views.get_blueprints()

    # ITemplateHelpers
    def get_helpers(self):
        return {
            'is_potree_resource': helpers.is_potree_resource,
            'can_view_potree': helpers.can_view_potree
        }

    # IResourceView
    def info(self):
        """Return information about this resource view."""
        return {
            'name': 'potree_scene',
            'title': 'Potree 3D Scene',
            'icon': 'cube',
            'iframed': False,
            'default_title': 'Potree Scene Viewer',
            'always_available': False,
            'schema': {},
        }

    def can_view(self, data_dict):
        """Determine if this view can display the resource."""
        resource = data_dict['resource']
        return self._is_potree_scene_file(resource)

    def view_template(self, context, data_dict):
        """Return the template to render for this view."""
        return 'potree/index.html'

    def setup_template_variables(self, context, data_dict):
        """Setup variables available to the template."""
        resource = data_dict['resource']
        resource_view = data_dict.get('resource_view', {})
        
        return {
            'resource': resource,
            'resource_view': resource_view,
            'resource_url': resource.get('url', ''),
            'viewer_url': toolkit.url_for('potree.scene_viewer', resource_id=resource['id']),
        }

    def _is_potree_scene_file(self, resource):
        """
        Check if a resource is a Potree scene file based on multiple criteria.
        
        This method checks:
        1. File extension (.json5)
        2. Format field (potree-scene, potree, json5)
        3. Filename patterns (scene.json5, potree.json5)
        """
        if not resource:
            return False

        # Check format field
        format_name = resource.get('format', '').lower()
        if format_name in ['potree-scene', 'potree', 'json5']:
            return True

        # Check file extension from URL
        url = resource.get('url', '').lower()
        if url.endswith('.json5'):
            return True

        # Check filename patterns
        name = resource.get('name', '').lower()
        if any(pattern in name for pattern in ['scene.json5', 'potree.json5', 'workspace.json5']):
            return True

        # Check if it's a JSON file with Potree-related name
        if name.endswith('.json') and any(keyword in name for keyword in ['scene', 'potree', 'workspace']):
            return True

        return False