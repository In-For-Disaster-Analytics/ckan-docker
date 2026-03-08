FROM postgres:12-alpine

# Install PostGIS extension libraries (required for spatial data support)
RUN apk add --no-cache postgis

# Include extra setup scripts (eg datastore)
COPY --chown=postgres:postgres docker-entrypoint-initdb.d /docker-entrypoint-initdb.d
