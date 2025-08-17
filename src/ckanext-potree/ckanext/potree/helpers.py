# ckanext/potree/helpers.py
import ckan.plugins.toolkit as toolkit

def is_potree_resource(resource):
    """Check if a resource is a Potree scene file"""
    return _detect_potree_resource(resource)

def _detect_potree_resource(resource):
    """
    Shared detection logic for Potree scene files.
    
    Checks multiple criteria:
    1. Format field (potree-scene, potree, json5, potree-workspace)
    2. File extension (.json5)
    3. Filename patterns (scene.json5, potree.json5, workspace.json5)
    4. JSON files with Potree keywords (scene, potree, workspace)
    5. Fallback for unknown format with .json5 extension
    """
    if not resource:
        return False

    # Get resource properties
    format_name = resource.get('format', '').lower()
    url = resource.get('url', '').lower()
    name = resource.get('name', '').lower()

    # Check format field
    if format_name in ['potree-scene', 'potree', 'json5', 'potree-workspace']:
        return True
    
    # Handle "unknown" format with JSON5 extension (fallback case)
    if format_name in ['unknown', ''] and (url.endswith('.json5') or name.endswith('.json5')):
        return True

    # Check file extension from URL
    if url.endswith('.json5'):
        return True

    # Check filename patterns
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