# ckanext/potree/helpers.py
import ckan.plugins.toolkit as toolkit

def is_potree_resource(resource):
    """Check if a resource is a Potree scene file"""
    if not resource:
        return False

    # Check format field
    format_name = resource.get('format', '').lower()
    if format_name in ['potree-scene', 'potree', 'json5', 'potree-workspace']:
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

def can_view_potree(resource_id):
    """Check if current user can view Potree scene"""
    try:
        toolkit.check_access('resource_show', {}, {'id': resource_id})
        return True
    except toolkit.NotAuthorized:
        return False