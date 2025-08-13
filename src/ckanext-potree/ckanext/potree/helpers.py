# ckanext/potree/helpers.py
import ckan.plugins.toolkit as toolkit

def is_potree_resource(resource):
    """Check if a resource is a Potree scene file"""
    if not resource:
        return False

    format_name = resource.get('format', '').lower()
    return format_name in ['potree-workspace', 'potree-scene', 'potree']

def can_view_potree(resource_id):
    """Check if current user can view Potree scene"""
    try:
        toolkit.check_access('resource_show', {}, {'id': resource_id})
        return True
    except toolkit.NotAuthorized:
        return False