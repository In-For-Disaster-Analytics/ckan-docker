#!/bin/bash

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 username password"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

# Get JWT token
echo "Getting JWT token..."
JWT=$(curl -s -H "Content-type: application/json" \
    -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"grant_type\": \"password\" }" \
    https://portals.tapis.io/v3/oauth2/tokens | jq -r '.result.access_token.access_token')

if [ -z "$JWT" ] || [ "$JWT" = "null" ]; then
    echo "Failed to get JWT token. Please check your credentials."
    exit 1
fi

# List all clients
echo "Listing all OAuth2 clients..."

RESPONSE=$(curl -s -H "X-Tapis-Token: $JWT" \
    https://portals.tapis.io/v3/oauth2/clients)

echo "Response:"
echo $RESPONSE | jq '.'
