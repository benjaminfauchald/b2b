#!/bin/bash

# ActiveStorage File Sync Script
# Syncs storage files from production to development
# Can be run standalone or called by sync_production_data.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$PROJECT_ROOT/log/sync"
LOG_FILE="$LOG_DIR/storage_sync_${TIMESTAMP}.log"

# Storage paths
DEV_STORAGE="$PROJECT_ROOT/storage"
PROD_HOST="${PROD_STORAGE_HOST:-app.connectica.no}"
PROD_USER="${PROD_STORAGE_USER:-benjamin}"
PROD_STORAGE_PATH="${PROD_STORAGE_PATH:-/home/benjamin/b2b/storage}"

# Rsync options
RSYNC_OPTS="-avz --progress --delete-after --exclude='*.tmp' --exclude='cache/'"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

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
  
  # Check if rsync is available
  command -v rsync >/dev/null 2>&1 || error_exit "rsync not found"
  
  # Check SSH connection to production
  ssh -o ConnectTimeout=5 -o BatchMode=yes "$PROD_USER@$PROD_HOST" exit 2>/dev/null || \
    error_exit "Cannot connect to production server via SSH"
  
  # Ensure local storage directory exists
  mkdir -p "$DEV_STORAGE"
  
  log "Prerequisites check passed"
}

# Backup current storage
backup_storage() {
  log "Backing up current storage files..."
  
  BACKUP_DIR="$PROJECT_ROOT/backups/storage"
  BACKUP_FILE="$BACKUP_DIR/storage_backup_${TIMESTAMP}.tar.gz"
  
  mkdir -p "$BACKUP_DIR"
  
  if [ -d "$DEV_STORAGE" ] && [ "$(ls -A "$DEV_STORAGE")" ]; then
    tar -czf "$BACKUP_FILE" -C "$PROJECT_ROOT" storage/ 2>/dev/null || true
    
    if [ -f "$BACKUP_FILE" ]; then
      log "Storage backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
    else
      log "WARNING: Storage backup failed, but continuing..."
    fi
  else
    log "No existing storage files to backup"
  fi
}

# Sync storage files
sync_storage() {
  log "Starting storage file sync from production..."
  
  # Create storage subdirectories if they don't exist
  for subdir in "aa" "ab" "ac" "ad" "ae" "af" "ag" "ah" "ai" "aj" "ak" "al" "am" "an" "ao" "ap" "aq" "ar" "as" "at" "au" "av" "aw" "ax" "ay" "az"; do
    mkdir -p "$DEV_STORAGE/$subdir"
  done
  
  # Perform rsync
  log "Running rsync from $PROD_HOST:$PROD_STORAGE_PATH to $DEV_STORAGE"
  
  rsync $RSYNC_OPTS \
    "$PROD_USER@$PROD_HOST:$PROD_STORAGE_PATH/" \
    "$DEV_STORAGE/" \
    2>&1 | tee -a "$LOG_FILE"
  
  # Check rsync exit status
  RSYNC_STATUS=${PIPESTATUS[0]}
  if [ $RSYNC_STATUS -eq 0 ]; then
    log "Storage sync completed successfully"
  else
    error_exit "Rsync failed with status $RSYNC_STATUS"
  fi
}

# Verify sync
verify_sync() {
  log "Verifying storage sync..."
  
  # Count files in local storage
  LOCAL_COUNT=$(find "$DEV_STORAGE" -type f -not -path "*/cache/*" | wc -l)
  log "Local storage files: $LOCAL_COUNT"
  
  # Get remote file count
  REMOTE_COUNT=$(ssh "$PROD_USER@$PROD_HOST" "find $PROD_STORAGE_PATH -type f -not -path '*/cache/*' | wc -l")
  log "Remote storage files: $REMOTE_COUNT"
  
  # Check if counts match (allow small differences due to timing)
  DIFF=$((LOCAL_COUNT - REMOTE_COUNT))
  if [ ${DIFF#-} -le 5 ]; then
    log "Storage sync verified successfully"
  else
    log "WARNING: File count mismatch (difference: $DIFF files)"
  fi
}

# Fix permissions
fix_permissions() {
  log "Fixing storage file permissions..."
  
  # Rails needs write access to storage
  chmod -R 755 "$DEV_STORAGE"
  
  # Ensure Rails user can write to storage
  if [ -n "${RAILS_USER:-}" ]; then
    chown -R "$RAILS_USER" "$DEV_STORAGE" 2>/dev/null || true
  fi
  
  log "Permissions fixed"
}

# Clean up old backups
cleanup_old_backups() {
  log "Cleaning up old storage backups..."
  
  BACKUP_DIR="$PROJECT_ROOT/backups/storage"
  if [ -d "$BACKUP_DIR" ]; then
    # Keep only last 3 storage backups
    find "$BACKUP_DIR" -name "storage_backup_*.tar.gz" -type f | \
      sort -r | tail -n +4 | xargs rm -f 2>/dev/null || true
  fi
  
  log "Cleanup completed"
}

# Main function
main() {
  log "Starting ActiveStorage file sync"
  
  # Check if we should skip storage sync
  if [ "${SKIP_STORAGE_SYNC:-0}" = "1" ]; then
    log "Storage sync skipped (SKIP_STORAGE_SYNC=1)"
    exit 0
  fi
  
  # Run sync steps
  check_prerequisites
  backup_storage
  sync_storage
  verify_sync
  fix_permissions
  cleanup_old_backups
  
  log "Storage sync completed successfully!"
}

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/sync_storage_files.lock"
if [ -f "$LOCK_FILE" ]; then
  error_exit "Storage sync already in progress (lock file exists)"
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed on exit
trap "rm -f $LOCK_FILE" EXIT

# Run main process
main "$@"