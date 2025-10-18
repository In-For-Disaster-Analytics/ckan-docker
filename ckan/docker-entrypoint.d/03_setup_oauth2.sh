#!/bin/bash

if [[ $CKAN__PLUGINS == *"oauth2"* ]]; then
   # Datapusher settings have been configured in the .env file
   # Set API token if necessary
   ckan -c /srv/app/ckan.ini db upgrade -p oauth2
else
   echo "Not configuring DataPusher"
fi
