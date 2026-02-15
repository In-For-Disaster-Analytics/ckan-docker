---
phase: 02-token-lifecycle
plan: 02
subsystem: OAuth2 Authentication
tags: [verification, token-lifecycle, e2e-testing]
dependency_graph:
  requires:
    - Plan 02-01 (JWT token expiration and auto-refresh)
    - Docker development environment
  provides:
    - Human-verified token lifecycle functionality
    - Logout on failed token refresh
  affects:
    - ckanext-oauth2 plugin identify() flow
tech_stack:
  added: []
  patterns:
    - Full user logout when token refresh fails (session + stored token)
key_files:
  created: []
  modified:
    - src/ckanext-oauth2/ckanext/oauth2/plugin.py
    - src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py
    - src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py
decisions:
  - Log out user completely when stored token refresh fails (not just clear token)
  - Fix test isolation issue by restoring real jwt module in TestTokenExpiration setup
metrics:
  duration_minutes: 30
  tasks_completed: 2
  tests_added: 0
  files_modified: 3
  commits: 4
  completed_date: 2026-02-14
---

# Phase 02 Plan 02: Token Lifecycle End-to-End Verification

**One-liner:** Human-verified token lifecycle with fix for session logout on refresh failure

## Summary

Deployed the updated OAuth2 extension to development environment and performed human verification of token lifecycle behavior. Discovered and fixed a critical issue: when a session-authenticated user's stored token is expired and refresh fails, the user was NOT being logged out (only `g.usertoken` was cleared). Fixed to perform full logout including session cookie invalidation.

### Verification Results

1. **Token expiration detected** -- Logs confirmed `is_expired=True` for stored tokens
2. **Refresh attempted** -- `refresh_token()` called but returned failed (expected, Tapis refresh token also expired)
3. **Original bug found** -- User stayed logged in via Flask-Login session cookie despite expired token and failed refresh
4. **Fix applied** -- Full logout (clear g.user, g.userobj, g.usertoken, call logout_user()) when refresh fails
5. **Fix verified** -- User is now properly logged out and redirected to login when refresh fails

### Test Fixes

- Fixed `test_identify_session_expired_token_refresh_fails` to mock `logout_user` (requires Flask request context)
- Updated assertion to verify user IS logged out (not just token cleared)
- Added `mock_logout.assert_called_once()` assertion
- Fixed `TestTokenExpiration` test isolation: `TestOAuth2Plugin` was globally mocking `oauth2.jwt`; added `setup_method` to restore real jwt module
- All 106 tests pass

## Deviations from Plan

1. **Found bug during verification** -- Session-authenticated users with expired tokens were not being logged out when refresh failed. Fixed by adding full logout logic matching the existing `_refresh_and_save_token` pattern.
2. **Test isolation fix** -- `TestOAuth2Plugin` class sets `oauth2.jwt = MagicMock()` globally without cleanup, causing `TestTokenExpiration` to fail when run after it in the full suite.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 5edf24b | enhance token expiration logging and refresh process |
| 1 | 348fdeb | improve token refresh failure handling and user logout |
| 2 | 372cba8 | enhance session expiration test to verify user logout |
| 2 | b3d06e5 | fix test isolation for TestTokenExpiration |

## Self-Check: PASSED

**Modified files:**
- src/ckanext-oauth2/ckanext/oauth2/plugin.py -- full logout on refresh failure
- src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py -- mock logout_user, verify logout
- src/ckanext-oauth2/ckanext/oauth2/tests/test_oauth2.py -- restore jwt module in setup_method

**Tests:** 106/106 passing
