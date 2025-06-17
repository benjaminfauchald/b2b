#!/bin/bash

# Database Backup Manager for B2B Development Environment
# This script helps manage database backups

set -e

PROJECT_ROOT="/home/benjamin/b2b"
BACKUP_DIR="$PROJECT_ROOT/backups/database"
DB_NAME="b2b_development"
DB_USER="${PGUSER:-postgres}"
DB_HOST="${PGHOST:-localhost}"
DB_PORT="${PGPORT:-5432}"
DB_PASSWORD="${PGPASSWORD}"

# Set PGPASSWORD environment variable
export PGPASSWORD="$DB_PASSWORD"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
show_usage() {
    echo "Database Backup Manager"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  list                 - List all available backups"
    echo "  latest               - Show the latest backup"
    echo "  restore <backup>     - Restore from a specific backup file"
    echo "  restore-latest       - Restore from the latest backup"
    echo "  cleanup              - Remove old backups (older than 7 days)"
    echo "  status               - Show backup status and disk usage"
    echo "  test <backup>        - Test if a backup file is valid"
    echo "  manual               - Create a manual backup now"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 restore b2b_dev_backup_20250617_020336.sql.gz"
    echo "  $0 restore-latest"
}

# Function to list backups
list_backups() {
    print_color $BLUE "Available Database Backups:"
    echo "=========================================="
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/*.sql.gz 2>/dev/null)" ]; then
        print_color $YELLOW "No backups found in $BACKUP_DIR"
        return
    fi
    
    echo "Filename                                Size      Date"
    echo "------------------------------------------------------"
    
    ls -lt "$BACKUP_DIR"/*.sql.gz 2>/dev/null | while read -r line; do
        filename=$(basename "$(echo $line | awk '{print $9}')")
        size=$(echo $line | awk '{print $5}' | numfmt --to=iec)
        date=$(echo $line | awk '{print $6, $7, $8}')
        printf "%-40s %-8s %s\n" "$filename" "$size" "$date"
    done
}

# Function to get latest backup
get_latest_backup() {
    ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | head -n 1
}

# Function to show latest backup
show_latest() {
    local latest=$(get_latest_backup)
    if [ -z "$latest" ]; then
        print_color $YELLOW "No backups found"
        return 1
    fi
    
    print_color $BLUE "Latest Backup:"
    echo "=============="
    local filename=$(basename "$latest")
    local size=$(du -h "$latest" | cut -f1)
    local date=$(stat -c %y "$latest" | cut -d'.' -f1)
    
    echo "File: $filename"
    echo "Size: $size"
    echo "Date: $date"
}

# Function to restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        print_color $RED "Error: No backup file specified"
        return 1
    fi
    
    # Check if it's just a filename or full path
    if [ ! -f "$backup_file" ]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_color $RED "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    print_color $YELLOW "WARNING: This will completely replace the current database!"
    print_color $YELLOW "Database: $DB_NAME"
    print_color $YELLOW "Backup: $(basename $backup_file)"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_color $YELLOW "Restore cancelled"
        return 0
    fi
    
    print_color $BLUE "Starting database restore..."
    
    # Drop and recreate database
    print_color $BLUE "Dropping existing database..."
    dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" --if-exists
    
    print_color $BLUE "Creating new database..."
    createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
    
    # Restore from backup
    print_color $BLUE "Restoring from backup..."
    if gunzip -c "$backup_file" | psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > /dev/null; then
        print_color $GREEN "Database restore completed successfully!"
    else
        print_color $RED "Error: Database restore failed"
        return 1
    fi
}

# Function to restore latest backup
restore_latest() {
    local latest=$(get_latest_backup)
    if [ -z "$latest" ]; then
        print_color $RED "Error: No backups found"
        return 1
    fi
    
    restore_backup "$latest"
}

# Function to cleanup old backups
cleanup_backups() {
    print_color $BLUE "Cleaning up old backups..."
    
    local before_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    
    # Remove backups older than 7 days
    find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +7 -delete 2>/dev/null || true
    
    local after_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    local removed=$((before_count - after_count))
    
    print_color $GREEN "Cleanup completed. Removed $removed old backup(s)"
    print_color $BLUE "Remaining backups: $after_count"
}

# Function to show backup status
show_status() {
    print_color $BLUE "Backup Status:"
    echo "=============="
    
    local backup_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    local available_space=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    
    echo "Total backups: $backup_count"
    echo "Total size: $total_size"
    echo "Available space: $available_space"
    echo ""
    
    show_latest
    
    echo ""
    print_color $BLUE "Cron Job Status:"
    echo "================"
    if crontab -l | grep -q "backup_database.sh"; then
        print_color $GREEN "✓ Hourly backup cron job is active"
    else
        print_color $RED "✗ Hourly backup cron job not found"
    fi
}

# Function to test backup
test_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        print_color $RED "Error: No backup file specified"
        return 1
    fi
    
    # Check if it's just a filename or full path
    if [ ! -f "$backup_file" ]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_color $RED "Error: Backup file not found: $backup_file"
        return 1
    fi
    
    print_color $BLUE "Testing backup file: $(basename $backup_file)"
    
    if gzip -t "$backup_file" 2>/dev/null; then
        print_color $GREEN "✓ Backup file is valid and not corrupted"
    else
        print_color $RED "✗ Backup file is corrupted or invalid"
        return 1
    fi
}

# Function to create manual backup
manual_backup() {
    print_color $BLUE "Creating manual backup..."
    cd "$PROJECT_ROOT"
    if ./scripts/backup_database.sh; then
        print_color $GREEN "Manual backup completed successfully!"
        show_latest
    else
        print_color $RED "Manual backup failed!"
        return 1
    fi
}

# Main execution
case "${1:-}" in
    "list")
        list_backups
        ;;
    "latest")
        show_latest
        ;;
    "restore")
        restore_backup "$2"
        ;;
    "restore-latest")
        restore_latest
        ;;
    "cleanup")
        cleanup_backups
        ;;
    "status")
        show_status
        ;;
    "test")
        test_backup "$2"
        ;;
    "manual")
        manual_backup
        ;;
    "help"|"--help"|"-h"|"")
        show_usage
        ;;
    *)
        print_color $RED "Error: Unknown command '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac 