# Potree Scene Editing Permissions Test Plan

This document provides step-by-step instructions for testing the Potree scene editing functionality with different user permission levels as outlined in issue #94.

## Prerequisites

1. Development environment running with OAuth disabled
2. CKAN container accessible via: `docker compose -f docker-compose.dev.yml exec ckan-dev bash`

## Step 1: Environment Setup

### Disable OAuth (Already Done)

OAuth has been disabled by removing `oauth2` from the plugins list in `.env.dev.config` and adding `potree` plugin.

### Restart CKAN Development Container

```bash
docker compose -f docker-compose.dev.yml restart ckan-dev
```

## Step 2: Create Test Users

Access the CKAN development container:

```bash
docker compose -f docker-compose.dev.yml exec ckan-dev bash
```

Create test users with different permission levels:

```bash
# User A (Dataset Owner/Sysadmin)
ckan -c /srv/app/ckan.ini user add usera email=usera@test.com password=testpass123
ckan -c /srv/app/ckan.ini sysadmin add usera

# User B (Regular User - No Special Permissions)
ckan -c /srv/app/ckan.ini user add userb email=userb@test.com password=testpass123

# User C (Organization Editor)
ckan -c /srv/app/ckan.ini user add userc email=userc@test.com password=testpass123

# Verify users were created
ckan -c /srv/app/ckan.ini user list
```

## Step 3: Create Organization and Set Permissions

First create userA's API token (will be used in Step 5, but needed now):

```bash
# Create API token for usera (run this first)
USERA_TOKEN=$(ckan -c /srv/app/ckan.ini api action api_token_create user=usera name=org-admin-token | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
echo "UserA Token: $USERA_TOKEN"
```

Create organization and set permissions:

```bash
# Create test organization using userA's token
ckan -c /srv/app/ckan.ini api action organization_create \
  apikey=$USERA_TOKEN \
  name=test-org \
  title="Test Organization" \
  description="Organization for permission testing"

# Add userc as editor to the organization
ckan -c /srv/app/ckan.ini api action organization_member_create \
  apikey=$USERA_TOKEN \
  id=test-org \
  username=userc \
  role=editor

# userB remains without organization membership
```

Alternative method using ckanapi if the above doesn't work:

```bash
# Install ckanapi in the container if not available
pip install ckanapi

# Create organization using ckanapi
ckanapi action organization_create -c /srv/app/ckan.ini -u userA \
  name=test-org \
  title="Test Organization" \
  description="Organization for permission testing"

# Add member using ckanapi
ckanapi action organization_member_create -c /srv/app/ckan.ini -u userA \
  id=test-org \
  username=userC \
  role=editor
```

## Step 4: Create Test Dataset

```bash
# Create dataset using userA's token
ckan -c /srv/app/ckan.ini api action package_create \
  apikey=$USERA_TOKEN \
  name=test-potree-dataset \
  title="Test Potree Dataset" \
  owner_org=test-org \
  notes="Dataset for testing Potree scene editing permissions"
```

## Step 5: Create API Tokens for Users

CKAN 2.9 uses API tokens (preferred) over legacy API keys. Create tokens for each user:

```bash
# Create API tokens for each user (CKAN 2.9 preferred method)
echo "Creating API tokens..."

# Create token for usera
USERA_TOKEN=$(ckan -c /srv/app/ckan.ini api action api_token_create user=usera name=testing-token | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
echo "UserA Token: $USERA_TOKEN"

# Create token for userb
USERB_TOKEN=$(ckan -c /srv/app/ckan.ini api action api_token_create user=userb name=testing-token | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
echo "UserB Token: $USERB_TOKEN"

# Create token for userc
USERC_TOKEN=$(ckan -c /srv/app/ckan.ini api action api_token_create user=userc name=testing-token | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
echo "UserC Token: $USERC_TOKEN"
```

## Step 6: Upload Scene.json5 File

1. **Login as usera** via web interface (http://localhost:5000)
2. **Navigate** to the test dataset: http://localhost:5000/dataset/test-potree-dataset
3. **Add resource** with a sample scene.json5 file:

Sample scene.json5 content:

```json5
{
  version: '1.7',
  octreeDir: 'pointclouds/cloud_1',
  sources: [
    {
      path: 'cloud.las',
      crs: 'EPSG:4326',
    },
  ],
  pointAttributes: ['POSITION_CARTESIAN', 'COLOR_PACKED'],
  spacing: 0.01,
  scale: 0.001,
  hierarchyStepSize: 5,
}
```

## Step 7: Test Permission Scenarios

### Test Case 1: usera (Dataset Owner/Sysadmin)

- **Expected**: Full edit access
- **Test**: Login as usera, navigate to resource, access `/dataset/potree/<resource_id>/edit`
- **Result**: Should have access to edit interface

### Test Case 2: userb (Regular User - No Permissions)

- **Expected**: No edit access
- **Test**: Login as userb, navigate to resource, try to access edit URL
- **Result**: Should be denied access or redirected

### Test Case 3: userc (Organization Editor)

- **Expected**: Edit access (if resource belongs to organization)
- **Test**: Login as userc, navigate to resource, access edit interface
- **Result**: Should have access to edit interface

### Test Case 4: Anonymous User

- **Expected**: No edit access
- **Test**: Logout, try to access edit URL directly
- **Result**: Should be redirected to login or denied access

## Step 8: Test Edit Functionality

For users with edit access, test:

1. **Load existing scene.json5** content in edit form
2. **Make modifications** to the JSON5 content
3. **Save changes** and verify they persist
4. **Invalid JSON5** - test error handling with malformed syntax
5. **Large files** - test with complex scene configurations

## Step 9: Test Concurrent Editing

1. **Open edit interface** as usera in one browser/tab
2. **Open edit interface** as userc in another browser/tab
3. **Make conflicting changes** and test save behavior
4. **Test session handling** during concurrent edits

## Expected Results Summary

| User Type              | Edit Access       | Notes                       |
| ---------------------- | ----------------- | --------------------------- |
| usera (Sysadmin/Owner) | ✅ Full Access    | Can edit any resource       |
| userb (Regular User)   | ❌ No Access      | Should be denied            |
| userc (Org Editor)     | ✅ Limited Access | Can edit org resources only |
| Anonymous              | ❌ No Access      | Must login first            |

## Files to Monitor During Testing

- `src/ckanext-potree/ckanext/potree/views.py:64-127` - Edit view permission checks
- `src/ckanext-potree/ckanext/potree/templates/potree/edit.html` - Edit interface
- CKAN logs for permission validation

## Cleanup After Testing

```bash
# Remove test users
ckan api action user_delete -c /srv/app/ckan.ini id=usera
ckan api action user_delete -c /srv/app/ckan.ini id=userb
ckan api action user_delete -c /srv/app/ckan.ini id=userc

# Remove test organization
ckan api action organization_delete -c /srv/app/ckan.ini id=test-org

# Re-enable OAuth in .env.dev.config if needed
```

## Notes

- Test results should be documented for issue #94
- Pay attention to error messages and user feedback
- Verify that unauthorized access attempts are properly logged
- Test both web interface and direct URL access scenarios
