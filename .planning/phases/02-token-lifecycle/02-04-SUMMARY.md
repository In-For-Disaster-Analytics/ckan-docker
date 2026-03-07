---
phase: 02-token-lifecycle
plan: 04
subsystem: auth
tags: [flask-login, oauth2, jwt, ckan-2.11, bearer-token]

requires:
  - phase: 02-03
    provides: Bearer token tuple unpacking fix for identify()
provides:
  - Flask-Login login_user() integration in OAuth2 identify()
  - Bearer token API authentication returning 200 instead of 403
affects: []

tech-stack:
  added: []
  patterns:
    - "login_user(toolkit.g.userobj) after setting g.user in identify()"

key-files:
  created: []
  modified:
    - src/ckanext-oauth2/ckanext/oauth2/plugin.py
    - src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py

key-decisions:
  - "Use toolkit.g.userobj (not username string) for login_user() since it requires a User model object"
  - "Mock check_token_expiration in test_identify to fix pre-existing failures with fake JWT tokens"

patterns-established:
  - "Mock login_user in all identify tests to prevent Flask app context errors"

duration: 4min
completed: 2026-03-07
---

# Phase 2 Plan 4: Bearer Token 403 Fix Summary

**Flask-Login login_user() call in OAuth2 identify() to fix CKAN 2.11 Bearer token API 403 errors**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-07T18:20:21Z
- **Completed:** 2026-03-07T18:24:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Added flask_login.login_user() import and call in OAuth2 plugin identify() method
- CKAN 2.11 API views now recognize Bearer token-authenticated users via current_user
- Fixed 9 pre-existing test failures by mocking check_token_expiration for fake JWT tokens
- All plan-specified tests pass (6/6 specific tests, 23/28 total -- 5 pre-existing env var failures)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add login_user() to identify() and update tests** - `2a550f2` (fix)

## Files Created/Modified
- `src/ckanext-oauth2/ckanext/oauth2/plugin.py` - Added login_user import, call login_user(toolkit.g.userobj) after setting g.user
- `src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py` - Added login_user mocks to all identify tests, mocked check_token_expiration

## Decisions Made
- Used `toolkit.g.userobj` for login_user() call since it requires a User model object, not a string username
- Placed login_user() call after setting g.userobj but before token expiration check
- Mocked check_token_expiration in test_identify to fix pre-existing test failures where fake token strings were being decoded as JWT

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing test_identify failures from check_token_expiration**
- **Found during:** Task 1 (test verification)
- **Issue:** 14 parameterized test_identify cases were failing because check_token_expiration tried to decode fake JWT token string 'current_access_token'
- **Fix:** Added `plugin_setup.oauth2helper.check_token_expiration = MagicMock(return_value=(False, None))` to mock token expiration checks in test_identify
- **Files modified:** src/ckanext-oauth2/ckanext/oauth2/tests/test_plugin.py
- **Verification:** 9 previously-failing tests now pass; 5 remaining failures are pre-existing env var override issue (CKAN_OAUTH2_AUTHORIZATION_HEADER env var overrides config in container)
- **Committed in:** 2a550f2

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Auto-fix necessary for test verification. No scope creep.

## Issues Encountered
- 5 test_identify parameterized cases (headers16-20, oauth2=False) fail due to CKAN_OAUTH2_AUTHORIZATION_HEADER env var in container overriding the custom header config. These are pre-existing and unrelated to login_user changes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Bearer token API authentication fix is complete
- E2E verification requires valid Tapis credentials (deferred to UAT)
- Phase 02 token lifecycle work is fully complete

---
*Phase: 02-token-lifecycle*
*Completed: 2026-03-07*
