# ckanext/potree/views.py
from flask import Blueprint, jsonify
import ckan.plugins.toolkit as toolkit
from ckan.common import _, request, config
import logging
import requests
import os
import json5
import ckan.lib.uploader as uploader

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
            context = {'user': toolkit.c.user}
            toolkit.check_access('resource_show', context, {'id': resource_id})

            # Validate it's a Potree scene file
            if not _is_potree_scene_resource(resource):
                toolkit.abort(400, _("Resource is not a Potree scene file"))

            # Fetch scene data
            scene_data_raw = _fetch_scene_data(resource)

            if scene_data_raw is None:
                toolkit.abort(404, _("Scene data could not be loaded"))

            # Parse JSON5 for template access
            scene_data_parsed = None
            try:
                import json5
                scene_data_parsed = json5.loads(scene_data_raw)
            except Exception as e:
                log.warning(f"Could not parse scene data as JSON5: {e}")
                scene_data_parsed = {}

            # Get package info for context
            package = toolkit.get_action('package_show')({}, {'id': resource['package_id']})

            return toolkit.render('potree/index.html', {
                'resource': resource,
                'package': package,
                'scene_data': scene_data_parsed,
                'scene_json': scene_data_raw,
                'resource_id': resource_id
            })

        except toolkit.ObjectNotFound:
            toolkit.abort(404, _("Resource not found"))
        except toolkit.NotAuthorized:
            toolkit.abort(403, _("Not authorized to view this resource"))
        except Exception as e:
            log.error(f"Error displaying Potree scene {resource_id}: {str(e)}")
            toolkit.abort(500, _("Error loading scene data"))

    @blueprint.route('/dataset/potree/<resource_id>/edit', methods=['GET', 'POST'])
    def edit_scene(resource_id):
        """Edit Potree scene configuration file"""
        try:
            # Check resource exists and get metadata
            resource = toolkit.get_action('resource_show')({}, {'id': resource_id})

            # Check user permissions - require edit access
            context = {'user': toolkit.c.user}
            toolkit.check_access('resource_update', context, {'id': resource_id})

            # Validate it's a Potree scene file
            if not _is_potree_scene_resource(resource):
                toolkit.abort(400, _("Resource is not a Potree scene file"))

            # Get package info for context
            package = toolkit.get_action('package_show')({}, {'id': resource['package_id']})

            context = {
                'resource': resource,
                'package': package,
                'resource_id': resource_id,
                'content': '',
                'error': None,
                'success': None
            }

            if request.method == 'POST':
                # Handle form submission
                new_content = request.form.get('content', '').strip()
                
                if not new_content:
                    context['error'] = _("Content cannot be empty")
                else:
                    try:
                        # Validate JSON5 syntax
                        json5.loads(new_content)
                        
                        # Save the content
                        if _save_scene_data(resource, new_content):
                            context['success'] = _("Scene configuration saved successfully")
                            context['content'] = new_content
                        else:
                            context['error'] = _("Failed to save scene configuration")
                            context['content'] = new_content
                    except Exception as e:
                        context['error'] = _("Invalid JSON5 syntax: {}").format(str(e))
                        context['content'] = new_content
            else:
                # GET request - load existing content
                scene_data_raw = _fetch_scene_data(resource)
                if scene_data_raw:
                    context['content'] = scene_data_raw
                else:
                    context['error'] = _("Could not load existing scene data")

            return toolkit.render('potree/edit.html', context)

        except toolkit.ObjectNotFound:
            toolkit.abort(404, _("Resource not found"))
        except toolkit.NotAuthorized:
            toolkit.abort(403, _("Not authorized to edit this resource"))
        except Exception as e:
            log.error(f"Error editing Potree scene {resource_id}: {str(e)}")
            toolkit.abort(500, _("Error editing scene data"))

    @blueprint.route('/dataset/potree/<resource_id>/save', methods=['POST'])
    def save_scene(resource_id):
        """Save scene data from Potree viewer back to resource file"""
        try:
            # Check resource exists and get metadata
            resource = toolkit.get_action('resource_show')({}, {'id': resource_id})

            # Check user permissions - require edit access
            auth_context = {'user': toolkit.c.user}
            toolkit.check_access('resource_update', auth_context, {'id': resource_id})

            # Validate it's a Potree scene file
            if not _is_potree_scene_resource(resource):
                return jsonify({
                    'success': False,
                    'error': 'Resource is not a Potree scene file'
                }), 400

            # Get content from form data
            new_content = request.form.get('content', '').strip()
            
            if not new_content:
                return jsonify({
                    'success': False,
                    'error': 'Content cannot be empty'
                }), 400

            try:
                # Validate JSON5 syntax
                json5.loads(new_content)
                
                # Save the content
                if _save_scene_data(resource, new_content):
                    log.info(f"Scene data saved successfully for resource: {resource_id}")
                    return jsonify({
                        'success': True,
                        'message': 'Scene data saved successfully'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': 'Failed to save scene data'
                    }), 500
                    
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': f'Invalid JSON5 syntax: {str(e)}'
                }), 400

        except toolkit.ObjectNotFound:
            return jsonify({
                'success': False,
                'error': 'Resource not found'
            }), 404
        except toolkit.NotAuthorized:
            return jsonify({
                'success': False,
                'error': 'Not authorized to edit this resource'
            }), 403
        except Exception as e:
            log.error(f"Error saving Potree scene {resource_id}: {str(e)}")
            return jsonify({
                'success': False,
                'error': 'Error saving scene data'
            }), 500

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

    # Input validation
    if not resource or not isinstance(resource, dict):
        log.error("Invalid resource provided to _fetch_scene_data")
        return None

    resource_id = resource.get('id')
    if not resource_id:
        log.error("Resource missing required 'id' field")
        return None

    try:
        log.debug(f"Fetching scene data for resource: {resource_id}")

        content = None

        # For uploaded files, try to access them directly from storage
        if resource.get('url_type') == 'upload':
            content = _read_local_file(resource)
            if content is not None:
                log.info(f"Successfully read scene data from local file for resource: {resource_id}")
                return _parse_and_normalize_content(content)

        # Fallback to HTTP request
        content = _fetch_remote_file(resource)
        if content is not None:
            log.info(f"Successfully fetched scene data via HTTP for resource: {resource_id}")
            return _parse_and_normalize_content(content)

        log.error(f"Failed to fetch scene data from any source for resource: {resource_id}")
        return None

    except Exception as e:
        log.error(f"Unexpected error fetching scene data for resource {resource_id}: {e}")
        return None


def _read_local_file(resource):
    """Read content from local uploaded file"""

    try:
        upload = uploader.get_resource_uploader(resource)
        file_path = upload.get_path(resource['id'])

        if not file_path or not os.path.exists(file_path):
            log.debug(f"Local file not found for resource: {resource['id']}")
            return None

        # Validate file path to prevent directory traversal
        if not os.path.abspath(file_path).startswith(os.path.abspath(upload.storage_path)):
            log.error(f"Invalid file path detected: {file_path}")
            return None

        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        return content.strip() if content else None

    except Exception as e:
        log.warning(f"Failed to read local file for resource {resource['id']}: {e}")
        return None


def _fetch_remote_file(resource):
    """Fetch content from remote URL"""

    file_url = resource.get('url')
    if not file_url:
        log.error(f"No URL found for resource: {resource['id']}")
        return None

    try:
        # Add authentication headers for internal requests
        headers = {}
        api_key = config.get('ckan.site_api_key')
        if api_key:
            headers['Authorization'] = api_key

        # Increase timeout for larger files
        response = requests.get(file_url, headers=headers, timeout=30)
        response.raise_for_status()

        content = response.text
        return content.strip() if content else None

    except requests.RequestException as e:
        log.error(f"Failed to fetch remote file for resource {resource['id']}: {e}")
        return None


def _parse_and_normalize_content(content):
    """Parse JSON5 content and return normalized JSON string"""

    if not content:
        return None

    try:
        # Parse as JSON5 and return as JSON string for consistency
        parsed = json5.loads(content)
        return json5.dumps(parsed)
    except Exception as e:
        log.warning(f"Failed to parse content as JSON5, returning raw content: {e}")
        return content


def _save_scene_data(resource, content):
    """Save scene data to resource file"""
    
    if not resource or not isinstance(resource, dict):
        log.error("Invalid resource provided to _save_scene_data")
        return False

    resource_id = resource.get('id')
    if not resource_id:
        log.error("Resource missing required 'id' field")
        return False

    try:
        log.debug(f"Saving scene data for resource: {resource_id}")

        # For uploaded files, try to save directly to storage
        if resource.get('url_type') == 'upload':
            if _save_local_file(resource, content):
                log.info(f"Successfully saved scene data to local file for resource: {resource_id}")
                return True

        # If local save failed or not an upload, we cannot save
        # Note: We don't support saving to remote URLs for security reasons
        log.error(f"Cannot save scene data for resource: {resource_id} (not a local upload)")
        return False

    except Exception as e:
        log.error(f"Unexpected error saving scene data for resource {resource_id}: {e}")
        return False


def _save_local_file(resource, content):
    """Save content to local uploaded file"""
    
    try:
        upload = uploader.get_resource_uploader(resource)
        file_path = upload.get_path(resource['id'])

        if not file_path:
            log.debug(f"No local file path for resource: {resource['id']}")
            return False

        # Validate file path to prevent directory traversal
        if not os.path.abspath(file_path).startswith(os.path.abspath(upload.storage_path)):
            log.error(f"Invalid file path detected: {file_path}")
            return False

        # Create directory if it doesn't exist
        os.makedirs(os.path.dirname(file_path), exist_ok=True)

        # Save content to file
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)

        log.debug(f"Successfully wrote content to: {file_path}")
        return True

    except Exception as e:
        log.error(f"Failed to save local file for resource {resource['id']}: {e}")
        return False