#!/bin/bash

# Production to Development Database Sync Script
# This script syncs production data to development while preserving dev schema
# Run at midnight via cron for daily updates

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$PROJECT_ROOT/log/sync"
LOG_FILE="$LOG_DIR/sync_${TIMESTAMP}.log"
BACKUP_DIR="$PROJECT_ROOT/backups"
BACKUP_FILE="$BACKUP_DIR/dev_backup_${TIMESTAMP}.sql.gz"

# Database configurations
DEV_DB="b2b_development"
DEV_HOST="${PGHOST:-localhost}"
DEV_PORT="${PGPORT:-5432}"
DEV_USER="${PGUSER}"
DEV_PASS="${PGPASSWORD}"

PROD_DB="b2b_production"
PROD_HOST="${PROD_HOST:-app.connectica.no}"
PROD_PORT="${PROD_PORT:-5432}"
PROD_USER="${PROD_USER:-benjamin}"
PROD_PASS="${PROD_PASS:-Charcoal2020!}"

# Tables to sync (order matters for foreign keys)
TABLES=(
  "users"
  "companies"
  "people"
  "domains"
  "communications"
  "service_configurations"
  "service_audit_logs"
  "active_storage_blobs"
  "active_storage_attachments"
  "active_storage_variant_records"
  "action_text_rich_texts"
  "action_mailbox_inbound_emails"
)

# Ensure directories exist
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# Logging function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
  log "ERROR: $1"
  exit 1
}

# Check prerequisites
check_prerequisites() {
  log "Checking prerequisites..."
  
  # Check if pg_dump and psql are available
  command -v pg_dump >/dev/null 2>&1 || error_exit "pg_dump not found"
  command -v psql >/dev/null 2>&1 || error_exit "psql not found"
  
  # Test database connections
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c "SELECT 1" >/dev/null 2>&1 || \
    error_exit "Cannot connect to development database"
  
  PGPASSWORD="$PROD_PASS" psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c "SELECT 1" >/dev/null 2>&1 || \
    error_exit "Cannot connect to production database"
  
  log "Prerequisites check passed"
}

# Backup development database
backup_dev_database() {
  log "Backing up development database..."
  
  PGPASSWORD="$DEV_PASS" pg_dump \
    -h "$DEV_HOST" \
    -p "$DEV_PORT" \
    -U "$DEV_USER" \
    -d "$DEV_DB" \
    --no-owner \
    --no-acl \
    | gzip > "$BACKUP_FILE"
  
  if [ -f "$BACKUP_FILE" ]; then
    log "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
  else
    error_exit "Backup failed"
  fi
}

# Get columns that exist in both databases
get_common_columns() {
  local table=$1
  
  # Get dev columns
  DEV_COLS=$(PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -t -c \
    "SELECT column_name FROM information_schema.columns WHERE table_name = '$table' ORDER BY ordinal_position")
  
  # Get prod columns
  PROD_COLS=$(PGPASSWORD="$PROD_PASS" psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
    "SELECT column_name FROM information_schema.columns WHERE table_name = '$table' ORDER BY ordinal_position")
  
  # Find intersection
  echo "$DEV_COLS" | grep -Fx "$PROD_COLS" | tr '\n' ',' | sed 's/,$//'
}

# Sync a single table
sync_table() {
  local table=$1
  log "Syncing table: $table"
  
  # Check if table exists in production
  TABLE_EXISTS=$(PGPASSWORD="$PROD_PASS" psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -t -c \
    "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '$table')")
  
  if [ "$TABLE_EXISTS" != " t" ]; then
    log "WARNING: Table $table does not exist in production, skipping"
    return
  fi
  
  # Get common columns
  COLUMNS=$(get_common_columns "$table")
  if [ -z "$COLUMNS" ]; then
    log "WARNING: No common columns found for $table, skipping"
    return
  fi
  
  # Create temp file for data
  TEMP_FILE="/tmp/${table}_${TIMESTAMP}.sql"
  
  # Export data from production (data only, specific columns)
  log "Exporting $table from production..."
  PGPASSWORD="$PROD_PASS" psql -h "$PROD_HOST" -p "$PROD_PORT" -U "$PROD_USER" -d "$PROD_DB" -c \
    "COPY (SELECT $COLUMNS FROM $table) TO STDOUT WITH (FORMAT csv, HEADER true, DELIMITER '|', NULL '\\N')" > "$TEMP_FILE"
  
  ROW_COUNT=$(wc -l < "$TEMP_FILE")
  log "Exported $((ROW_COUNT - 1)) rows from $table"
  
  # Clear existing data in dev
  log "Clearing $table in development..."
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "TRUNCATE TABLE $table CASCADE"
  
  # Import to development
  log "Importing $table to development..."
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "COPY $table ($COLUMNS) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER '|', NULL '\\N')" < "$TEMP_FILE"
  
  # Clean up
  rm -f "$TEMP_FILE"
  
  log "Completed sync for $table"
}

# Reset sequences
reset_sequences() {
  log "Resetting sequences..."
  
  for table in "${TABLES[@]}"; do
    # Check if table has an id column
    HAS_ID=$(PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -t -c \
      "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = '$table' AND column_name = 'id')")
    
    if [ "$HAS_ID" = " t" ]; then
      PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
        "SELECT setval(pg_get_serial_sequence('$table', 'id'), COALESCE(MAX(id), 1)) FROM $table" >/dev/null 2>&1 || true
    fi
  done
  
  log "Sequences reset"
}

# Refresh materialized views
refresh_views() {
  log "Refreshing materialized views..."
  
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "REFRESH MATERIALIZED VIEW service_performance_stats" 2>/dev/null || \
    log "WARNING: Could not refresh service_performance_stats"
  
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "REFRESH MATERIALIZED VIEW latest_service_runs" 2>/dev/null || \
    log "WARNING: Could not refresh latest_service_runs"
  
  log "Materialized views refreshed"
}

# Run data sanitization
sanitize_data() {
  log "Running data sanitization..."
  
  cd "$PROJECT_ROOT"
  bundle exec rails runner "load '$SCRIPT_DIR/sanitize_dev_data.rb'" >> "$LOG_FILE" 2>&1
  
  log "Data sanitization completed"
}

# Main sync process
main() {
  log "Starting production to development sync"
  
  # Check prerequisites
  check_prerequisites
  
  # Backup development database
  backup_dev_database
  
  # Disable foreign key checks temporarily
  log "Disabling foreign key constraints..."
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "SET session_replication_role = 'replica'"
  
  # Sync each table
  for table in "${TABLES[@]}"; do
    sync_table "$table" || log "WARNING: Failed to sync $table"
  done
  
  # Re-enable foreign key checks
  log "Re-enabling foreign key constraints..."
  PGPASSWORD="$DEV_PASS" psql -h "$DEV_HOST" -p "$DEV_PORT" -U "$DEV_USER" -d "$DEV_DB" -c \
    "SET session_replication_role = 'origin'"
  
  # Reset sequences
  reset_sequences
  
  # Run data sanitization
  sanitize_data
  
  # Refresh materialized views
  refresh_views
  
  # Sync ActiveStorage files (optional)
  if [ "${SYNC_STORAGE_FILES:-0}" = "1" ]; then
    log "Syncing ActiveStorage files..."
    "$SCRIPT_DIR/sync_storage_files.sh" || log "WARNING: Storage sync failed"
  fi
  
  # Run validation
  log "Running post-sync validation..."
  cd "$PROJECT_ROOT"
  bundle exec rails runner "load '$SCRIPT_DIR/validate_sync.rb'" >> "$LOG_FILE" 2>&1 || \
    log "WARNING: Some validations failed, check the log"
  
  # Clean up old backups (keep last 7 days)
  log "Cleaning up old backups..."
  find "$BACKUP_DIR" -name "dev_backup_*.sql.gz" -mtime +7 -delete
  
  log "Sync completed successfully!"
  
  # Send notification (optional)
  if [ -n "${SYNC_NOTIFICATION_EMAIL:-}" ]; then
    echo "Database sync completed at $(date)" | mail -s "Dev DB Sync Complete" "$SYNC_NOTIFICATION_EMAIL"
  fi
}

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/sync_production_data.lock"
if [ -f "$LOCK_FILE" ]; then
  error_exit "Sync already in progress (lock file exists)"
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed on exit
trap "rm -f $LOCK_FILE" EXIT

# Run main process
main "$@"