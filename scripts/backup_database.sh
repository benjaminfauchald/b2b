#!/bin/bash

# Database Backup Script for B2B Development Environment
# This script creates compressed PostgreSQL backups with automatic rotation

set -e  # Exit on any error

# Configuration
PROJECT_ROOT="/home/benjamin/b2b"
BACKUP_DIR="$PROJECT_ROOT/backups/database"
LOG_FILE="$BACKUP_DIR/backup.log"
RETENTION_DAYS=7  # Keep backups for 7 days
MAX_BACKUPS=168   # Keep maximum 168 backups (7 days * 24 hours)

# Database configuration from Rails environment variables
DB_NAME="b2b_development"
DB_USER="${PGUSER:-postgres}"
DB_HOST="${PGHOST:-localhost}"
DB_PORT="${PGPORT:-5432}"
DB_PASSWORD="${PGPASSWORD}"

# Set PGPASSWORD environment variable for pg_dump
export PGPASSWORD="$DB_PASSWORD"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log_message "Starting cleanup of old backups..."
    
    # Remove backups older than retention days
    find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    # Keep only the most recent MAX_BACKUPS files
    ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f 2>/dev/null || true
    
    # Count remaining backups
    backup_count=$(ls -1 "$BACKUP_DIR"/*.sql.gz 2>/dev/null | wc -l)
    log_message "Cleanup completed. Current backup count: $backup_count"
}

# Function to get database size
get_db_size() {
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null | xargs
}

# Main backup function
perform_backup() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$BACKUP_DIR/b2b_dev_backup_$timestamp.sql"
    local compressed_file="$backup_file.gz"
    
    log_message "Starting database backup..."
    log_message "Database: $DB_NAME"
    log_message "Host: $DB_HOST:$DB_PORT"
    log_message "User: $DB_USER"
    
    # Get database size before backup
    db_size=$(get_db_size)
    log_message "Database size: $db_size"
    
    # Check available disk space
    available_space=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    log_message "Available disk space: $available_space"
    
    # Perform the backup
    log_message "Creating backup: $backup_file"
    
    if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --verbose \
        --no-password \
        --format=plain \
        --no-owner \
        --no-privileges \
        --exclude-table-data=service_audit_logs \
        --exclude-table-data=ar_internal_metadata \
        > "$backup_file" 2>>"$LOG_FILE"; then
        
        log_message "Database dump completed successfully"
        
        # Compress the backup
        log_message "Compressing backup..."
        if gzip "$backup_file"; then
            log_message "Backup compressed successfully: $compressed_file"
            
            # Get compressed file size
            compressed_size=$(du -h "$compressed_file" | cut -f1)
            log_message "Compressed backup size: $compressed_size"
            
            # Verify the compressed backup
            if gzip -t "$compressed_file" 2>/dev/null; then
                log_message "Backup verification successful"
                return 0
            else
                log_message "ERROR: Backup verification failed"
                rm -f "$compressed_file" 2>/dev/null || true
                return 1
            fi
        else
            log_message "ERROR: Failed to compress backup"
            rm -f "$backup_file" 2>/dev/null || true
            return 1
        fi
    else
        log_message "ERROR: Database dump failed"
        rm -f "$backup_file" 2>/dev/null || true
        return 1
    fi
}

# Function to send notification (optional)
send_notification() {
    local status="$1"
    local message="$2"
    
    # You can add email notifications here if needed
    # echo "$message" | mail -s "Database Backup $status" admin@example.com
    
    log_message "Notification: $status - $message"
}

# Main execution
main() {
    log_message "=== Database Backup Started ==="
    
    # Check if PostgreSQL is running
    if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; then
        log_message "ERROR: PostgreSQL is not accessible"
        send_notification "FAILED" "PostgreSQL is not accessible"
        exit 1
    fi
    
    # Check if database exists
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        log_message "ERROR: Database '$DB_NAME' does not exist"
        send_notification "FAILED" "Database '$DB_NAME' does not exist"
        exit 1
    fi
    
    # Perform backup
    if perform_backup; then
        log_message "Backup completed successfully"
        
        # Cleanup old backups
        cleanup_old_backups
        
        log_message "=== Database Backup Completed Successfully ==="
        send_notification "SUCCESS" "Database backup completed successfully"
    else
        log_message "=== Database Backup Failed ==="
        send_notification "FAILED" "Database backup failed"
        exit 1
    fi
}

# Run the main function
main "$@" 