#!/bin/bash

# Database Backup Script for B2B Rails Application
# Backs up all PostgreSQL databases every 5 minutes

# Set environment variables
export RAILS_ROOT="/Users/benjamin/Documents/Projects/b2b"
export BACKUP_DIR="/Users/benjamin/Documents/Projects/b2b/db/backups"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER}"
export PGPASSWORD="${PGPASSWORD}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Get current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Database names
DATABASES=("b2b_development" "b2b_production" "b2b_production_cache" "b2b_production_queue" "b2b_production_cable")

# Function to backup a single database
backup_database() {
    local db_name=$1
    local backup_file="$BACKUP_DIR/${db_name}_${TIMESTAMP}.sql"
    
    echo "$(date): Starting backup of $db_name"
    
    # Create backup using pg_dump
    if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db_name" -f "$backup_file" --verbose; then
        echo "$(date): Successfully backed up $db_name to $backup_file"
        
        # Compress the backup file
        gzip "$backup_file"
        echo "$(date): Compressed backup to ${backup_file}.gz"
        
        # Log backup size
        size=$(ls -lh "${backup_file}.gz" | awk '{print $5}')
        echo "$(date): Backup size: $size"
        
    else
        echo "$(date): ERROR: Failed to backup $db_name" >&2
        return 1
    fi
}

# Function to cleanup old backups (keep last 288 backups = 24 hours worth)
cleanup_old_backups() {
    echo "$(date): Cleaning up old backups (keeping last 288 files per database)"
    
    for db in "${DATABASES[@]}"; do
        # Count files for this database
        count=$(ls -1 "$BACKUP_DIR"/${db}_*.sql.gz 2>/dev/null | wc -l)
        
        if [ "$count" -gt 288 ]; then
            # Delete oldest files, keeping only the latest 288
            ls -1t "$BACKUP_DIR"/${db}_*.sql.gz | tail -n +289 | xargs rm -f
            removed=$((count - 288))
            echo "$(date): Removed $removed old backup files for $db"
        fi
    done
}

# Main backup process
echo "$(date): Starting database backup process"

# Check if required environment variables are set
if [ -z "$PGUSER" ] || [ -z "$PGPASSWORD" ]; then
    echo "$(date): ERROR: PGUSER and PGPASSWORD environment variables must be set" >&2
    exit 1
fi

# Test database connection
if ! pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -q; then
    echo "$(date): ERROR: Cannot connect to PostgreSQL server" >&2
    exit 1
fi

# Backup each database
backup_success=0
backup_total=0

for db in "${DATABASES[@]}"; do
    # Check if database exists before trying to back it up
    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -lqt | cut -d \| -f 1 | grep -qw "$db"; then
        backup_total=$((backup_total + 1))
        if backup_database "$db"; then
            backup_success=$((backup_success + 1))
        fi
    else
        echo "$(date): Database $db does not exist, skipping"
    fi
done

# Cleanup old backups
cleanup_old_backups

# Summary
echo "$(date): Backup process completed. $backup_success/$backup_total databases backed up successfully"

# Calculate total backup directory size
total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
echo "$(date): Total backup directory size: $total_size"

exit 0