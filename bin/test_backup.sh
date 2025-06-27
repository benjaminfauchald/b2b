#!/bin/bash

# Test script for database backup
# This performs a single backup to verify everything works

echo "Testing database backup system..."
echo "================================="

# Check if required environment variables are set
if [ -z "$PGUSER" ] || [ -z "$PGPASSWORD" ]; then
    echo "ERROR: Please set PGUSER and PGPASSWORD environment variables"
    echo "Example:"
    echo "export PGUSER=your_username"
    echo "export PGPASSWORD=your_password"
    exit 1
fi

# Check if PostgreSQL is running
if ! pg_isready -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "$PGUSER" -q; then
    echo "ERROR: Cannot connect to PostgreSQL server"
    echo "Please ensure PostgreSQL is running and credentials are correct"
    exit 1
fi

# Run the backup script
echo "Running backup script..."
/Users/benjamin/Documents/Projects/b2b/bin/db_backup.sh

# Check results
BACKUP_DIR="/Users/benjamin/Documents/Projects/b2b/db/backups"
if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo "Backup directory contents:"
    ls -la "$BACKUP_DIR"
    
    echo ""
    echo "Backup directory size:"
    du -sh "$BACKUP_DIR"
    
    # Count backup files
    backup_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    echo "Number of backup files: $backup_count"
    
    if [ "$backup_count" -gt 0 ]; then
        echo ""
        echo "✅ Backup test SUCCESSFUL!"
        echo "Latest backup files:"
        ls -lt "$BACKUP_DIR"/*.sql.gz | head -5
    else
        echo ""
        echo "❌ Backup test FAILED - No backup files created"
        exit 1
    fi
else
    echo "❌ Backup test FAILED - Backup directory not created"
    exit 1
fi