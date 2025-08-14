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
    if resource.get('format', '').lower() in ['potree-workspace', 'potree-scene', 'json5']:
        return True

    # Check by filename extension
    if resource.get('name', '').lower().endswith('.json5'):
        return True

    return False

def _fetch_scene_data(resource):
    """Fetch and parse scene data from resource"""
    import requests
    import os
    import ckan.lib.uploader as uploader

    try:
        logging.warning(f"Resource metadata: {resource}")
        
        # For uploaded files, try to access them directly from storage
        if resource.get('url_type') == 'upload':
            try:
                # Use CKAN's uploader to get the file path
                upload = uploader.get_resource_uploader(resource)
                file_path = upload.get_path(resource['id'])
                
                if file_path and os.path.exists(file_path):
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    log.info(f"Successfully read scene data from local file: {file_path}")
                    return json.loads(content) if content.strip() else None
                        
            except Exception as e:
                log.warning(f"Failed to read local file, falling back to HTTP: {e}")
        
        # Fallback to HTTP request with authentication
        file_url = resource.get('url')
        if not file_url:
            log.error("No URL found for resource")
            return None
            
        # Add authentication headers for internal requests
        headers = {}
        api_key = config.get('ckan.site_api_key')
        if api_key:
            headers['Authorization'] = api_key
            
        # Increase timeout for larger files
        response = requests.get(file_url, headers=headers, timeout=30)
        response.raise_for_status()
        
        content = response.text
        if not content.strip():
            log.error("Empty response from scene data URL")
            return None
            
        # Parse JSON content
        try:
            scene_data = json.loads(content)
            log.info("Successfully fetched and parsed scene data via HTTP")
            return scene_data
        except json.JSONDecodeError:
            # If it's not valid JSON, return as text (might be JSON5)
            log.info("Content is not valid JSON, returning as text")
            return content

    except requests.RequestException as e:
        log.error(f"Failed to fetch scene data: {e}")
        return None
    except json.JSONDecodeError as e:
        log.error(f"Failed to parse scene JSON: {e}")
        return None
    except Exception as e:
        log.error(f"Unexpected error fetching scene data: {e}")
        return None