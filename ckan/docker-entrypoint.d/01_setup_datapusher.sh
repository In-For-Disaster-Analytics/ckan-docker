#!/bin/bash

if [[ $CKAN__PLUGINS == *"datapusher"* ]]; then
   # Datapusher settings have been configured in the .env file
   # Set API token if necessary
   if [ -z "$CKAN__DATAPUSHER__API_TOKEN" ] ; then
      echo "Set up ckan.datapusher.api_token in the CKAN config file"
      DATAPUSHER_USER="${CKAN_SYSADMIN_NAME:-admin}"
      DATAPUSHER_TOKEN="$(ckan -c $CKAN_INI user token add "$DATAPUSHER_USER" datapusher | tail -n 1 | tr -d '\t')"
      if [ -z "$DATAPUSHER_TOKEN" ] ; then
         echo "Unable to create datapusher API token for user '$DATAPUSHER_USER'"
         exit 1
      fi
      ckan config-tool $CKAN_INI "ckan.datapusher.api_token=$DATAPUSHER_TOKEN"
   fi
else
   echo "Not configuring DataPusher"
fi
