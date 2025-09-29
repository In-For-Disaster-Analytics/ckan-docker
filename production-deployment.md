# Production Deployment Guide

This guide provides step-by-step instructions for deploying your application to a production environment. Follow these best practices to ensure a smooth and successful deployment.

The docker compose file for production is located at `/srv/ckan-tacc-images`

## How to start the application

### Prerequisites

Verify if the attached disk (corral) is mounted:

```
mount | grep corral
```

If the disk is not mounted, mount it using:

```
mount -a
```

### Start the application

Navigate to the directory containing the `docker-compose.yml` file:

```
cd /srv/ckan-tacc-images
docker compose up -d
```

This command will start all the necessary services defined in the `docker-compose.yml` file in detached mode.

Check the status of the services:

```
docker compose ps
```

You should see a list of services with their current status. Ensure that all services are running without errors.

## Check logs

```
docker compose logs -f
```

### Nginx - Reverse Proxy

Check status of nginx:

```
systemctl status nginx
```

If nginx is not running, start it with:

```
systemctl start nginx
```
