---
phase: 01-migration-verification
plan: 01
subsystem: tacc_theme
tags: [bootstrap5, ui, templates, css, migration]
dependency_graph:
  requires: []
  provides: [bootstrap5-compatible-templates, bootstrap5-compatible-css]
  affects: [all-dataset-pages, all-resource-listings, spatial-forms, group-pages]
tech_stack:
  added: []
  patterns: [bootstrap5-data-attributes, bootstrap5-utility-classes, bootstrap5-badge-components]
key_files:
  created: []
  modified:
    - src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/snippets/resource_item.html
    - src/ckanext-tacc_theme/ckanext/tacc_theme/templates/forms_snippets/spatial.html
    - src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/read.html
    - src/ckanext-tacc_theme/ckanext/tacc_theme/templates/group/snippets/group_item.html
    - src/ckanext-tacc_theme/ckanext/tacc_theme/assets/tacc_colors.css
decisions:
  - context: Bootstrap 3 to Bootstrap 5 migration approach
    choice: Update existing templates and CSS in place rather than rewrite from scratch
    rationale: Preserves custom TACC functionality (DYNAMO integration, spatial forms) while modernizing framework compatibility
    alternatives: [complete-rewrite, gradual-component-replacement]
  - context: CSS backward compatibility
    choice: Keep legacy .label selectors alongside new .badge selectors
    rationale: Ensures compatibility with any CKAN core templates that might still use .label classes
    alternatives: [remove-legacy-selectors, create-separate-css-file]
metrics:
  duration_minutes: 2
  tasks_completed: 2
  files_modified: 5
  lines_changed: 57
  commits: 2
  completed_date: 2026-02-14
---

# Phase 01 Plan 01: Bootstrap 5 Template Modernization Summary

**One-liner:** Updated tacc_theme extension templates and CSS from Bootstrap 3 patterns (data-toggle, label classes, pull-* floats) to Bootstrap 5 equivalents (data-bs-toggle, badge classes, float-* utilities) for CKAN 2.11 compatibility.

## What Was Built

Fixed all Bootstrap 3 incompatibilities in the tacc_theme extension that were preventing interactive elements (dropdowns, modals) from working and visual elements (badges, floats) from rendering correctly in CKAN 2.11.

### Components Updated

**Templates (4 files):**
1. `resource_item.html` - Resource dropdown menus and dividers
2. `spatial.html` - Spatial coverage modal close/cancel buttons and JavaScript selectors
3. `package/read.html` - Private dataset badge
4. `group_item.html` - Group role badge

**CSS (1 file):**
1. `tacc_colors.css` - Added Bootstrap 5 badge selectors for format labels and UI components

### Key Changes

**Data Attributes:**
- `data-toggle="dropdown"` → `data-bs-toggle="dropdown"`
- `data-dismiss="modal"` → `data-bs-dismiss="modal"`
- Updated JavaScript querySelector to match new attributes: `[data-bs-dismiss="modal"]`

**HTML Structure:**
- Dropdown dividers: `<li class="divider"></li>` → `<li><hr class="dropdown-divider"></li>`

**CSS Classes:**
- `label label-inverse pull-right` → `badge bg-dark float-end`
- `label label-default` → `badge bg-secondary`

**CSS Selectors (backward-compatible additions):**
- Added `.badge.bg-dark` and `.badge.bg-secondary` alongside `.label`
- Added `.badge[data-format]` selectors for all 9 format types (html, json, xml, text, csv, xls, zip, api, pdf, rdf)
- Updated `.dataset-private.pull-right` to `.dataset-private.float-end`

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All verification criteria met:

1. **Bootstrap 3 patterns removed:**
   - Zero `data-toggle`, `data-dismiss`, `data-target` attributes in templates ✓
   - Zero `label label-*` classes in templates ✓
   - Zero `pull-right`, `pull-left` classes in templates ✓

2. **Bootstrap 5 patterns added:**
   - `data-bs-toggle` and `data-bs-dismiss` attributes present ✓
   - `badge bg-*` classes present ✓
   - `float-end` utility class present ✓

3. **CSS completeness:**
   - 23 `.badge[data-format]` selectors found (covering all format types with wildcards) ✓
   - `.dataset-private.float-end` selector exists ✓
   - `.badge.bg-dark` and `.badge.bg-secondary` selectors exist ✓

4. **Syntax validity:**
   - All HTML/Jinja2 tags properly closed ✓
   - All CSS rules have closing braces ✓

## Impact

**User-facing changes:**
- Dropdown menus on resource items now open when clicked (previously broken)
- Spatial modal close and cancel buttons now dismiss the modal (previously broken)
- Private dataset badge displays with correct dark background and alignment
- Group role labels display with proper badge styling (not unstyled text)
- Resource format labels (CSV, JSON, PDF, etc.) display with correct background colors

**Developer impact:**
- All future template development should use Bootstrap 5 patterns
- CSS maintains backward compatibility with legacy `.label` selectors for CKAN core templates

**Technical debt:**
- Legacy `.label` selectors retained for safety - can be removed in future cleanup if verified unused

## Tasks Completed

| Task | Description | Commit | Files Modified |
|------|-------------|--------|----------------|
| 1 | Fix Bootstrap 5 data attributes and HTML patterns in tacc_theme templates | 0abaa8f | resource_item.html, spatial.html, package/read.html, group_item.html |
| 2 | Modernize tacc_colors.css from Bootstrap 3 label selectors to Bootstrap 5 badge selectors | 9bd74d7 | tacc_colors.css |

## Self-Check: PASSED

**Files verified:**
- [FOUND] src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/snippets/resource_item.html
- [FOUND] src/ckanext-tacc_theme/ckanext/tacc_theme/templates/forms_snippets/spatial.html
- [FOUND] src/ckanext-tacc_theme/ckanext/tacc_theme/templates/package/read.html
- [FOUND] src/ckanext-tacc_theme/ckanext/tacc_theme/templates/group/snippets/group_item.html
- [FOUND] src/ckanext-tacc_theme/ckanext/tacc_theme/assets/tacc_colors.css

**Commits verified:**
- [FOUND] 0abaa8f (Task 1)
- [FOUND] 9bd74d7 (Task 2)

All claimed files and commits exist and are reachable.
