#!/bin/bash
# migrate-db.sh - Migrate a CKAN 2.9 database dump into a running CKAN 2.11 environment
#
# Usage: migrate-db.sh [OPTIONS] <ckan_dump> <datastore_dump>
#
# Handles PostGIS setup, dump restoration, duplicate email detection,
# Alembic schema upgrades, Solr reindexing, and post-migration validation.

set -euo pipefail

# =============================================================================
# Global Variables
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CURRENT_STEP=""
STEP_START_TIME=0
LOG_FILE=""
COMPOSE_FILE="docker-compose.dev.yml"
CKAN_SERVICE=""
CKAN_INI="/srv/app/ckan.ini"
FORCE=false

# Database defaults (overridden by env files)
POSTGRES_USER="${POSTGRES_USER:-postgres}"
CKAN_DB="${CKAN_DB:-ckandb}"
DATASTORE_DB="${DATASTORE_DB:-datastore}"
CKAN_DB_USER="${CKAN_DB_USER:-ckandbuser}"

# Positional arguments
CKAN_DUMP=""
DATASTORE_DUMP=""

# =============================================================================
# Color Support
# =============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
else
    RED=''
    YELLOW=''
    GREEN=''
    NC=''
fi

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    local full_timestamp
    full_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] $1"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[${full_timestamp}] INFO: $1" >> "$LOG_FILE"
    fi
}

log_warn() {
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    local full_timestamp
    full_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${YELLOW}[${timestamp}] WARNING: $1${NC}"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[${full_timestamp}] WARN: $1" >> "$LOG_FILE"
    fi
}

log_error() {
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    local full_timestamp
    full_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${RED}[${timestamp}] ERROR: $1${NC}" >&2
    if [[ -n "$LOG_FILE" ]]; then
        echo "[${full_timestamp}] ERROR: $1" >> "$LOG_FILE"
    fi
}

log_detail() {
    if [[ -n "$LOG_FILE" ]]; then
        local full_timestamp
        full_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[${full_timestamp}] DETAIL: $1" >> "$LOG_FILE"
    fi
}

# =============================================================================
# Step Runner
# =============================================================================

run_step() {
    local step_name="$1"
    local step_func="$2"
    CURRENT_STEP="$step_name"
    STEP_START_TIME=$(date +%s)

    printf "[%s] %s... " "$(date +"%H:%M:%S")" "$step_name"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: Starting: $step_name" >> "$LOG_FILE"
    fi

    $step_func

    local elapsed=$(( $(date +%s) - STEP_START_TIME ))
    echo -e "${GREEN}done${NC} (${elapsed}s)"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: $step_name... done (${elapsed}s)" >> "$LOG_FILE"
    fi
    CURRENT_STEP=""
}

# =============================================================================
# Trap Handler
# =============================================================================

cleanup_on_failure() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -n "$CURRENT_STEP" ]]; then
        echo ""
        log_error "FAILED at step: $CURRENT_STEP (exit code: $exit_code)"
        if [[ -n "$LOG_FILE" ]]; then
            log_error "Check log file for details: $LOG_FILE"
        fi
        print_recovery_instructions "$CURRENT_STEP"
    fi
}
trap cleanup_on_failure EXIT

print_recovery_instructions() {
    local step="$1"
    echo ""
    echo "=========================================="
    echo "RECOVERY INSTRUCTIONS"
    echo "=========================================="
    case "$step" in
        "Pre-flight checks")
            echo "Fix the reported issue and re-run the migration script."
            ;;
        "Schema validation")
            echo "The source dump does not contain the expected CKAN 2.9 schema."
            echo "Verify the dump file was exported from a CKAN 2.9 instance."
            echo "If the dump is from a different CKAN version, it cannot be"
            echo "migrated with this script."
            ;;
        "Pre-migration backup")
            echo "Backup failed. No data has been modified."
            echo "Check disk space and database connectivity, then re-run."
            ;;
        "Stop services")
            echo "Could not stop CKAN/DataPusher services."
            echo "Manually stop them: docker compose -f $COMPOSE_FILE stop $CKAN_SERVICE datapusher"
            echo "Then re-run the migration script."
            ;;
        "Restore CKAN database")
            echo "CKAN database restore failed."
            echo "The previous database may have been dropped."
            echo "If you have a pre-migration backup, restore it first."
            echo "Then fix the issue and re-run."
            ;;
        "Restore datastore database")
            echo "Datastore restore failed."
            echo "The CKAN database was restored successfully."
            echo "Fix the issue and re-run (use --force to overwrite)."
            ;;
        "Duplicate email check")
            echo "Duplicate emails were detected in the restored database."
            echo "The database has been left in place for inspection."
            echo "Fix duplicates using the SQL commands shown above."
            echo "Then re-run the migration script with --force."
            ;;
        "Start CKAN")
            echo "Could not start CKAN service."
            echo "Check: docker compose -f $COMPOSE_FILE logs $CKAN_SERVICE"
            echo "Fix the issue and restart manually:"
            echo "  docker compose -f $COMPOSE_FILE up -d $CKAN_SERVICE"
            echo "Then run the remaining migration steps manually:"
            echo "  docker compose -f $COMPOSE_FILE exec $CKAN_SERVICE ckan db upgrade"
            ;;
        "Schema migration")
            echo "Alembic schema migration failed."
            echo "Check the log file for the specific revision that failed."
            echo "Common fix: resolve the issue, then run:"
            echo "  docker compose -f $COMPOSE_FILE exec $CKAN_SERVICE ckan db upgrade"
            ;;
        "Datastore upgrade")
            echo "Datastore data dictionary migration failed."
            echo "The schema migration completed successfully."
            echo "Fix the issue and run:"
            echo "  docker compose -f $COMPOSE_FILE exec $CKAN_SERVICE ckan datastore upgrade"
            ;;
        "Datastore permissions")
            echo "Failed to set datastore permissions."
            echo "Run manually:"
            echo "  docker compose -f $COMPOSE_FILE exec $CKAN_SERVICE ckan datastore set-permissions | \\"
            echo "    docker compose -f $COMPOSE_FILE exec -T db psql -U $POSTGRES_USER"
            ;;
        "Search index rebuild")
            echo "Solr search index rebuild failed."
            echo "The database migration completed successfully."
            echo "Run manually:"
            echo "  docker compose -f $COMPOSE_FILE exec $CKAN_SERVICE ckan search-index rebuild"
            ;;
        "Start DataPusher")
            echo "Could not start DataPusher."
            echo "The migration is otherwise complete."
            echo "Start manually: docker compose -f $COMPOSE_FILE up -d datapusher"
            ;;
        "Validation")
            echo "Post-migration validation encountered an error."
            echo "The migration itself completed. Check results manually."
            ;;
        *)
            echo "An unexpected error occurred during: $step"
            echo "Check the log file for details and re-run if appropriate."
            ;;
    esac
    echo "=========================================="
}

# =============================================================================
# Helper Functions
# =============================================================================

dc_exec() {
    docker compose -f "$COMPOSE_FILE" exec -T "$@"
}

run_sql() {
    local db_name="$1"
    local sql="$2"
    dc_exec db psql -U "$POSTGRES_USER" -d "$db_name" -t -A -c "$sql"
}

run_ckan() {
    dc_exec "$CKAN_SERVICE" ckan "$@"
}

detect_ckan_service() {
    if grep -q "ckan-dev:" "$COMPOSE_FILE" 2>/dev/null; then
        CKAN_SERVICE="ckan-dev"
    else
        CKAN_SERVICE="ckan"
    fi
    log_detail "Detected CKAN service name: $CKAN_SERVICE"
}

# =============================================================================
# Argument Parsing
# =============================================================================

usage() {
    cat <<USAGE
Usage: migrate-db.sh [OPTIONS] <ckan_dump> <datastore_dump>

Migrate a CKAN 2.9 database dump into a running CKAN 2.11 environment.

The script automatically validates that the source dump contains a CKAN 2.9
schema (Alembic revision ccd38ad5fced) before proceeding with migration.

Arguments:
  ckan_dump           Path to the CKAN database dump file (pg_dump custom format)
  datastore_dump      Path to the datastore database dump file (pg_dump custom format)

Options:
  --force             Overwrite existing databases without prompting
  --compose-file FILE Use the specified Docker Compose file (default: docker-compose.dev.yml)
  -h, --help          Show this help message and exit

Examples:
  migrate-db.sh backups/ckan.dump backups/datastore.dump
  migrate-db.sh --force --compose-file docker-compose.yml ckan.dump datastore.dump
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --compose-file)
                if [[ -z "${2:-}" ]]; then
                    log_error "--compose-file requires a file argument"
                    exit 1
                fi
                COMPOSE_FILE="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
            *)
                if [[ -z "$CKAN_DUMP" ]]; then
                    CKAN_DUMP="$1"
                elif [[ -z "$DATASTORE_DUMP" ]]; then
                    DATASTORE_DUMP="$1"
                else
                    log_error "Unexpected argument: $1"
                    echo ""
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$CKAN_DUMP" || -z "$DATASTORE_DUMP" ]]; then
        log_error "Missing required arguments: <ckan_dump> and <datastore_dump>"
        echo ""
        usage
        exit 1
    fi
}

# =============================================================================
# Environment Loading
# =============================================================================

load_env() {
    local env_prefix="dev"

    # Detect env prefix from compose file name
    if [[ "$COMPOSE_FILE" == *"dev"* ]]; then
        env_prefix="dev"
    else
        env_prefix="prod"
    fi

    local config_file="${PROJECT_DIR}/.env.${env_prefix}.config"
    local secrets_file="${PROJECT_DIR}/.env.${env_prefix}.secrets"

    if [[ -f "$config_file" ]]; then
        log_detail "Loading config from: $config_file"
        # Extract only simple KEY=VALUE lines (no spaces in key, skip comments)
        # Handles env files with spaces around '=' and multiline values
        while IFS='=' read -r key value; do
            # Skip empty keys or keys with invalid chars
            if [[ "$key" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]]; then
                export "$key=$value"
            fi
        done < <(grep -E '^[A-Za-z_][A-Za-z_0-9]*\s*=' "$config_file" | sed 's/\s*=\s*/=/')
    else
        log_warn "Config file not found: $config_file (using defaults)"
    fi

    if [[ -f "$secrets_file" ]]; then
        log_detail "Loading secrets from: $secrets_file"
        while IFS='=' read -r key value; do
            if [[ "$key" =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]]; then
                export "$key=$value"
            fi
        done < <(grep -E '^[A-Za-z_][A-Za-z_0-9]*\s*=' "$secrets_file" | sed 's/\s*=\s*/=/')
    else
        log_warn "Secrets file not found: $secrets_file (using defaults)"
    fi

    # Set defaults
    POSTGRES_USER="${POSTGRES_USER:-postgres}"
    CKAN_DB="${CKAN_DB:-ckandb}"
    DATASTORE_DB="${DATASTORE_DB:-datastore}"
    CKAN_DB_USER="${CKAN_DB_USER:-ckandbuser}"

    log_detail "Database config: POSTGRES_USER=$POSTGRES_USER, CKAN_DB=$CKAN_DB, DATASTORE_DB=$DATASTORE_DB"
}

# =============================================================================
# Pre-flight Validation Functions
# =============================================================================

validate_dump_file() {
    local dump_file="$1"
    local label="$2"

    if [[ ! -f "$dump_file" ]]; then
        log_error "File not found: $dump_file ($label)"
        return 1
    fi

    # pg_restore -l lists the TOC of a custom-format archive
    # It exits non-zero if the file is not a valid archive
    if ! pg_restore -l "$dump_file" > /dev/null 2>&1; then
        log_error "Not a valid pg_dump custom format file: $dump_file ($label)"
        log_error "Ensure the file was created with: pg_dump -Fc"
        return 1
    fi

    log_detail "Validated dump file: $dump_file ($label)"
    return 0
}

check_pg_version() {
    local dump_file="$1"

    # Extract pg_dump version from the dump TOC header
    local dump_version
    dump_version=$(pg_restore -l "$dump_file" 2>/dev/null | grep -i "pg_dump version" | head -1 | sed 's/.*pg_dump version: *//' || true)

    if [[ -z "$dump_version" ]]; then
        log_warn "Could not determine pg_dump version from dump file"
        return 0
    fi

    # Get target PostgreSQL version
    local target_version
    target_version=$(dc_exec db psql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)

    if [[ -z "$target_version" ]]; then
        log_warn "Could not determine target PostgreSQL version"
        return 0
    fi

    # Extract major versions for comparison
    local dump_major
    dump_major=$(echo "$dump_version" | grep -oE '^[0-9]+')
    local target_major
    target_major=$(echo "$target_version" | grep -oE '^[0-9]+')

    if [[ -n "$dump_major" && -n "$target_major" ]]; then
        if (( dump_major > target_major )); then
            log_warn "PostgreSQL version mismatch: dump created with pg_dump $dump_version, target is PostgreSQL $target_version"
            log_warn "Restoring a dump from a newer PostgreSQL version may cause issues"
        else
            log_detail "PostgreSQL version check passed: dump=$dump_version, target=$target_version"
        fi
    fi

    return 0
}

check_services() {
    local services_to_check=("db" "solr" "$CKAN_SERVICE")

    for service in "${services_to_check[@]}"; do
        local state
        state=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' "$service" 2>/dev/null || true)

        if [[ -z "$state" ]]; then
            log_error "Service '$service' is not found in $COMPOSE_FILE"
            log_error "Run: docker compose -f $COMPOSE_FILE up -d"
            return 1
        fi

        if [[ "$state" != "running" ]]; then
            log_error "Service '$service' is not running (state: $state)"
            log_error "Run: docker compose -f $COMPOSE_FILE up -d $service"
            return 1
        fi

        log_detail "Service '$service' is running"
    done

    return 0
}

validate_schema_version() {
    local dump_file="$1"
    local expected_revision="ccd38ad5fced"  # CKAN 2.9 HEAD (migration 100)

    # Known post-2.9 revisions that indicate the dump is already partially/fully migrated
    local post29_revisions=(
        "d111f446733b"  # 2.10 migration 101 - Add last_active column
        "ff13667243ed"  # 2.10 migration 102 - Unique email index
        "353aaf2701f0"  # 2.10 migration 103 - Add plugin_data to package
        "9f33a0280c51"  # 2.11 migration 104 - Resource view index
        "4a5e3465beb6"  # 2.11 migration 105 - Autogenerate sync (HEAD)
    )

    # Check if alembic_version table exists in the dump TOC
    if ! pg_restore -l "$dump_file" 2>/dev/null | grep -q "alembic_version"; then
        log_warn "No alembic_version table found in dump. Cannot verify schema version. Proceeding anyway."
        return 0
    fi

    # Extract alembic_version data from dump (COPY format)
    local version_output
    version_output=$(pg_restore --data-only --table=alembic_version \
        -f /dev/stdout "$dump_file" 2>/dev/null)

    # Parse the version_num from COPY format:
    #   COPY public.alembic_version (version_num) FROM stdin;
    #   ccd38ad5fced
    #   \.
    local actual_revision
    actual_revision=$(echo "$version_output" | grep -A1 "^COPY.*alembic_version" | tail -1 | tr -d '[:space:]')

    if [[ -z "$actual_revision" ]]; then
        log_warn "Could not extract schema version from dump. Proceeding anyway."
        return 0
    fi

    # Check for expected CKAN 2.9 revision
    if [[ "$actual_revision" == "$expected_revision" ]]; then
        log_info "Schema version verified: $actual_revision (CKAN 2.9)"
        return 0
    fi

    # Check for known post-2.9 revisions (already migrated)
    for rev in "${post29_revisions[@]}"; do
        if [[ "$actual_revision" == "$rev" ]]; then
            log_error "Schema version mismatch!"
            log_error "  Found:    $actual_revision (post-2.9 revision)"
            log_error "  Expected: $expected_revision (CKAN 2.9)"
            log_error "This dump appears to be already partially or fully migrated beyond CKAN 2.9."
            log_error "Migration 101+ revisions indicate CKAN 2.10 or 2.11 schema changes are present."
            log_error "This script expects a CKAN 2.9 database dump."
            return 1
        fi
    done

    # Unknown revision -- warn but proceed (may be an older 2.9.x minor release)
    log_warn "Unrecognized schema revision: $actual_revision"
    log_warn "Expected $expected_revision (CKAN 2.9 HEAD). This may be an older 2.9.x release."
    log_warn "Proceeding with migration -- CKAN db upgrade will apply any missing migrations."
    return 0
}

check_existing_databases() {
    local existing_dbs=""

    # Check if CKAN database exists
    local ckan_exists
    ckan_exists=$(dc_exec db psql -U "$POSTGRES_USER" -t -A -c \
        "SELECT 1 FROM pg_database WHERE datname = '$CKAN_DB';" 2>/dev/null || true)

    if [[ "$ckan_exists" == "1" ]]; then
        existing_dbs="$CKAN_DB"
    fi

    # Check if datastore database exists
    local ds_exists
    ds_exists=$(dc_exec db psql -U "$POSTGRES_USER" -t -A -c \
        "SELECT 1 FROM pg_database WHERE datname = '$DATASTORE_DB';" 2>/dev/null || true)

    if [[ "$ds_exists" == "1" ]]; then
        if [[ -n "$existing_dbs" ]]; then
            existing_dbs="$existing_dbs, $DATASTORE_DB"
        else
            existing_dbs="$DATASTORE_DB"
        fi
    fi

    if [[ -n "$existing_dbs" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_warn "Existing databases will be overwritten: $existing_dbs"
        else
            log_error "Existing databases found: $existing_dbs"
            log_error "Use --force to overwrite existing databases"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# Pre-flight Orchestrator
# =============================================================================

run_preflight_checks() {
    validate_dump_file "$CKAN_DUMP" "CKAN dump"
    validate_dump_file "$DATASTORE_DUMP" "Datastore dump"
    check_services
    check_pg_version "$CKAN_DUMP"
    validate_schema_version "$CKAN_DUMP"
    check_existing_databases
}

# =============================================================================
# Migration Pipeline Steps
# =============================================================================

# --- SAFE-01: Pre-migration backup ---
step_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir
    backup_dir=$(cd "$(dirname "$CKAN_DUMP")" 2>/dev/null && pwd || echo ".")

    # Backup CKAN database
    log_detail "Backing up $CKAN_DB to /tmp/pre_migration_${CKAN_DB}_${timestamp}.dump"
    dc_exec db pg_dump -U "$POSTGRES_USER" -F c -b \
        -f "/tmp/pre_migration_${CKAN_DB}_${timestamp}.dump" "$CKAN_DB" 2>> "$LOG_FILE"
    docker compose -f "$COMPOSE_FILE" cp \
        "db:/tmp/pre_migration_${CKAN_DB}_${timestamp}.dump" \
        "${backup_dir}/pre_migration_${CKAN_DB}_${timestamp}.dump"

    # Backup datastore database
    log_detail "Backing up $DATASTORE_DB to /tmp/pre_migration_${DATASTORE_DB}_${timestamp}.dump"
    dc_exec db pg_dump -U "$POSTGRES_USER" -F c -b \
        -f "/tmp/pre_migration_${DATASTORE_DB}_${timestamp}.dump" "$DATASTORE_DB" 2>> "$LOG_FILE"
    docker compose -f "$COMPOSE_FILE" cp \
        "db:/tmp/pre_migration_${DATASTORE_DB}_${timestamp}.dump" \
        "${backup_dir}/pre_migration_${DATASTORE_DB}_${timestamp}.dump"

    # Clean up container tmp files
    dc_exec db rm -f \
        "/tmp/pre_migration_${CKAN_DB}_${timestamp}.dump" \
        "/tmp/pre_migration_${DATASTORE_DB}_${timestamp}.dump"

    log_detail "Pre-migration backups saved to: $backup_dir"
    log_detail "  - pre_migration_${CKAN_DB}_${timestamp}.dump"
    log_detail "  - pre_migration_${DATASTORE_DB}_${timestamp}.dump"
}

# --- MIG-07 part 1: Stop services ---
step_stop_services() {
    docker compose -f "$COMPOSE_FILE" stop "$CKAN_SERVICE" datapusher 2>> "$LOG_FILE"
    # Allow connections to drain
    sleep 2
    log_detail "Stopped $CKAN_SERVICE and datapusher"
}

# --- MIG-01: Restore CKAN database ---
step_restore_ckan() {
    local dump_filename
    dump_filename=$(basename "$CKAN_DUMP")

    # Copy dump into db container
    docker compose -f "$COMPOSE_FILE" cp "$CKAN_DUMP" "db:/tmp/${dump_filename}" 2>> "$LOG_FILE"

    # Drop and recreate CKAN database
    dc_exec db dropdb -U "$POSTGRES_USER" --if-exists "$CKAN_DB" 2>> "$LOG_FILE"
    dc_exec db createdb -U "$POSTGRES_USER" -O "$CKAN_DB_USER" "$CKAN_DB" -E utf-8 2>> "$LOG_FILE"

    # Create PostGIS extension before restore
    run_sql "$CKAN_DB" "CREATE EXTENSION IF NOT EXISTS postgis;" >> "$LOG_FILE" 2>&1

    # Restore dump -- capture exit code and check for real errors vs warnings
    local restore_output
    local restore_exit=0
    restore_output=$(dc_exec db pg_restore -U "$POSTGRES_USER" -d "$CKAN_DB" -v "/tmp/${dump_filename}" 2>&1) || restore_exit=$?

    # Log full output
    echo "$restore_output" >> "$LOG_FILE"

    if [[ $restore_exit -ne 0 ]]; then
        # Check if there are real ERRORs (not just warnings)
        if echo "$restore_output" | grep -qi "^pg_restore.*ERROR\|^ERROR"; then
            log_error "pg_restore encountered errors during CKAN database restore"
            log_detail "Exit code: $restore_exit"
            # Clean up container tmp file
            dc_exec db rm -f "/tmp/${dump_filename}" 2>/dev/null || true
            return 1
        else
            log_detail "pg_restore returned exit code $restore_exit but no critical errors found (likely warnings)"
        fi
    fi

    # Clean up container tmp file
    dc_exec db rm -f "/tmp/${dump_filename}" 2>> "$LOG_FILE"
    log_detail "CKAN database restored successfully"
}

# --- MIG-02: Restore datastore database ---
step_restore_datastore() {
    local dump_filename
    dump_filename=$(basename "$DATASTORE_DUMP")

    # Copy dump into db container
    docker compose -f "$COMPOSE_FILE" cp "$DATASTORE_DUMP" "db:/tmp/${dump_filename}" 2>> "$LOG_FILE"

    # Drop and recreate datastore database
    dc_exec db dropdb -U "$POSTGRES_USER" --if-exists "$DATASTORE_DB" 2>> "$LOG_FILE"
    dc_exec db createdb -U "$POSTGRES_USER" -O "$CKAN_DB_USER" "$DATASTORE_DB" -E utf-8 2>> "$LOG_FILE"

    # Restore dump -- same error handling as CKAN restore
    local restore_output
    local restore_exit=0
    restore_output=$(dc_exec db pg_restore -U "$POSTGRES_USER" -d "$DATASTORE_DB" -v "/tmp/${dump_filename}" 2>&1) || restore_exit=$?

    # Log full output
    echo "$restore_output" >> "$LOG_FILE"

    if [[ $restore_exit -ne 0 ]]; then
        if echo "$restore_output" | grep -qi "^pg_restore.*ERROR\|^ERROR"; then
            log_error "pg_restore encountered errors during datastore restore"
            log_detail "Exit code: $restore_exit"
            dc_exec db rm -f "/tmp/${dump_filename}" 2>/dev/null || true
            return 1
        else
            log_detail "pg_restore returned exit code $restore_exit but no critical errors found (likely warnings)"
        fi
    fi

    # Clean up container tmp file
    dc_exec db rm -f "/tmp/${dump_filename}" 2>> "$LOG_FILE"
    log_detail "Datastore database restored successfully"
}

# --- SAFE-04: Detect duplicate emails ---
step_check_duplicate_emails() {
    local result
    result=$(run_sql "$CKAN_DB" "
        SELECT email, array_agg(name ORDER BY name) AS usernames, count(*)
        FROM \"user\"
        WHERE state = 'active' AND email IS NOT NULL AND email != ''
        GROUP BY email
        HAVING count(*) > 1
        ORDER BY count(*) DESC;
    " 2>/dev/null) || true

    log_detail "Duplicate email query result: ${result:-<none>}"

    if [[ -n "$result" ]]; then
        echo ""
        echo "=========================================="
        echo "DUPLICATE EMAILS DETECTED"
        echo "=========================================="
        echo ""
        echo "The following email addresses are shared by multiple active users."
        echo "CKAN 2.10+ requires unique emails per active user."
        echo ""
        echo "  email | usernames | count"
        echo "  ------|-----------|------"
        echo "$result" | while IFS='|' read -r email usernames count; do
            echo "  ${email} | ${usernames} | ${count}"
        done
        echo ""
        echo "Option 1: Change duplicate emails (recommended)"
        echo "  Connect to the database and run:"
        echo ""
        run_sql "$CKAN_DB" "
            SELECT '  UPDATE \"user\" SET email = ''' || name || '+duplicate@example.com'' WHERE name = ''' || name || ''';'
            FROM \"user\"
            WHERE state = 'active' AND email IN (
                SELECT email FROM \"user\"
                WHERE state = 'active' AND email IS NOT NULL AND email != ''
                GROUP BY email HAVING count(*) > 1
            )
            ORDER BY email, name;
        " 2>/dev/null || true
        echo ""
        echo "Option 2: Deactivate duplicate accounts (keep newest per email)"
        echo "  Connect to the database and run:"
        echo ""
        run_sql "$CKAN_DB" "
            SELECT '  UPDATE \"user\" SET state = ''deleted'' WHERE name = ''' || name || ''';'
            FROM (
                SELECT name, email, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created DESC) as rn
                FROM \"user\"
                WHERE state = 'active' AND email IN (
                    SELECT email FROM \"user\"
                    WHERE state = 'active' AND email IS NOT NULL AND email != ''
                    GROUP BY email HAVING count(*) > 1
                )
            ) sub
            WHERE rn > 1
            ORDER BY email, name;
        " 2>/dev/null || true
        echo ""
        echo "Database left in place for inspection. Fix duplicates, then re-run migration."
        echo "=========================================="
        return 1
    fi

    log_detail "No duplicate emails found"
}

# --- MIG-07 part 2a: Start CKAN ---
step_start_ckan() {
    docker compose -f "$COMPOSE_FILE" start "$CKAN_SERVICE" 2>> "$LOG_FILE"

    # Wait for CKAN to be healthy (timeout 120s)
    local timeout=120
    local elapsed=0
    local interval=5

    while (( elapsed < timeout )); do
        local health
        health=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' "$CKAN_SERVICE" 2>/dev/null || true)
        log_detail "CKAN health check (${elapsed}s): state=$health"

        if [[ "$health" == "running" ]]; then
            # Also check if CKAN can respond (give it a moment to fully initialize)
            if dc_exec "$CKAN_SERVICE" ckan -c "$CKAN_INI" status 2>/dev/null; then
                log_detail "CKAN is running and responsive"
                return 0
            fi
        fi

        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    # If we got here but service is running, proceed anyway (status command may not exist)
    local final_state
    final_state=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.State}}' "$CKAN_SERVICE" 2>/dev/null || true)
    if [[ "$final_state" == "running" ]]; then
        log_detail "CKAN is running (status command may not be available)"
        return 0
    fi

    log_error "CKAN failed to start within ${timeout}s"
    return 1
}

# --- MIG-03: Schema migration (Alembic) ---
step_db_upgrade() {
    local output
    output=$(run_ckan -c "$CKAN_INI" db upgrade 2>&1) || {
        echo "$output" >> "$LOG_FILE"
        log_error "ckan db upgrade failed"
        return 1
    }
    echo "$output" >> "$LOG_FILE"
    log_detail "Schema migration completed successfully"
}

# --- MIG-04: Datastore upgrade ---
step_datastore_upgrade() {
    local output
    output=$(run_ckan -c "$CKAN_INI" datastore upgrade 2>&1) || {
        echo "$output" >> "$LOG_FILE"
        log_error "ckan datastore upgrade failed"
        return 1
    }
    echo "$output" >> "$LOG_FILE"
    log_detail "Datastore upgrade completed successfully"
}

# --- MIG-05: Datastore permissions ---
step_datastore_permissions() {
    dc_exec "$CKAN_SERVICE" ckan -c "$CKAN_INI" datastore set-permissions 2>> "$LOG_FILE" | \
        dc_exec db psql -U "$POSTGRES_USER" --set ON_ERROR_STOP=1 >> "$LOG_FILE" 2>&1
    log_detail "Datastore permissions applied successfully"
}

# --- MIG-06: Search index rebuild ---
step_search_reindex() {
    local output
    output=$(run_ckan -c "$CKAN_INI" search-index rebuild 2>&1) || {
        echo "$output" >> "$LOG_FILE"
        log_error "search-index rebuild failed"
        return 1
    }
    echo "$output" >> "$LOG_FILE"

    # Show summary on terminal
    local reindexed_count
    reindexed_count=$(echo "$output" | grep -c "Indexed" || true)
    if [[ "$reindexed_count" -gt 0 ]]; then
        log_detail "Reindexed $reindexed_count datasets"
    fi
    log_detail "Search index rebuild completed"
}

# --- MIG-07 part 2b: Start DataPusher ---
step_start_datapusher() {
    docker compose -f "$COMPOSE_FILE" start datapusher 2>> "$LOG_FILE"
    log_detail "DataPusher started"
}

# --- VAL-01: Post-migration validation ---
step_validation() {
    echo ""
    echo "=========================================="
    echo "POST-MIGRATION VALIDATION"
    echo "=========================================="

    # Dataset count
    local dataset_count
    dataset_count=$(run_sql "$CKAN_DB" "SELECT count(*) FROM package WHERE state = 'active';" 2>/dev/null) || dataset_count="ERROR"
    echo "  Datasets:      ${dataset_count} active"
    log_detail "Validation - Datasets: $dataset_count"

    # User count
    local user_count
    user_count=$(run_sql "$CKAN_DB" "SELECT count(*) FROM \"user\" WHERE state = 'active';" 2>/dev/null) || user_count="ERROR"
    echo "  Users:         ${user_count} active"
    log_detail "Validation - Users: $user_count"

    # Organization count
    local org_count
    org_count=$(run_sql "$CKAN_DB" "SELECT count(*) FROM \"group\" WHERE type = 'organization' AND state = 'active';" 2>/dev/null) || org_count="ERROR"
    echo "  Organizations: ${org_count} active"
    log_detail "Validation - Organizations: $org_count"

    # Resource count
    local resource_count
    resource_count=$(run_sql "$CKAN_DB" "SELECT count(*) FROM resource WHERE state = 'active';" 2>/dev/null) || resource_count="ERROR"
    echo "  Resources:     ${resource_count} active"
    log_detail "Validation - Resources: $resource_count"

    # Solr search index check
    local search_result
    search_result=$(run_ckan -c "$CKAN_INI" search-index check 2>&1 | tail -3) || search_result="ERROR checking search index"
    echo "  Search index:  ${search_result}"
    log_detail "Validation - Search index: $search_result"

    # Datastore tables
    local ds_tables
    ds_tables=$(run_sql "$DATASTORE_DB" "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null) || ds_tables="ERROR"
    echo "  Datastore:     ${ds_tables} public tables"
    log_detail "Validation - Datastore tables: $ds_tables"

    # Spatial extents (may not exist)
    local spatial_count
    spatial_count=$(run_sql "$CKAN_DB" "SELECT count(*) FROM package_extent;" 2>/dev/null) || spatial_count="N/A (table not found)"
    echo "  Spatial:       ${spatial_count} extents"
    log_detail "Validation - Spatial extents: $spatial_count"

    echo "=========================================="
    echo "Migration complete. Review validation results above."
    echo "=========================================="
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Initialize log file in the same directory as the CKAN dump
    local dump_dir
    dump_dir=$(cd "$(dirname "$CKAN_DUMP")" 2>/dev/null && pwd || echo ".")
    LOG_FILE="${dump_dir}/migration-$(date +%Y-%m-%d_%H%M%S).log"
    if ! touch "$LOG_FILE" 2>/dev/null; then
        # Fall back to current directory if dump directory is not writable/accessible
        LOG_FILE="./migration-$(date +%Y-%m-%d_%H%M%S).log"
        touch "$LOG_FILE"
    fi

    echo "=========================================="
    echo "CKAN 2.9 -> 2.11 Database Migration"
    echo "=========================================="
    echo ""
    log_info "Log file: $LOG_FILE"

    # Change to project directory for compose file resolution
    cd "$PROJECT_DIR"

    # Load environment
    load_env

    # Detect CKAN service name
    detect_ckan_service

    # Run pre-flight checks
    run_step "Pre-flight checks" run_preflight_checks

    # Print migration plan summary
    echo ""
    echo "Migration plan:"
    echo "  CKAN dump:      $CKAN_DUMP"
    echo "  Datastore dump: $DATASTORE_DUMP"
    echo "  Target CKAN DB: $CKAN_DB"
    echo "  Target DS DB:   $DATASTORE_DB"
    echo "  Compose file:   $COMPOSE_FILE"
    echo "  CKAN service:   $CKAN_SERVICE"
    echo "  Force mode:     $FORCE"
    echo ""

    # === MIGRATION PIPELINE ===
    run_step "Pre-migration backup"       step_backup
    run_step "Stop services"              step_stop_services
    run_step "Restore CKAN database"      step_restore_ckan
    run_step "Restore datastore database" step_restore_datastore
    run_step "Duplicate email check"      step_check_duplicate_emails
    run_step "Start CKAN"                 step_start_ckan
    run_step "Schema migration"           step_db_upgrade
    run_step "Datastore upgrade"          step_datastore_upgrade
    run_step "Datastore permissions"      step_datastore_permissions
    run_step "Search index rebuild"       step_search_reindex
    run_step "Start DataPusher"           step_start_datapusher
    run_step "Validation"                 step_validation

    echo ""
    log_info "Migration completed successfully."
    log_info "Log file: $LOG_FILE"
}

main "$@"
