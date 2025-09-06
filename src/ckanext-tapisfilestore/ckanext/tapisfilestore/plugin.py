"""
ckanext-tapisfilestore

CKAN extension for handling tapis:// protocol files
Similar to ckanext-s3filestore but for Tapis file system

File: ckanext/tapisfilestore/plugin.py
"""

from dataclasses import dataclass
import json
import logging
import requests
import mimetypes
from urllib.parse import quote, unquote
from flask import Response, stream_with_context, request

import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit
from ckan.common import config
import ckan.lib.helpers as h

log = logging.getLogger(__name__)

@dataclass
class TapisFileInfo:
    mimeType: str
    type: str
    owner: str
    group: str
    nativePermissions: str
    url: str
    lastModified: str
    name: str
    path: str
    size: int


class TapisFilestorePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.IResourceController, inherit=True)
    plugins.implements(plugins.IBlueprint)

    # IConfigurer
    def update_config(self, config_):
        toolkit.add_template_directory(config_, 'templates')
        toolkit.add_public_directory(config_, 'public')
        toolkit.add_resource('fanstatic', 'tapisfilestore')

    # IBlueprint
    def get_blueprint(self):
        from flask import Blueprint
        blueprint = Blueprint('tapisfilestore', __name__)

        # Route for serving tapis files
        blueprint.add_url_rule(
            '/tapis-file/<path:file_path>',
            'serve_tapis_file',
            self.serve_tapis_file,
            methods=['GET']
        )

        return blueprint

    def _get_tapis_token(self):
        """
        Get Tapis OAuth2 token using the OAuth2 extension
        """
        # Method 1: Try the OAuth2 helper function
        try:
            token = h.oauth2_get_stored_token()
            if token:
                log.debug(f"Retrieved token via oauth2_get_stored_token: {type(token)}")
                # The token might be an object with access_token attribute
                if hasattr(token, 'access_token'):
                    return token.access_token
                # Or it might be the token string directly
                elif isinstance(token, str):
                    return token
                # Or it might be a dict
                elif isinstance(token, dict):
                    return token.get('access_token')
        except Exception as e:
            log.debug(f"oauth2_get_stored_token failed: {e}")

        # Method 2: Try toolkit.g.usertoken (set by OAuth2 plugin)
        try:
            if hasattr(toolkit.g, 'usertoken') and toolkit.g.usertoken:
                token = toolkit.g.usertoken
                log.debug(f"Retrieved token via toolkit.g.usertoken: {type(token)}")
                if isinstance(token, dict):
                    return token.get('access_token')
                elif hasattr(token, 'access_token'):
                    return token.access_token
                elif isinstance(token, str):
                    return token
        except Exception as e:
            log.debug(f"toolkit.g.usertoken failed: {e}")

        # Method 5: Try request headers
        try:
            auth_header = request.headers.get('Authorization', '')
            if auth_header.startswith('Bearer '):
                return auth_header[7:]  # Remove 'Bearer ' prefix

            # Check for custom Tapis header
            tapis_token = request.headers.get('X-Tapis-Token', '')
            if tapis_token:
                return tapis_token
        except Exception as e:
            log.debug(f"Request headers check failed: {e}")

        return None


    def intercept_errors(self, status_code, file_path):
        """
        Handle Tapis errors
        """
        if status_code == 404:
            if "text/html" in request.headers.get('Accept'):
                return Response(f'The resource is not found. Please check the URL and try again. {file_path}', status=200, content_type='text/html')
            else:
                return Response(f'The resource is not found. Please check the URL and try again. {file_path}', status=404, content_type='text/plain')
        elif status_code == 401:
            if "text/html" in request.headers.get('Accept'):
                return Response('Unauthorized: No Tapis token found. Please authenticate with Tapis through the OAuth2 system. ', status=200, content_type='text/html')
            else:
                return Response('Unauthorized: No Tapis token found. Please authenticate with Tapis through the OAuth2 system. ', status=401, content_type='text/plain')
        elif status_code == 403:
            if "text/html" in request.headers.get('Accept'):
                return Response('Forbidden: You are not authorized to access this resource. Probably the resource is not public, please contact the owner.', status=200, content_type='text/html')
            else:
                return Response('Forbidden: You are not authorized to access this resource. Probably the resource is not public, please contact the owner.', status=403, content_type='text/plain')
        elif status_code != 200:
            if "text/html" in request.headers.get('Accept'):
                return Response(f'Error fetching file from Tapis: {status_code}', status=status_code, content_type='text/html')
            else:
                return Response(f'Error fetching file from Tapis: {status_code}', status=status_code, content_type='text/plain')

    def request_file_info(self, file_path, tapis_token) -> Response:
        """
        Get the MIME type for a file
        """
        url = f"https://portals.tapis.io/v3/files/ops/{file_path}"
        headers = {
            'x-tapis-token': tapis_token,
            'Accept': '*/*'
        }
        return requests.get(url, headers=headers)


    def request_file_content(self, file_path, tapis_token) -> Response:
        """
        Get the content of a file
        """
        url = f"https://portals.tapis.io/v3/files/content/{file_path}"
        headers = {
            'x-tapis-token': tapis_token,
            'Accept': '*/*'
        }
        return requests.get(url, headers=headers, stream=True)

    def get_mime_type(self, response_file_info) -> str:
        try:
            response_info = response_file_info.json()
            if 'result' in response_info and len(response_info['result']) > 0:
                return response_info['result'][0]['mimeType']
            else:
                return 'application/octet-stream'
        except:
            return 'application/octet-stream'

    def serve_tapis_file(self, file_path):
        """
        Serve a file from Tapis file system by proxying the request
        """

        tapis_token = self._get_tapis_token()
        if not tapis_token:
            if "text/html" in request.headers.get('Accept'):
                return Response('You must be logged in to access this resource. Please log in and try again.', status=200, content_type='text/html')
            else:
                return Response('You must be logged in to access this resource. Please log in and try again.', status=401)

        response_file_info = self.request_file_info(file_path, tapis_token)
        if self.intercept_errors(response_file_info.status_code, file_path):
            return self.intercept_errors(response_file_info.status_code, file_path)
        response_file_content = self.request_file_content(file_path, tapis_token)
        if self.intercept_errors(response_file_content.status_code, file_path):
            return self.intercept_errors(response_file_content.status_code, file_path)

        filename = file_path.split('/')[-1] if len(file_path) > 0 else file_path
        mime_type = self.get_mime_type(response_file_info)

        response_headers = {
            'Content-Type': mime_type,
            'Content-Disposition': f'inline; filename="{filename}"'
        }

        # Add content length if available
        if 'content-length' in response_file_content.headers:
            response_headers['Content-Length'] = response_file_content.headers['content-length']

        # Stream the response
        def generate():
            for chunk in response_file_content.iter_content(chunk_size=8192):
                if chunk:
                    yield chunk

        return Response(
            stream_with_context(generate()),
            headers=response_headers,
            status=200
        )


    # IResourceController
    def before_resource_show(self, resource_dict):
        """
        Modify resource URLs for tapis:// files before showing them
        """
        url = resource_dict.get('url', '')

        if url.startswith('tapis://'):
            # Extract the path after tapis://
            tapis_path = url[8:]  # Remove 'tapis://' prefix

            # Create the CKAN route URL for serving the file
            resource_dict['url'] = toolkit.url_for(
                'tapisfilestore.serve_tapis_file',
                file_path=tapis_path,
                _external=True
            )

            # Store the original tapis URL for reference
            resource_dict['tapis_original_url'] = url

        return resource_dict

    def after_resource_create(self, context, resource):
        """Handle resource creation - for tapis files, just validate the URL format"""
        url = resource.get('url', '')
        if url.startswith('tapis://'):
            # Validate tapis URL format
            if len(url) <= 8 or not url[8:]:  # Must have content after 'tapis://'
                raise toolkit.ValidationError({'url': ['Invalid tapis:// URL format']})
        return resource

    def after_resource_update(self, context, resource):
        """Handle resource updates - similar validation as create"""
        return self.after_resource_create(context, resource)


def is_tapis_url(url):
    """Check if a URL is a tapis:// URL"""
    return url and url.startswith('tapis://')


def get_tapis_download_url(url):
    """Convert a tapis:// URL to a CKAN download URL"""
    if not is_tapis_url(url):
        return url

    tapis_path = url[8:]  # Remove 'tapis://' prefix
    return toolkit.url_for(
        'tapisfilestore.serve_tapis_file',
        file_path=tapis_path,
        _external=True
    )


def get_tapis_view_url(url):
    """Get view URL for tapis files (same as download for now)"""
    return get_tapis_download_url(url)


# Template helper functions
def tapis_helpers():
    return {
        'is_tapis_url': is_tapis_url,
        'get_tapis_download_url': get_tapis_download_url,
        'get_tapis_view_url': get_tapis_view_url,
    }


# Register template helpers
try:
    toolkit.add_template_directory(config, 'templates')
    h.is_tapis_url = is_tapis_url
    h.get_tapis_download_url = get_tapis_download_url
    h.get_tapis_view_url = get_tapis_view_url
except:
    pass  # Helpers will be registered when plugin loads


