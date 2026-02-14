# Configurable Response Unwrapping for OAuth2 Extension

## Problem

The OAuth2 extension hardcodes Tapis-specific response unwrapping logic (`_unwrap_tapis_response`) that extracts data from a `result` key. Different OAuth2 providers wrap their API responses differently (e.g., `result`, `response`, `data`), and some nest data multiple levels deep. The current code cannot be reused with other providers without modification.

## Solution

Replace the hardcoded `_unwrap_tapis_response` with a generic `_unwrap_response` method that uses configurable dot-notation paths to extract nested data from API responses.

## Configuration

Three new configuration values, following the existing env var + CKAN config pattern:

| Env Var | CKAN Config | Default | Purpose |
|---------|-------------|---------|---------|
| `CKAN_OAUTH2_TOKEN_RESPONSE_PATH` | `ckan.oauth2.token_response_path` | `""` | Dot-path to unwrap token response envelope |
| `CKAN_OAUTH2_TOKEN_RESPONSE_KEY` | `ckan.oauth2.token_response_key` | `access_token` | Key within unwrapped response holding the token data |
| `CKAN_OAUTH2_PROFILE_RESPONSE_PATH` | `ckan.oauth2.profile_response_path` | `""` | Dot-path to unwrap profile response envelope |

### Example: Tapis

```
CKAN_OAUTH2_TOKEN_RESPONSE_PATH=result
CKAN_OAUTH2_TOKEN_RESPONSE_KEY=access_token
CKAN_OAUTH2_PROFILE_RESPONSE_PATH=result
```

### Example: No wrapping (standard OAuth2)

All defaults work -- no unwrapping, token key is `access_token`.

## Core Method

```python
def _unwrap_response(self, data, path):
    """Unwrap a nested API response by following a dot-separated path.

    If path is empty/None, returns data unchanged.
    """
    if not path:
        return data
    for key in path.split('.'):
        if isinstance(data, dict) and key in data:
            data = data[key]
        else:
            log.warning('_unwrap_response: key "%s" not found (path: %s)', key, path)
            return data
    return data
```

## Changes

1. `__init__`: Add three new config values (`token_response_path`, `token_response_key`, `profile_response_path`)
2. Replace `_unwrap_tapis_response` with generic `_unwrap_response(data, path)`
3. `_compliance_fix`: Use `self.token_response_path` and `self.token_response_key` instead of hardcoded Tapis logic
4. `get_profile_from_api`: Use `self.profile_response_path` instead of calling `_unwrap_tapis_response`

## Error Handling

If a path key is not found in the response, log a warning and return data as-is (fail-open). This prevents breaking authentication when an API response format changes unexpectedly.

## How It Works

The `_compliance_fix` method performs a two-step unwrap on token responses:

1. **Navigate to the container** using `token_response_path` (e.g. `result` navigates into `{"result": {...}}`)
2. **Extract the token payload** using `token_response_key` (e.g. `access_token` extracts the full token dict from within the container)

For Tapis, the token endpoint returns:
```json
{"result": {"access_token": {"access_token": "...", "token_type": "Bearer", ...}}}
```

With `token_response_path=result` and `token_response_key=access_token`, the compliance fix extracts the inner token dict that oauthlib expects.

The `get_profile_from_api` method uses `profile_response_path` to unwrap profile API responses similarly (e.g. Tapis wraps profile data in `{"result": {...}}`).

## Backwards Compatibility

- Empty path defaults mean no unwrapping for providers that don't wrap responses
- `token_response_key` defaults to `access_token`, the standard OAuth2 token field
- Tapis users must add the three new env vars to their config (see `.env.dev.config` for reference)
