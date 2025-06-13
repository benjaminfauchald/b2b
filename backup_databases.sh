#!/bin/bash

# Set environment variables
source ~/.env

# Create backup directory if it doesn't exist
BACKUP_DIR="/home/benjamin/backups"
mkdir -p "$BACKUP_DIR"

# Get current timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# List of databases to backup
DATABASES=(
    "b2b_development"
    "b2b_test"
    "b2b_production"
    "b2b_production_cache"
    "b2b_production_queue"
    "b2b_production_cable"
)

# Backup each database
for DB in "${DATABASES[@]}"; do
    echo "Backing up $DB..."
    BACKUP_FILE="$BACKUP_DIR/${DB}_${TIMESTAMP}.sql.gz"
    
    # Create backup with compression
    PGPASSWORD=$PGPASSWORD pg_dump -h $PGHOST -U $PGUSER -d $DB | gzip > "$BACKUP_FILE"
    
    # Check if backup was successful
    if [ $? -eq 0 ]; then
        echo "Successfully backed up $DB to $BACKUP_FILE"
        
        # Keep only the last 7 days of backups
        find "$BACKUP_DIR" -name "${DB}_*.sql.gz" -mtime +7 -delete
    else
        echo "Error backing up $DB"
        exit 1
    fi
done

echo "All backups completed successfully" 