import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit
from ckan.common import config
from ckanext.potree import views, helpers

class PotreePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.IBlueprint)
    plugins.implements(plugins.ITemplateHelpers)
    plugins.implements(plugins.IResourceView)
    plugins.implements(plugins.IResourceController)

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
        """Check if a resource is a Potree scene file using shared detection logic."""
        return helpers._detect_potree_resource(resource)

    # IResourceController
    def before_create(self, context, resource):
        """Auto-detect and set format for Potree files before resource creation."""
        return self._auto_detect_potree_format(resource)

    def before_update(self, context, current, resource):
        """Auto-detect and set format for Potree files before resource update."""
        return self._auto_detect_potree_format(resource)

    def _auto_detect_potree_format(self, resource):
        """
        Automatically detect and set format for Potree scene files.
        
        This method is called before resource creation/update to ensure
        that .json5 files and other Potree-related files get the correct format.
        """
        if not resource:
            return resource

        current_format = resource.get('format', '').lower()

        # Only auto-detect if format is not already set to a Potree-specific format
        if current_format not in ['potree-scene', 'potree', 'json5', 'potree-workspace']:
            
            # Use our shared detection logic to check if this is a Potree resource
            if helpers._detect_potree_resource(resource):
                url = resource.get('url', '').lower()
                name = resource.get('name', '').lower()
                
                # Set appropriate format based on file characteristics
                if url.endswith('.json5') or name.endswith('.json5'):
                    resource['format'] = 'json5'
                elif any(keyword in name for keyword in ['scene', 'potree', 'workspace']):
                    resource['format'] = 'potree-scene'
                else:
                    resource['format'] = 'potree'

        return resource