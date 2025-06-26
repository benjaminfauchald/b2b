#!/bin/bash

# Setup script for database backup cron job
# This script adds a cron job to backup databases every 5 minutes

SCRIPT_DIR="/Users/benjamin/Documents/Projects/b2b/bin"
LOG_DIR="/Users/benjamin/Documents/Projects/b2b/log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Create the cron job entry
CRON_JOB="*/5 * * * * cd /Users/benjamin/Documents/Projects/b2b && $SCRIPT_DIR/db_backup.sh >> $LOG_DIR/db_backup.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "db_backup.sh"; then
    echo "Database backup cron job already exists"
    echo "Current cron jobs:"
    crontab -l | grep "db_backup.sh"
else
    # Add the cron job
    echo "Adding database backup cron job..."
    
    # Get current crontab and add new job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    if [ $? -eq 0 ]; then
        echo "Successfully added database backup cron job"
        echo "Backup will run every 5 minutes"
        echo "Logs will be written to: $LOG_DIR/db_backup.log"
    else
        echo "Failed to add cron job" >&2
        exit 1
    fi
fi

echo ""
echo "Current crontab:"
crontab -l

echo ""
echo "To remove the backup cron job, run:"
echo "crontab -e"
echo "Then delete the line containing 'db_backup.sh'"

echo ""
echo "To view backup logs:"
echo "tail -f $LOG_DIR/db_backup.log"