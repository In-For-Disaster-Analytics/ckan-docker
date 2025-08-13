# ckanext/potree/views.py
from flask import Blueprint
import ckan.plugins.toolkit as toolkit
from ckan.common import _, request, config
import json
import logging

log = logging.getLogger(__name__)

def get_blueprints():
    blueprint = Blueprint('potree', __name__)

    @blueprint.route('/dataset/potree/<resource_id>')
    def scene_viewer(resource_id):
        """Display Potree scene data in formatted JSON view"""
        try:
            # Check resource exists and get metadata
            resource = toolkit.get_action('resource_show')({}, {'id': resource_id})

            # Check user permissions
            toolkit.check_access('resource_show', {}, {'id': resource_id})

            # Validate it's a Potree scene file
            if not _is_potree_scene_resource(resource):
                toolkit.abort(400, _("Resource is not a Potree scene file"))

            # Fetch scene data
            scene_data = _fetch_scene_data(resource)

            if scene_data is None:
                toolkit.abort(404, _("Scene data could not be loaded"))

            # Get package info for context
            package = toolkit.get_action('package_show')({}, {'id': resource['package_id']})

            return toolkit.render('potree/viewer.html', {
                'resource': resource,
                'package': package,
                'scene_data': scene_data,
                'resource_id': resource_id
            })

        except toolkit.ObjectNotFound:
            toolkit.abort(404, _("Resource not found"))
        except toolkit.NotAuthorized:
            toolkit.abort(403, _("Not authorized to view this resource"))
        except Exception as e:
            log.error(f"Error displaying Potree scene {resource_id}: {str(e)}")
            toolkit.abort(500, _("Error loading scene data"))

    return blueprint

def _is_potree_scene_resource(resource):
    """Check if resource is a Potree scene file"""
    # Check by format
    if resource.get('format', '').lower() in ['potree-workspace', 'potree-scene']:
        return True

    # Check by filename extension
    if resource.get('name', '').lower().endswith('.json'):
        return True

    return False

def _fetch_scene_data(resource):
    """Fetch and parse scene data from resource"""
    import requests
    from urllib.parse import urljoin

    try:
        # Get file URL
        if resource.get('url_type') == 'upload':
            # For uploaded files, use CKAN's download URL
            site_url = config.get('ckan.site_url')
            file_url = urljoin(site_url,
                             f"/dataset/{resource['package_id']}/resource/{resource['id']}/download/{resource['name']}")
        else:
            file_url = resource['url']

        # Fetch file content
        response = requests.get(file_url, timeout=10)
        response.raise_for_status()

        # Parse JSON
        scene_data = response.json()

        # Basic validation - check if it looks like a Potree scene
        if not isinstance(scene_data, dict):
            return None

        if scene_data.get('type') != 'Potree':
            log.warning(f"Resource {resource['id']} doesn't appear to be a Potree scene file")

        return scene_data

    except requests.RequestException as e:
        log.error(f"Failed to fetch scene data: {e}")
        return None
    except json.JSONDecodeError as e:
        log.error(f"Failed to parse scene JSON: {e}")
        return None
    except Exception as e:
        log.error(f"Unexpected error fetching scene data: {e}")
        return None