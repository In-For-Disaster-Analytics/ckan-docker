# Codebase Concerns

**Analysis Date:** 2026-02-14

## Tech Debt

### 1. SSL Certificate Detection in OAuth2 Extension

**Area:** OAuth2 Token Exchange

- **Issue:** Hardcoded string matching to detect SSL certificate errors (`"verify failed" in str(e)`)
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:186-190`, `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:455-459`
- **Impact:** Fragile error detection that depends on specific error message format. Different Python/requests versions may produce different SSL error messages, causing the code to fail silently and raise incorrect exception types.
- **Fix approach:** Refactor to catch specific SSL error types properly. Use `requests.exceptions.SSLError` and examine the exception details more carefully, potentially checking exception type hierarchy rather than string matching.
- **Priority:** Medium - Affects OAuth2 authentication reliability on systems with certificate issues

### 2. Bare Except Clauses

**Area:** Error Handling

- **Issue:** Bare `except:` clauses that catch all exceptions without filtering
- **Files:**
  - `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:171` (in `get_mime_type()`)
  - `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:293-294` (module-level template helper registration)
- **Impact:** Silently swallows exceptions including KeyboardInterrupt and SystemExit. Makes debugging difficult because errors are hidden. Can mask critical failures.
- **Fix approach:** Replace bare `except:` with `except Exception as e:` and log the error. Line 171 should specifically catch `(KeyError, ValueError, TypeError)` since it's parsing JSON. Line 293-294 should catch only `ImportError` or `AttributeError`.
- **Priority:** High - Reduces debuggability and can hide critical failures

### 3. Sensitive Information Logged at Debug Level

**Area:** OAuth2 Authentication, Security

- **Issue:** JWT secret and tokens are logged at debug level
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:394-398` (logs `jwt_secret` and `token` content)
- **Impact:** If debug logs are captured and stored, they contain sensitive authentication material. Violates security best practices. Could lead to credentials being exposed in log aggregation systems.
- **Fix approach:** Remove debug logging of `jwt_secret` (line 397) and redact token values (line 394). Only log that tokens were processed, not their content. Add explicit warning if debug logging is enabled in production.
- **Priority:** High - Security concern

### 4. Incomplete JWT Decoding Path

**Area:** OAuth2 JWT Handling

- **Issue:** Line 420 in `oauth2.py` calls `jwt.decode(token, verify=True)` without providing an algorithm or secret when `verify=False`
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:420`
- **Impact:** The `verify=False` code path is unreachable in practice but represents incomplete logic. If this path is ever taken, it will fail cryptically.
- **Fix approach:** Remove line 420 or implement proper unverified decoding with appropriate logging and warning messages.
- **Priority:** Low - Code path appears unreachable, but represents incomplete implementation

### 5. Template Comment Referring to Unclear Code

**Area:** Theme Template

- **Issue:** FIXME comment questioning template inclusion
- **Files:** `src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/read.html:40`
- **Content:** `{# FIXME why is this here? seems wrong #}`
- **Impact:** Indicates uncertainty about template structure. The `<span class="insert-comment-thread"></span>` may be cruft or undocumented feature.
- **Fix approach:** Clarify the purpose of this span element (appears to be a placeholder for comments). Remove if unused, or document its intended function.
- **Priority:** Low - Cosmetic/clarity issue

## Known Bugs

### 1. Incomplete HTTP Error Handling in Tapis Filestore

**Area:** Tapis File Proxy

- **Issue:** `serve_tapis_file()` method doesn't verify that error responses are actually returned to the client properly
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:187-191`
- **Symptoms:** 404 and 403 errors are returned with HTTP 200 status code to HTML clients (see lines 182, 127, 132), which violates HTTP semantics
- **Trigger:** Access unauthorized or non-existent Tapis files with HTML Accept header
- **Workaround:** API clients can rely on response content to detect errors despite the HTTP 200 status
- **Fix approach:** Return proper HTTP status codes for error cases (404, 401, 403). The method `intercept_errors()` intentionally converts error statuses to 200 for HTML clients, which breaks client-side error detection. Separate HTML and JSON error responses properly.
- **Priority:** Medium - Violates HTTP standards, may break client error handling

### 2. Missing Error Logging in Tapis Token Retrieval

**Area:** Tapis Integration

- **Issue:** `_get_tapis_token()` method returns `None` on auth failures but doesn't log which retrieval method failed
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:65-113`
- **Symptoms:** Users see "You must be logged in" message but admins have no insight into which auth mechanism failed
- **Trigger:** When Tapis token cannot be retrieved through any method
- **Workaround:** None - must be investigated through request logs
- **Fix approach:** Add `log.debug()` statements in each except block to indicate which method failed and why
- **Priority:** Low - Operational concern for debugging

## Security Considerations

### 1. Unvalidated File Paths in Tapis Filestore

**Area:** Tapis File Serving

- **Risk:** File path traversal via `file_path` parameter in URL
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:174-215` (method `serve_tapis_file()`)
- **Current mitigation:** None in the proxy layer. Relies entirely on Tapis server to validate access.
- **Recommendations:**
  - Validate that `file_path` doesn't contain `..` or absolute paths
  - Whitelist allowed characters in file paths
  - Log all file access attempts
  - Consider implementing a file path prefix whitelist per user
- **Priority:** Medium - Relies on external service for security

### 2. API Key Exposure in Potree Views

**Area:** Potree Scene Fetching

- **Risk:** Site API key is sent in plain HTTP headers to fetch remote files
- **Files:** `src/ckanext-potree/ckanext/potree/views.py:283-285`
- **Current mitigation:** Code checks for `ckan.site_api_key` existence
- **Recommendations:**
  - Only send API key over HTTPS
  - Consider using per-user API keys instead of site-wide key
  - Add explicit check for HTTPS before including Authorization header
  - Log API key usage for audit trail
- **Priority:** Medium - API key could be intercepted on HTTP connections

### 3. JWT Secret and Public Key Configuration

**Area:** OAuth2 JWT Handling

- **Risk:** JWT secret stored in environment variables can be exposed via process listing
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:63-66` (configuration loading)
- **Current mitigation:** Code uses `REQUESTS_CA_BUNDLE` for certificate path but doesn't validate key format
- **Recommendations:**
  - Load JWT secrets from secure files rather than environment variables
  - Validate PEM format of public keys on startup
  - Add explicit warning if JWT is enabled without proper key configuration
  - Implement automatic key rotation mechanism
- **Priority:** Medium - Depends on operational security practices

### 4. No Rate Limiting on OAuth2 Endpoints

**Area:** OAuth2 Authentication

- **Risk:** Callback endpoint has no rate limiting or brute-force protection
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/views.py:57-87` (callback handler)
- **Current mitigation:** None
- **Recommendations:**
  - Implement rate limiting per IP/user
  - Add CSRF token validation beyond state parameter
  - Log failed authentication attempts
  - Implement exponential backoff for failed attempts
- **Priority:** Medium - Could enable credential stuffing attacks

## Performance Bottlenecks

### 1. Large OAuth2 Helper Class with Linear Configuration Loading

**Area:** OAuth2 Configuration

- **Problem:** `OAuth2Helper.__init__()` performs 40+ environment variable lookups sequentially with string conversions
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:51-116`
- **Cause:** Each configuration option loads from environment, then converts to string, then strips whitespace
- **Current performance:** O(n) where n = number of config variables (~40). Not significant for startup but inefficient.
- **Improvement path:**
  - Cache environment variable lookups
  - Batch environment variable reads
  - Consider loading config once and caching in memory
- **Priority:** Low - Startup time impact is minor

### 2. Sequential HTTP Requests for Tapis File Serving

**Area:** Tapis File Proxy

- **Problem:** `serve_tapis_file()` makes two sequential HTTP requests (file info, then file content)
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:186-191`
- **Cause:** File info must be fetched before serving to determine MIME type, but full file content is fetched separately
- **Impact:** Doubles request latency for file downloads. Any network delay is multiplied.
- **Improvement path:**
  - Cache file metadata for short period (e.g., 5 minutes)
  - Consider fetching content header first to extract MIME type
  - Implement parallel requests for metadata and content
- **Priority:** Low - Only affects file download performance

### 3. Synchronous External API Calls in Flask Request Handler

**Area:** Potree Scene Viewing

- **Problem:** `_fetch_scene_data()` makes blocking HTTP request during request handling
- **Files:** `src/ckanext-potree/ckanext/potree/views.py:275-296`
- **Cause:** Uses `requests.get()` with 30-second timeout
- **Impact:** If remote resource is slow, entire Flask request thread is blocked. Can cause cascading timeouts.
- **Improvement path:**
  - Implement async/await for external HTTP calls
  - Add request timeout with clear user feedback
  - Cache scene data locally
  - Consider prefetching scene data in background task
- **Priority:** Low - Functional but could improve responsiveness

## Fragile Areas

### 1. OAuth2 User Profile Merging Logic

**Area:** OAuth2 User Identification

- **Why fragile:**
  - Merges JWT claims with API profile data with priority logic
  - If both sources are available but use different field names, data loss occurs
  - Order of merging determines which field wins if both sources have same field
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:324-348`
- **Safe modification:**
  - Add detailed logging of merge decisions
  - Implement explicit field mapping rules rather than implicit merging
  - Add tests for all merge scenarios (JWT only, API only, both)
  - Document merge behavior in README
- **Test coverage:** Moderate - tests exist but don't cover all merge scenarios
- **Priority:** Medium - Could cause silent data loss

### 2. Template Helper Registration in Tapis Filestore

**Area:** Template Helpers

- **Why fragile:**
  - Module-level code tries to register helpers at import time
  - If CKAN hasn't fully initialized, registration fails silently
  - No mechanism to verify helpers are actually registered
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:287-294`
- **Safe modification:**
  - Move helper registration to plugin's `update_config()` method
  - Add verification that helpers are registered
  - Remove bare `except:` and log actual errors
- **Test coverage:** None - this code path isn't tested
- **Priority:** Medium - Could cause templates to fail silently

### 3. Potree Scene Data Parsing with JSON5

**Area:** Potree Scene Configuration

- **Why fragile:**
  - JSON5 parsing can succeed but produce unexpected results for malformed data
  - Falls back to raw content if parsing fails, silently creating inconsistency
  - No validation of scene data structure
- **Files:** `src/ckanext-potree/ckanext/potree/views.py:33-40`, `src/ckanext-potree/ckanext/potree/views.py:299-311`
- **Safe modification:**
  - Validate parsed JSON structure against schema
  - Log warnings when falling back to raw content
  - Implement strict mode for production
  - Add tests for malformed scene data
- **Test coverage:** Limited - basic tests but no edge cases
- **Priority:** Low - Affects visualization but not data integrity

## Scaling Limits

### 1. In-Memory Token Storage

**Area:** OAuth2 Token Management

- **Current capacity:** One token per user stored in database row, loaded into memory per request
- **Limit:** No practical limit per user, but refreshing tokens requires database roundtrip on every request
- **Scaling path:**
  - Implement token caching layer (Redis) to reduce database load
  - Add token expiration check before API calls to avoid expired token errors
  - Batch token refresh operations
- **Priority:** Low - Not a current bottleneck but could become one at scale

### 2. Tapis File Streaming Buffer Size

**Area:** Tapis File Proxy

- **Current capacity:** Uses 8KB chunks for streaming (line 207)
- **Limit:** Memory-bounded but not optimized for large files or slow connections
- **Scaling path:**
  - Make chunk size configurable via environment variable
  - Implement adaptive chunk sizing based on file size
  - Add connection pooling for multiple concurrent file requests
- **Priority:** Low - Functional for current use cases

## Dependencies at Risk

### 1. OAuth2 Library Version Compatibility

**Area:** OAuth2 Authentication

- **Risk:** `requests-oauthlib` library may have breaking changes in future versions
- **Impact:** SSL certificate handling and compliance hooks depend on specific implementation details
- **Migration plan:**
  - Document required version constraints
  - Add version pinning in requirements.txt
  - Test against next major version in CI/CD
  - Consider switching to `authlib` library which has more stable API
- **Priority:** Low - Currently stable but long-term concern

### 2. JSON5 Library Dependency

**Area:** Potree Scene Configuration

- **Risk:** `json5` is less widely maintained than `json` library
- **Impact:** Parsing errors may change behavior, potential security issues in parser
- **Migration plan:**
  - Consider if standard JSON is sufficient instead of JSON5
  - Document why JSON5 is required
  - Add fallback to standard JSON parser if JSON5 parsing fails
- **Priority:** Low - Feature enhancement, not critical

## Missing Critical Features

### 1. Token Refresh Before Expiration

**Area:** OAuth2 Token Management

- **Problem:** Tokens are only refreshed when expired, leading to failed requests
- **Blocks:** Users get auth errors when token expires between requests
- **Current behavior:** `identify()` method checks token in `plugin.py:164` but doesn't preemptively refresh
- **Fix approach:** Implement token expiration check with refresh margin (e.g., refresh when 5 minutes remain)
- **Priority:** Medium - Affects user experience

### 2. Comprehensive Audit Logging

**Area:** OAuth2 Authentication, Security

- **Problem:** No central audit trail of who authenticated, when, and from where
- **Blocks:** Security investigations, compliance reporting
- **Current behavior:** Individual info-level logs scattered throughout code
- **Fix approach:**
  - Implement centralized audit log table
  - Log all authentication attempts (success and failure)
  - Include IP address, user agent, timestamp
  - Implement audit log retention policy
- **Priority:** Medium - Operational security concern

### 3. Multi-Factor Authentication Support

**Area:** OAuth2 Authentication

- **Problem:** No MFA support for elevated operations
- **Blocks:** Cannot require MFA for sensitive dataset changes
- **Current behavior:** Only uses OAuth2 provider's authentication
- **Fix approach:** Add optional MFA challenge for sensitive operations
- **Priority:** Low - Enhancement for future security hardening

## Test Coverage Gaps

### 1. OAuth2 User Profile Creation Edge Cases

**Area:** OAuth2 User Management

- **What's not tested:**
  - User creation when both username and email are missing (should fail but test doesn't exist)
  - User creation when only email is provided (should use email as username)
  - Fullname extraction from different field combinations
  - Group membership extraction when groups field is missing
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:234-260` (user creation logic)
- **Risk:** Silent failures when profile data is incomplete
- **Priority:** High - Core functionality

### 2. Tapis Filestore Error Scenarios

**Area:** Tapis File Proxy

- **What's not tested:**
  - Tapis server returns 500 errors
  - Network timeout during file transfer
  - Corrupted file content from Tapis
  - Missing MIME type in response
  - Large file streaming behavior
- **Files:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py:174-215`
- **Risk:** Unexpected failures in production
- **Priority:** Medium - Error handling

### 3. Potree Scene Data Validation

**Area:** Potree Scene Management

- **What's not tested:**
  - Invalid JSON5 syntax handling in save operations
  - File system permission errors during save
  - Concurrent save operations on same file
  - Scene data with very large coordinate values
  - Special characters in file paths
- **Files:** `src/ckanext-potree/ckanext/potree/views.py:345-373` (file save logic)
- **Risk:** Data corruption or service failures
- **Priority:** Medium - Data integrity

### 4. Database Connection Edge Cases

**Area:** OAuth2 Token Storage

- **What's not tested:**
  - Database connection failure during token update
  - Duplicate token creation (race condition)
  - Token retrieval when database is slow
  - Session cleanup in error scenarios
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/db.py`, `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:425-446`
- **Risk:** Data inconsistency or memory leaks
- **Priority:** Medium - Data consistency

### 5. OAuth2 Response Unwrapping

**Area:** OAuth2 Configuration

- **What's not tested:**
  - Deeply nested response paths (e.g., "result.data.user.info")
  - Missing intermediate keys in path navigation
  - Non-dict values at intermediate levels
  - Unicode characters in response keys
- **Files:** `src/ckanext-oauth2/ckanext/oauth2/oauth2.py:117-130` (unwrap logic)
- **Risk:** Configuration errors silently produce wrong results
- **Priority:** Medium - Configuration reliability

---

*Concerns audit: 2026-02-14*
