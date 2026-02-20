---
status: complete
phase: 02-token-lifecycle
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md]
started: 2026-02-20T00:00:00Z
updated: 2026-02-20T00:05:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Fresh Login via TACC OAuth2
expected: Open CKAN, click login, authenticate via TACC OAuth2, return to CKAN logged in with username visible in header.
result: pass

### 2. Browse Datasets While Authenticated
expected: After logging in, navigate to the dataset list page. Click into a dataset to view its detail page. You should remain logged in throughout (username stays in header, no login redirects).
result: pass

### 3. API Call with Valid Bearer Token
expected: Using your current JWT token, make an API call. The call should return 200 with valid JSON.
result: issue
reported: "API call returns 500 ProgrammingError: can't adapt type 'User'. oauth2helper.identify() returns tuple (name, User) but plugin.py passes it directly to model.User.by_name() which expects a string."
severity: blocker

### 4. Expired Token Triggers Logout (Session Auth)
expected: Wait for your JWT token to expire (or use a previously expired session). When you browse to any authenticated page, you should be logged out and redirected to login -- NOT left in a broken half-authenticated state.
result: pass

### 5. Token Lifecycle Events in Logs
expected: Check Docker logs for token lifecycle messages. You should see INFO-level messages about token expiration checks, refresh attempts, and their results.
result: pass

### 6. All Unit Tests Pass
expected: Run the full test suite. All 106 tests should pass with 0 failures.
result: pass

## Summary

total: 6
passed: 5
issues: 1
pending: 0
skipped: 0

## Gaps

- truth: "API call with valid Bearer token returns 200 with valid JSON"
  status: failed
  reason: "User reported: API call returns 500 ProgrammingError: can't adapt type 'User'. oauth2helper.identify() returns tuple (name, User) but plugin.py passes it directly to model.User.by_name() which expects a string."
  severity: blocker
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
