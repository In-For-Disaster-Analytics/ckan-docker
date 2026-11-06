import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit

from typing import (
    Any, Callable, Match, NoReturn, cast, Dict,
    Iterable, Optional, TypeVar, Union)
from markupsafe import Markup, escape
from markdown import markdown
import re


class TaccThemePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.ITemplateHelpers)

    # IConfigurer

    def update_config(self, config_):
        toolkit.add_template_directory(config_, 'templates')
        toolkit.add_public_directory(config_, 'public')
        toolkit.add_resource('assets', 'tacc_theme')

    # ITemplateHelpers

    def get_helpers(self):
        return {
            'get_dynamo_dashboard_url': self.get_dynamo_dashboard_url,
            'get_ensemble_manager_api_url': self.get_ensemble_manager_api_url,
            'safe_oauth2_get_stored_token': self.safe_oauth2_get_stored_token,
            'get_child_organizations': self.get_child_organizations,
        }

    def get_dynamo_dashboard_url(self):
        """Get the DYNAMO Dashboard URL from CKAN configuration"""
        return toolkit.config.get('ckanext.tacc_theme.dynamo_dashboard_url', 'https://mint.tacc.utexas.edu')

    def get_ensemble_manager_api_url(self):
        """Get the Ensemble Manager API URL from CKAN configuration"""
        return toolkit.config.get('ckanext.tacc_theme.ensemble_manager_api_url', 'https://ensemble-manager.mint.tacc.utexas.edu/v1')

    def safe_oauth2_get_stored_token(self):
        """Safely get OAuth2 stored token, returning None if OAuth2 is disabled or helper not available"""
        try:
            # Try to get the OAuth2 helper function
            oauth2_helper = toolkit.h.oauth2_get_stored_token
            return oauth2_helper()
        except (AttributeError, Exception):
            # OAuth2 extension is not available or helper is not defined
            return None

    def get_child_organizations(self, group_id):
        """Direct sub-organizations of an organization, ordered by name.

        Used for the card grid on an organization's page. Each item is an
        organization_show dict (image, description, dataset count), so it can be
        rendered with the same card markup as the organization index. Returns []
        when ckanext-hierarchy is not enabled or the organization has no children.
        """
        if not plugins.plugin_loaded('hierarchy_display'):
            return []
        try:
            section = toolkit.get_action('group_tree_section')(
                {'include_parents': False, 'include_siblings': False},
                {'id': group_id, 'type': 'organization'})
        except (toolkit.ObjectNotFound, toolkit.ValidationError):
            return []
        children = []
        for node in section.get('children', []):
            try:
                children.append(toolkit.get_action('organization_show')({}, {
                    'id': node['id'],
                    'include_datasets': False,
                    'include_dataset_count': True,
                    'include_users': False,
                    'include_followers': False,
                    'include_extras': False,
                    'include_groups': False,
                    'include_tags': False,
                }))
            except (toolkit.ObjectNotFound, toolkit.NotAuthorized):
                continue
        return sorted(children, key=lambda o: (o.get('display_name') or o['name']).lower())

    def markdown_extract_paragraphs(text: str, extract_length: int = 190) -> Union[str, Markup]:
        ''' return the plain text representation of markdown (ie: text without any html tags)
        as a list of paragraph strings.'''
        if not text:
            return ''

        # find all tags but ignore < in the strings so that we can use it correctly
        # in markdown
        RE_MD_HTML_TAGS = re.compile('<[^><]*>')
        plain = RE_MD_HTML_TAGS.sub('', markdown(text))
        return plain.splitlines()
