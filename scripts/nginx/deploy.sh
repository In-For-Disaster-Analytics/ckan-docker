#!/usr/bin/env bash
# Deploy the repo's nginx config (docs/nginx/) to this host.
#
# Run as root on the CKAN host, from the repo checkout:
#   scripts/nginx/deploy.sh --check   show what would change, touch nothing
#   scripts/nginx/deploy.sh           back up, install, validate, reload
#
# Safety: current files are backed up first; the config is validated with `nginx -t`
# before reload; if validation fails everything is restored and nginx is not reloaded.
# `reload` keeps existing connections open.
#
# The rate-limit zones used to be defined in /etc/nginx/nginx.conf. They now live in
# conf.d/00-ckan-rate-limits.conf, so this script comments out any ckan_* zone lines still
# present in nginx.conf (a zone defined twice is a config error). Nothing else in
# nginx.conf is touched.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_DIR/docs/nginx"
CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
MAIN_CONF="${NGINX_MAIN_CONF:-/etc/nginx/nginx.conf}"
NGINX_BIN="${NGINX_BIN:-nginx}"
RELOAD_CMD="${NGINX_RELOAD_CMD:-systemctl reload nginx}"
BACKUP_ROOT="${NGINX_BACKUP_DIR:-/root}"
FILES=(00-ckan-rate-limits.conf ckan-tacc-utexas.conf)
ZONE_RE='^[[:space:]]*limit_(req|conn)_zone[[:space:]].*zone=ckan_[a-z_]+:'

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ "$CHECK_ONLY" -eq 0 ] && [ "$(id -u)" -ne 0 ] && [ -z "${NGINX_ALLOW_NONROOT:-}" ]; then
  echo "Run as root (or use --check)." >&2
  exit 1
fi
for f in "${FILES[@]}"; do
  [ -f "$SRC/$f" ] || { echo "Missing $SRC/$f" >&2; exit 1; }
done

echo "== changes to $CONF_DIR =="
for f in "${FILES[@]}"; do
  if [ -f "$CONF_DIR/$f" ]; then
    if diff -q "$CONF_DIR/$f" "$SRC/$f" >/dev/null; then
      echo "-- $f: unchanged"
    else
      echo "-- $f: differs"; diff -u "$CONF_DIR/$f" "$SRC/$f" || true
    fi
  else
    echo "-- $f: NEW"
  fi
done
echo "== zone lines to move out of $MAIN_CONF =="
grep -nE "$ZONE_RE" "$MAIN_CONF" || echo "(none)"

[ "$CHECK_ONLY" -eq 1 ] && { echo; echo "--check: nothing changed."; exit 0; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$(mktemp -d "$BACKUP_ROOT/nginx-backup-$STAMP-XXXX")"
cp -a "$MAIN_CONF" "$BACKUP/nginx.conf"
for f in "${FILES[@]}"; do
  if [ -f "$CONF_DIR/$f" ]; then cp -a "$CONF_DIR/$f" "$BACKUP/$f"; else : > "$BACKUP/$f.absent"; fi
done
echo; echo "Backup: $BACKUP"

restore() {
  echo "Restoring previous configuration..." >&2
  cp -a "$BACKUP/nginx.conf" "$MAIN_CONF"
  for f in "${FILES[@]}"; do
    if [ -f "$BACKUP/$f" ]; then cp -a "$BACKUP/$f" "$CONF_DIR/$f"; else rm -f "$CONF_DIR/$f"; fi
  done
}

# Any failure from here on (copy, edit, validation, reload) puts the old files back.
trap restore ERR

for f in "${FILES[@]}"; do install -m 0644 "$SRC/$f" "$CONF_DIR/$f"; done
sed -i.deploy-bak -E "s@$ZONE_RE@# moved to conf.d/00-ckan-rate-limits.conf: &@" "$MAIN_CONF" && rm -f "$MAIN_CONF.deploy-bak"

if "$NGINX_BIN" -t; then
  $RELOAD_CMD
  echo "Reloaded. To undo: restore the files in $BACKUP, then '$NGINX_BIN -t && $RELOAD_CMD'."
else
  restore
  "$NGINX_BIN" -t || true
  echo "nginx -t failed; previous configuration restored, nginx not reloaded." >&2
  exit 1
fi
