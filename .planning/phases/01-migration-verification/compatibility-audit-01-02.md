# CKAN 2.11 Extension Compatibility Audit
**Date:** 2026-02-14
**Phase:** 01-migration-verification
**Plan:** 01-02
**Scope:** All five custom CKAN extensions

## Executive Summary

**Result:** 4 of 5 extensions PASSED all compatibility checks. 1 extension (potree) has WARNING-level Bootstrap 3 issues.

**Critical Issues:** 0
**Warnings:** 1 (potree - Bootstrap 3 data attributes)

## Detailed Findings

### Check 1: Deprecated Interface Methods
**Status:** ✓ PASSED

Searched for deprecated unscoped IResourceController/IPackageController methods across all extensions:
- `def before_create(` - Not found
- `def after_create(` - Not found
- `def before_show(` - Not found
- `def after_show(` - Not found
- `def before_update(` - Not found
- `def after_update(` - Not found

**Result:** All extensions correctly use scoped methods (e.g., `before_resource_show`, `after_dataset_create`).

---

### Check 2: Deprecated Helper Functions
**Status:** ✓ PASSED

Searched all templates for removed helper functions:
- `h.submit(` - Not found
- `h.radio(` - Not found
- `h.icon(` - Not found
- `{{ h.snippet(` - Not found

**Result:** All templates use CKAN 2.11-compatible helper syntax.

---

### Check 3: Deprecated Template Syntax
**Status:** ✓ PASSED

Searched for deprecated template patterns:
- `h.activity_div(` - Not found
- `c.action` - Not found

**Result:** No deprecated template syntax in use.

---

### Check 4: tapisfilestore Extension Audit
**Status:** ✓ PASSED

**File:** `src/ckanext-tapisfilestore/ckanext/tapisfilestore/plugin.py`

**Interface implementation:**
- ✓ Uses `IResourceController` with `inherit=True` (line 41)
- ✓ Uses scoped methods:
  - `before_resource_show` (line 219)
  - `after_resource_create` (line 241)
  - `after_resource_update` (line 250)
- ✓ Uses `IBlueprint` for Flask blueprint registration (line 42, 51-63)
- ✓ Properly uses Flask patterns:
  - `from flask import Response, stream_with_context, request` (line 16)
  - Flask blueprint with `add_url_rule` (line 56-61)
  - Flask `Response` objects (lines 122, 127, 132, etc.)
  - Flask `request.headers` (line 102, 121, etc.)
- ✓ No deprecated Pylons patterns detected

**Token handling:**
- Multi-fallback token retrieval strategy (lines 65-113)
- Proper error handling for auth failures (lines 116-139)
- Uses `toolkit.url_for` for URL generation (line 230, 266)

**Result:** tapisfilestore is fully compatible with CKAN 2.11 Flask architecture.

---

### Check 5: potree Extension Audit
**Status:** ✓ PASSED (code-level)

**File:** `src/ckanext-potree/ckanext/potree/plugin.py`

**Interface implementation:**
- ✓ Uses `IBlueprint` for Flask blueprint registration (line 8, 19-44)
- ✓ Uses `IResourceController` with scoped methods:
  - `before_resource_create` (line 92)
  - `before_resource_update` (line 96)
  - `before_resource_show` (line 100)
  - `after_resource_create` (line 104)
  - `after_resource_update` (line 108)
  - `after_resource_delete` (line 112)
  - `before_resource_delete` (line 116)
- ✓ Uses `IResourceView` interface (line 10, 54-89)
- ✓ Proper Flask blueprint with `add_url_rule` (lines 24-43)
- ✓ No deprecated Pylons patterns

**Result:** potree plugin.py is fully compatible with CKAN 2.11.

---

### Check 6: Bootstrap 3 Patterns in All Extensions
**Status:** ⚠️ WARNING (potree extension)

**Searched patterns:**
- `data-toggle=` (Bootstrap 3)
- `data-dismiss=` (Bootstrap 3)
- `label label-` (Bootstrap 3)

**Findings:**

**tacc_theme:** ✓ CLEAN (fixed in Plan 01-01)

**oauth2:** ✓ CLEAN (no custom templates with BS patterns)

**dso_scheming:** ✓ CLEAN (schema-only extension)

**tapisfilestore:** ✓ CLEAN (no custom templates with BS patterns)

**potree:** ⚠️ WARNING - Bootstrap 3 data attributes found

**File:** `src/ckanext-potree/ckanext/potree/templates/potree/edit.html`
**Lines:** 73, 109, 131
**Pattern:** `data-toggle="collapse"`
**Context:** Accordion help section on scene editor page

```html
73:  <a class="accordion-toggle" data-toggle="collapse" data-parent="#help-accordion" href="#basic-structure">
109: <a class="accordion-toggle" data-toggle="collapse" data-parent="#help-accordion" href="#point-cloud-config">
131: <a class="accordion-toggle" data-toggle="collapse" data-parent="#help-accordion" href="#json5-features">
```

**Impact:** WARNING (not critical)
- This page is for advanced users editing Potree scene JSON5 config files
- Accordions likely won't open/close when clicked
- Does NOT affect main dataset/resource viewing functionality
- Does NOT affect main theme UI (already fixed in Plan 01-01)
- Does NOT affect file proxy or core CKAN functionality

**Recommended fix:** Replace `data-toggle="collapse"` with `data-bs-toggle="collapse"` (Bootstrap 5)

---

## Summary by Extension

| Extension | Check 1 | Check 2 | Check 3 | Check 4/5 | Check 6 | Overall |
|-----------|---------|---------|---------|-----------|---------|---------|
| oauth2 | PASS | PASS | PASS | N/A | PASS | ✓ PASS |
| tacc_theme | PASS | PASS | PASS | N/A | PASS | ✓ PASS |
| dso_scheming | PASS | PASS | PASS | N/A | PASS | ✓ PASS |
| tapisfilestore | PASS | PASS | PASS | PASS | PASS | ✓ PASS |
| potree | PASS | PASS | PASS | PASS | WARN | ⚠️ WARN |

## Conclusion

**All five extensions are compatible with CKAN 2.11 at the code level.**

**Critical issues:** 0
- All interface implementations use CKAN 2.11 patterns
- All Flask/IBlueprint usage is correct
- No deprecated Pylons patterns
- No deprecated template helpers

**Non-critical issues:** 1
- potree extension has Bootstrap 3 data attributes in edit.html template
- Affects accordion UX on admin scene editor page only
- Fix recommended but not blocking for Phase 1 completion

**Migration verification can proceed to manual smoke testing (Task 2).**
