# Docker Compose setup for CKAN

## Install (build and run) CKAN plus dependencies

### Base mode

Use this if you are a maintainer and will not be making code changes to CKAN or to CKAN extensions

Copy the included `.env.example` and rename it to `.env`. Modify it depending on your own needs.

> [!WARNING]
> There is a sysadmin user created by default with the values defined in `CKAN_SYSADMIN_NAME` and `CKAN_SYSADMIN_PASSWORD` (`ckan_admin` and `test1234` by default). These must be changed before running this setup as a public CKAN instance.

To build the images:

    docker compose build

To start the containers:

    docker compose up

This will start up the containers in the current window. By default the containers will log direct to this window with each container
using a different colour. You could also use the -d "detach mode" option ie: `docker compose up -d` if you wished to use the current
window for something else.

At the end of the container start sequence there should be 6 containers running:

```bash
$ docker compose ps
NAME                       IMAGE                              COMMAND                  SERVICE      CREATED         STATUS                   PORTS
ckan-docker-ckan-1         ckan-docker-ckan                   "/srv/app/start_ckan…"   ckan         4 minutes ago   Up 3 minutes (healthy)   5000/tcp
ckan-docker-datapusher-1   ckan/ckan-base-datapusher:0.0.20   "sh -c 'uwsgi --plug…"   datapusher   4 minutes ago   Up 4 minutes (healthy)   8800/tcp
ckan-docker-db-1           ckan-docker-db                     "docker-entrypoint.s…"   db           4 minutes ago   Up 4 minutes (healthy)
ckan-docker-nginx-1        ckan-docker-nginx                  "/bin/sh -c 'openssl…"   nginx        4 minutes ago   Up 2 minutes             80/tcp, 0.0.0.0:8443->443/tcp
ckan-docker-redis-1        redis:6                            "docker-entrypoint.s…"   redis        4 minutes ago   Up 4 minutes (healthy)
ckan-docker-solr-1         ckan/ckan-solr:2.10-solr9          "docker-entrypoint.s…"   solr         4 minutes ago   Up 4 minutes (healthy)
```

After this step, CKAN should be running at `CKAN_SITE_URL` (by default https://localhost:8443)

### Manage users

To manage users, you can use the [CKAN API](https://docs.ckan.org/en/2.9/api/index.html).

```bash
ckan sysadmin add john_doe
```

### Filesystem permissions

The CKAN data is stored in the `ckan_storage` volume. The `ckan` user needs to have write access to this volume.

The ckan user is created with the `ckan` group.

````bash
docker-compose exec  ckan bash
ckan@dbdd4ea66995:~$ id
uid=503(ckan) gid=502(ckan-sys) groups=502(ckan-sys)
```

Set the correct permissions for the ckan user:

```bash
sudo chown -R 503:502 ckan_storage
```
````

### Development mode

To run CKAN in development mode, use the `docker-compose.dev.yml` file.

Copy the included `.env.dev.example` and rename it to `.env`.

```bash
docker compose -f docker-compose.dev.yml up
```

To edit the theme, you can edit the files in the `src/ckanext-tacc_theme` directory.
