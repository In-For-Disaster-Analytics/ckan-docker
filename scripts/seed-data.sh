#!/bin/bash
set -euo pipefail

# Usage: ./scripts/seed-data.sh <hostname> <username> <password>
# Example: ./scripts/seed-data.sh http://localhost:5000 myuser mypassword
#
# Creates a test organization, dataset, and uploads a dummy file.

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <hostname> <username> <password>"
    echo ""
    echo "Example:"
    echo "  $0 http://localhost:5000 myuser mypassword"
    exit 1
fi

HOSTNAME="$1"
USERNAME="$2"
PASSWORD="$3"
API="$HOSTNAME/api/action"

# Get JWT token from Tapis
echo "Obtaining JWT token for $USERNAME..."
JWT=$(curl -sf -H "Content-type: application/json" \
    -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"grant_type\": \"password\"}" \
    https://portals.tapis.io/v3/oauth2/tokens | jq -r '.result.access_token.access_token')

if [ -z "$JWT" ] || [ "$JWT" = "null" ]; then
    echo "Failed to obtain JWT token. Check your credentials."
    exit 1
fi
echo "Token obtained."

AUTH="Authorization: Bearer $JWT"

# Create organization
ORG_NAME="test-org-$(date +%s)"
echo ""
echo "Creating organization: $ORG_NAME..."
ORG_RESULT=$(curl -sf -X POST "$API/organization_create" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$ORG_NAME\",
        \"title\": \"Test Organization\",
        \"description\": \"Auto-generated test organization\"
    }")

ORG_ID=$(echo "$ORG_RESULT" | jq -r '.result.id')
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "Failed to create organization:"
    echo "$ORG_RESULT" | jq .
    exit 1
fi
echo "Organization created: $ORG_ID"

# Create dataset
DATASET_NAME="test-dataset-$(date +%s)"
echo ""
echo "Creating dataset: $DATASET_NAME..."
DATASET_RESULT=$(curl -sf -X POST "$API/package_create" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$DATASET_NAME\",
        \"title\": \"Test Dataset\",
        \"notes\": \"Auto-generated test dataset with a dummy file.\",
        \"owner_org\": \"$ORG_ID\"
    }")

DATASET_ID=$(echo "$DATASET_RESULT" | jq -r '.result.id')
if [ -z "$DATASET_ID" ] || [ "$DATASET_ID" = "null" ]; then
    echo "Failed to create dataset:"
    echo "$DATASET_RESULT" | jq .
    exit 1
fi
echo "Dataset created: $DATASET_ID"

# Create a dummy file
TMPFILE=$(mktemp /tmp/ckan-seed-XXXXXX.csv)
cat > "$TMPFILE" <<'CSV'
id,name,value,description
1,alpha,10.5,First test record
2,beta,20.3,Second test record
3,gamma,30.1,Third test record
4,delta,40.7,Fourth test record
5,epsilon,50.9,Fifth test record
CSV

echo ""
echo "Uploading dummy file..."
RESOURCE_RESULT=$(curl -sf -X POST "$API/resource_create" \
    -H "$AUTH" \
    -F "package_id=$DATASET_ID" \
    -F "name=test-data.csv" \
    -F "description=Sample CSV data file" \
    -F "format=CSV" \
    -F "upload=@$TMPFILE")

RESOURCE_ID=$(echo "$RESOURCE_RESULT" | jq -r '.result.id')
rm -f "$TMPFILE"

if [ -z "$RESOURCE_ID" ] || [ "$RESOURCE_ID" = "null" ]; then
    echo "Failed to upload resource:"
    echo "$RESOURCE_RESULT" | jq .
    exit 1
fi
echo "Resource uploaded: $RESOURCE_ID"

# Summary
echo ""
echo "==============================="
echo "Seed data created successfully!"
echo "==============================="
echo "Organization: $HOSTNAME/organization/$ORG_NAME"
echo "Dataset:      $HOSTNAME/dataset/$DATASET_NAME"
echo "Resource:     $HOSTNAME/dataset/$DATASET_NAME/resource/$RESOURCE_ID"
