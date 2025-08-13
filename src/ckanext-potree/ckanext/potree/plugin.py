import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit
from ckan.common import config
from ckanext.potree import viewer, helpers

class PotreePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.IBlueprint)
    plugins.implements(plugins.ITemplateHelpers)

    # IConfigurer
    def update_config(self, config_):
        toolkit.add_template_directory(config_, 'templates')
        toolkit.add_public_directory(config_, 'public')
        toolkit.add_resource('public', 'potree')

    # IBlueprint
    def get_blueprint(self):
        return viewer.get_blueprints()

    # ITemplateHelpers
    def get_helpers(self):
        return {
            'is_potree_resource': helpers.is_potree_resource,
            'can_view_potree': helpers.can_view_potree
        }