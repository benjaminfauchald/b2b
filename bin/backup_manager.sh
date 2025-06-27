#!/bin/bash

# Database Backup Manager
# Provides easy commands for managing database backups

BACKUP_DIR="/Users/benjamin/Documents/Projects/b2b/db/backups"
LOG_FILE="/Users/benjamin/Documents/Projects/b2b/log/db_backup.log"

show_usage() {
    echo "Database Backup Manager"
    echo "======================"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     - Set up automatic backups every 5 minutes"
    echo "  stop      - Remove automatic backup cron job"
    echo "  test      - Run a test backup"
    echo "  status    - Show backup status and recent files"
    echo "  logs      - Show recent backup logs"
    echo "  cleanup   - Clean up old backup files (keep last 24 hours)"
    echo "  restore   - List available backups for restoration"
    echo "  size      - Show backup directory size"
    echo ""
}

start_backups() {
    echo "Setting up automatic database backups..."
    /Users/benjamin/Documents/Projects/b2b/bin/setup_backup_cron.sh
}

stop_backups() {
    echo "Removing automatic backup cron job..."
    
    if crontab -l 2>/dev/null | grep -q "db_backup.sh"; then
        # Remove the backup cron job
        crontab -l | grep -v "db_backup.sh" | crontab -
        echo "✅ Automatic backups stopped"
    else
        echo "ℹ️  No backup cron job found"
    fi
}

test_backup() {
    echo "Running backup test..."
    /Users/benjamin/Documents/Projects/b2b/bin/test_backup.sh
}

show_status() {
    echo "Database Backup Status"
    echo "====================="
    echo ""
    
    # Check if cron job exists
    if crontab -l 2>/dev/null | grep -q "db_backup.sh"; then
        echo "✅ Automatic backups: ENABLED (every 5 minutes)"
        echo "Cron job: $(crontab -l | grep db_backup.sh)"
    else
        echo "❌ Automatic backups: DISABLED"
    fi
    
    echo ""
    
    # Show backup directory info
    if [ -d "$BACKUP_DIR" ]; then
        backup_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
        total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        
        echo "📁 Backup directory: $BACKUP_DIR"
        echo "📦 Total backup files: $backup_count"
        echo "💾 Total size: ${total_size:-0B}"
        
        if [ "$backup_count" -gt 0 ]; then
            echo ""
            echo "Recent backup files:"
            ls -lt "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -5 | while read line; do
                echo "  $line"
            done
        fi
    else
        echo "❌ Backup directory not found: $BACKUP_DIR"
    fi
    
    # Show last backup log entry
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "Last backup log entry:"
        tail -n 1 "$LOG_FILE"
    fi
}

show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "Recent backup logs (last 50 lines):"
        echo "==================================="
        tail -n 50 "$LOG_FILE"
    else
        echo "No backup log file found at: $LOG_FILE"
    fi
}

cleanup_backups() {
    echo "Cleaning up old backup files..."
    
    if [ -d "$BACKUP_DIR" ]; then
        # Keep last 288 files per database (24 hours worth at 5-minute intervals)
        DATABASES=("b2b_development" "b2b_production" "b2b_production_cache" "b2b_production_queue" "b2b_production_cable")
        
        for db in "${DATABASES[@]}"; do
            count=$(ls -1 "$BACKUP_DIR"/${db}_*.sql.gz 2>/dev/null | wc -l)
            
            if [ "$count" -gt 288 ]; then
                ls -1t "$BACKUP_DIR"/${db}_*.sql.gz | tail -n +289 | xargs rm -f
                removed=$((count - 288))
                echo "Removed $removed old backup files for $db"
            else
                echo "No cleanup needed for $db ($count files)"
            fi
        done
        
        echo "Cleanup completed"
    else
        echo "Backup directory not found: $BACKUP_DIR"
    fi
}

show_restore_options() {
    echo "Available backup files for restoration:"
    echo "======================================"
    
    if [ -d "$BACKUP_DIR" ]; then
        echo ""
        DATABASES=("b2b_development" "b2b_production" "b2b_production_cache" "b2b_production_queue" "b2b_production_cable")
        
        for db in "${DATABASES[@]}"; do
            echo "Database: $db"
            ls -lt "$BACKUP_DIR"/${db}_*.sql.gz 2>/dev/null | head -5 | while read line; do
                echo "  $line"
            done
            echo ""
        done
        
        echo "To restore a backup:"
        echo "1. Stop your Rails application"
        echo "2. Gunzip the backup file: gunzip backup_file.sql.gz"
        echo "3. Drop the existing database: dropdb -U \$PGUSER database_name"
        echo "4. Create a new database: createdb -U \$PGUSER database_name"
        echo "5. Restore: psql -U \$PGUSER -d database_name -f backup_file.sql"
    else
        echo "No backup directory found: $BACKUP_DIR"
    fi
}

show_size() {
    if [ -d "$BACKUP_DIR" ]; then
        echo "Backup directory size breakdown:"
        echo "==============================="
        du -sh "$BACKUP_DIR"/* 2>/dev/null | sort -hr
        echo ""
        echo "Total: $(du -sh "$BACKUP_DIR" | cut -f1)"
    else
        echo "Backup directory not found: $BACKUP_DIR"
    fi
}

# Main script
case "${1:-}" in
    start)
        start_backups
        ;;
    stop)
        stop_backups
        ;;
    test)
        test_backup
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    cleanup)
        cleanup_backups
        ;;
    restore)
        show_restore_options
        ;;
    size)
        show_size
        ;;
    *)
        show_usage
        ;;
esac