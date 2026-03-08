#!/bin/bash
# backup-db.sh - Create database dumps for CKAN and datastore
#
# Usage: backup-db.sh [OPTIONS] [output_directory]
#
# Produces two pg_dump custom-format files suitable for use with
# scripts/migration/migrate-db.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="docker-compose.dev.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Database defaults (overridden by env files)
POSTGRES_USER="${POSTGRES_USER:-postgres}"
CKAN_DB="${CKAN_DB:-ckandb}"
DATASTORE_DB="${DATASTORE_DB:-datastore}"

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<USAGE
Usage: backup-db.sh [OPTIONS] [output_directory]

Create database dumps of CKAN and datastore databases.
Produces pg_dump custom-format files compatible with migrate-db.sh.

Arguments:
  output_directory    Directory for backup files (default: ./backups)

Options:
  --compose-file FILE Use the specified Docker Compose file (default: docker-compose.dev.yml)
  -h, --help          Show this help message and exit

Examples:
  backup-db.sh
  backup-db.sh ./my-backups
  backup-db.sh --compose-file docker-compose.yml ./backups
USAGE
}

# =============================================================================
# Environment Loading
# =============================================================================

load_env() {
    local env_prefix="dev"

    if [[ "$COMPOSE_FILE" == *"dev"* ]]; then
        env_prefix="dev"
    else
        env_prefix="prod"
    fi

    local config_file="${PROJECT_DIR}/.env.${env_prefix}.config"
    local secrets_file="${PROJECT_DIR}/.env.${env_prefix}.secrets"

    for f in "$config_file" "$secrets_file"; do
        if [[ -f "$f" ]]; then
            while IFS='=' read -r key value; do
                if [[ "$key" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]]; then
                    export "$key=$value"
                fi
            done < <(grep -v '^\s*#' "$f" | grep -v '^\s*$')
        fi
    done

    # Re-apply defaults in case env files didn't set them
    POSTGRES_USER="${POSTGRES_USER:-postgres}"
    CKAN_DB="${CKAN_DB:-ckandb}"
    DATASTORE_DB="${DATASTORE_DB:-datastore}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

OUTPUT_DIR=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --compose-file)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: --compose-file requires a file argument" >&2
                    exit 1
                fi
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                echo ""
                usage
                exit 1
                ;;
            *)
                if [[ -z "$OUTPUT_DIR" ]]; then
                    OUTPUT_DIR="$1"
                else
                    echo "ERROR: Unexpected argument: $1" >&2
                    echo ""
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    OUTPUT_DIR="${OUTPUT_DIR:-./backups}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    cd "$PROJECT_DIR"
    load_env

    # Verify compose file exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo "ERROR: Compose file not found: $COMPOSE_FILE" >&2
        exit 1
    fi

    # Verify db service is running
    if ! docker compose -f "$COMPOSE_FILE" ps --format '{{.Service}}' 2>/dev/null | grep -q '^db$'; then
        echo "ERROR: 'db' service is not running. Start it with: docker compose -f $COMPOSE_FILE up -d db" >&2
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR"

    local ckan_file="ckan_db_backup_${TIMESTAMP}.dump"
    local ds_file="ckan_datastore_backup_${TIMESTAMP}.dump"
    local roles_file="postgres_roles_${TIMESTAMP}.sql"

    echo "Starting database backup..."
    echo "  Compose file: $COMPOSE_FILE"
    echo "  Output dir:   $OUTPUT_DIR"
    echo ""

    # Backup CKAN database
    echo "Backing up CKAN database ($CKAN_DB)..."
    docker compose -f "$COMPOSE_FILE" exec -T db \
        pg_dump -U "$POSTGRES_USER" -F c -b -f "/tmp/${ckan_file}" "$CKAN_DB"
    docker compose -f "$COMPOSE_FILE" cp "db:/tmp/${ckan_file}" "${OUTPUT_DIR}/${ckan_file}"
    docker compose -f "$COMPOSE_FILE" exec -T db rm -f "/tmp/${ckan_file}"

    # Backup datastore database
    echo "Backing up datastore database ($DATASTORE_DB)..."
    docker compose -f "$COMPOSE_FILE" exec -T db \
        pg_dump -U "$POSTGRES_USER" -F c -b -f "/tmp/${ds_file}" "$DATASTORE_DB"
    docker compose -f "$COMPOSE_FILE" cp "db:/tmp/${ds_file}" "${OUTPUT_DIR}/${ds_file}"
    docker compose -f "$COMPOSE_FILE" exec -T db rm -f "/tmp/${ds_file}"

    # Backup roles
    echo "Backing up PostgreSQL roles..."
    docker compose -f "$COMPOSE_FILE" exec -T db \
        pg_dumpall -U "$POSTGRES_USER" --roles-only > "${OUTPUT_DIR}/${roles_file}"

    echo ""
    echo "Backup complete!"
    echo "  ${OUTPUT_DIR}/${ckan_file}"
    echo "  ${OUTPUT_DIR}/${ds_file}"
    echo "  ${OUTPUT_DIR}/${roles_file}"
    echo ""
    echo "To migrate with these dumps:"
    echo "  ./scripts/migration/migrate-db.sh ${OUTPUT_DIR}/${ckan_file} ${OUTPUT_DIR}/${ds_file}"
}

main "$@"
