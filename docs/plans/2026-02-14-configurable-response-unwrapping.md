# Configurable Response Unwrapping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace hardcoded Tapis response unwrapping with a generic, configurable dot-path based unwrapper in the OAuth2 extension.

**Architecture:** Add a generic `_unwrap_response(data, path)` method that traverses dot-separated keys. Three new config values control token envelope path, token key, and profile envelope path. The existing `_unwrap_tapis_response` is removed entirely.

**Tech Stack:** Python, requests-oauthlib, pytest, httpretty

---

### Task 1: Write tests for `_unwrap_response`

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py`

**Step 1: Write failing tests for `_unwrap_response`**

Add these tests to `TestOAuth2Plugin` class at the end of the file:

```python
def test_unwrap_response_empty_path(self, oauth2_setup):
    """Empty path returns data unchanged"""
    helper = self._helper(oauth2_setup)
    data = {'foo': 'bar'}
    assert helper._unwrap_response(data, '') == data
    assert helper._unwrap_response(data, None) == data

def test_unwrap_response_single_key(self, oauth2_setup):
    """Single key path unwraps one level"""
    helper = self._helper(oauth2_setup)
    data = {'result': {'username': 'test'}}
    assert helper._unwrap_response(data, 'result') == {'username': 'test'}

def test_unwrap_response_nested_path(self, oauth2_setup):
    """Dot-separated path unwraps multiple levels"""
    helper = self._helper(oauth2_setup)
    data = {'response': {'data': {'username': 'test'}}}
    assert helper._unwrap_response(data, 'response.data') == {'username': 'test'}

def test_unwrap_response_missing_key(self, oauth2_setup):
    """Missing key in path returns data as-is"""
    helper = self._helper(oauth2_setup)
    data = {'foo': 'bar'}
    assert helper._unwrap_response(data, 'nonexistent') == data

def test_unwrap_response_partial_path(self, oauth2_setup):
    """Partially valid path returns data at point of failure"""
    helper = self._helper(oauth2_setup)
    data = {'result': {'foo': 'bar'}}
    assert helper._unwrap_response(data, 'result.nonexistent') == {'foo': 'bar'}
```

**Step 2: Run tests to verify they fail**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_empty_path -v`
Expected: FAIL with `AttributeError: 'OAuth2Helper' object has no attribute '_unwrap_response'`

**Step 3: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py
git commit -m "test: add tests for generic _unwrap_response method"
```

---

### Task 2: Implement `_unwrap_response` and new config values

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:53-119`

**Step 1: Add config values to `__init__`**

Add these three lines after `self.sysadmin_group_name` (line 90) and before `site_url` (line 92):

```python
self.token_response_path = str(os.environ.get('CKAN_OAUTH2_TOKEN_RESPONSE_PATH', cfg.get('ckan.oauth2.token_response_path', ''))).strip()
self.token_response_key = str(os.environ.get('CKAN_OAUTH2_TOKEN_RESPONSE_KEY', cfg.get('ckan.oauth2.token_response_key', 'access_token'))).strip()
self.profile_response_path = str(os.environ.get('CKAN_OAUTH2_PROFILE_RESPONSE_PATH', cfg.get('ckan.oauth2.profile_response_path', ''))).strip()
```

**Step 2: Replace `_unwrap_tapis_response` with `_unwrap_response`**

Delete the `_unwrap_tapis_response` method (lines 114-119) and replace with:

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

**Step 3: Run tests to verify they pass**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_empty_path ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_single_key ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_nested_path ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_missing_key ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_unwrap_response_partial_path -v`
Expected: All 5 PASS

**Step 4: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/oauth2.py
git commit -m "feat: add generic _unwrap_response with configurable dot-path"
```

---

### Task 3: Write tests for configurable `_compliance_fix`

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py`

**Step 1: Write failing tests for token response unwrapping**

Add these tests to `TestOAuth2Plugin`:

```python
def test_compliance_fix_with_token_response_path(self, oauth2_setup):
    """Token response unwrapping uses configured path and key"""
    helper = self._helper(oauth2_setup, conf={
        'ckan.oauth2.token_response_path': 'result',
        'ckan.oauth2.token_response_key': 'access_token',
    })

    mock_response = MagicMock()
    mock_response.json.return_value = {
        'result': {
            'access_token': {
                'access_token': 'my_token',
                'token_type': 'Bearer',
            }
        }
    }

    session = MagicMock()
    hooks = {}

    def register_hook(name, fn):
        hooks[name] = fn

    session.register_compliance_hook = register_hook
    helper._compliance_fix(session)

    result = hooks['access_token_response'](mock_response)
    content = json.loads(result._content.decode('utf-8'))
    assert content == {'access_token': 'my_token', 'token_type': 'Bearer'}

def test_compliance_fix_without_token_response_path(self, oauth2_setup):
    """No unwrapping when token_response_path is empty"""
    helper = self._helper(oauth2_setup)

    mock_response = MagicMock()
    mock_response.json.return_value = {
        'access_token': 'my_token',
        'token_type': 'Bearer',
    }

    session = MagicMock()
    hooks = {}

    def register_hook(name, fn):
        hooks[name] = fn

    session.register_compliance_hook = register_hook
    helper._compliance_fix(session)

    result = hooks['access_token_response'](mock_response)
    # Response should be returned unchanged (no _content modification)
    assert result == mock_response
```

**Step 2: Run tests to verify they fail**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_compliance_fix_with_token_response_path -v`
Expected: FAIL (current code uses hardcoded Tapis logic)

**Step 3: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py
git commit -m "test: add tests for configurable compliance_fix"
```

---

### Task 4: Update `_compliance_fix` to use config values

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:121-133`

**Step 1: Update `_compliance_fix`**

Replace the current `_compliance_fix` method with:

```python
def _compliance_fix(self, session):
    """Apply compliance hooks to the OAuth2 session."""
    def _fix_access_token(response):
        if not self.token_response_path:
            return response
        data = response.json()
        log.debug(f"data: {data}")
        unwrapped = self._unwrap_response(data, self.token_response_path)
        if self.token_response_key and self.token_response_key in unwrapped:
            response._content = json.dumps(unwrapped[self.token_response_key]).encode('utf-8')
        return response

    session.register_compliance_hook('access_token_response', _fix_access_token)
    return session
```

**Step 2: Run compliance_fix tests to verify they pass**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_compliance_fix_with_token_response_path ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_compliance_fix_without_token_response_path -v`
Expected: All PASS

**Step 3: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/oauth2.py
git commit -m "feat: update compliance_fix to use configurable response path"
```

---

### Task 5: Write tests for configurable profile response unwrapping

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py`

**Step 1: Write failing tests for profile response unwrapping**

Add these tests to `TestOAuth2Plugin`:

```python
@httpretty.activate
def test_get_profile_from_api_with_path(self, oauth2_setup):
    """Profile API response is unwrapped using configured path"""
    helper = self._helper(oauth2_setup, conf={
        'ckan.oauth2.profile_response_path': 'result',
    })

    wrapped_response = {
        'result': {
            oauth2_setup['user_field']: 'testuser',
            oauth2_setup['email_field']: 'test@example.com',
        }
    }

    httpretty.register_uri(
        httpretty.GET,
        oauth2_setup['profile_api_url'],
        body=json.dumps(wrapped_response),
    )

    profile = helper.get_profile_from_api(OAUTH2TOKEN)
    assert profile[oauth2_setup['user_field']] == 'testuser'
    assert profile[oauth2_setup['email_field']] == 'test@example.com'

@httpretty.activate
def test_get_profile_from_api_without_path(self, oauth2_setup):
    """Profile API response returned as-is when no path configured"""
    helper = self._helper(oauth2_setup)

    flat_response = {
        oauth2_setup['user_field']: 'testuser',
        oauth2_setup['email_field']: 'test@example.com',
    }

    httpretty.register_uri(
        httpretty.GET,
        oauth2_setup['profile_api_url'],
        body=json.dumps(flat_response),
    )

    profile = helper.get_profile_from_api(OAUTH2TOKEN)
    assert profile[oauth2_setup['user_field']] == 'testuser'
    assert profile[oauth2_setup['email_field']] == 'test@example.com'
```

**Step 2: Run tests to verify they fail**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py::TestOAuth2Plugin::test_get_profile_from_api_with_path -v`
Expected: FAIL (current code calls `_unwrap_tapis_response` which no longer exists)

**Step 3: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py
git commit -m "test: add tests for configurable profile response unwrapping"
```

---

### Task 6: Update `get_profile_from_api` to use config

**Files:**
- Modify: `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:301-308`

**Step 1: Update `get_profile_from_api`**

Replace line 308 (`return self._unwrap_tapis_response(profile_data)`) with:

```python
return self._unwrap_response(profile_data, self.profile_response_path)
```

**Step 2: Run all tests to verify everything passes**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/test_oauth2.py -v`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add src/ckanext-oauth2/ckanext/oauth2/oauth2.py
git commit -m "feat: update get_profile_from_api to use configurable response path"
```

---

### Task 7: Run full test suite and verify

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `cd src/ckanext-oauth2 && pytest ckanext/oauth2/tests/ -v`
Expected: All tests PASS

**Step 2: Verify no references to `_unwrap_tapis_response` remain**

Search for any remaining references to the old method name in the codebase.

**Step 3: Final commit if any cleanup needed**
