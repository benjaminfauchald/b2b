# Production Data Sync Documentation

## Overview

This system provides automated nightly synchronization of production data to your development environment while preserving development schema integrity and ensuring data security.

## Features

- **Schema-Safe Sync**: Only syncs data, preserves development schema/migrations
- **Data Integrity**: Maintains foreign key relationships
- **Security**: Sanitizes sensitive data (passwords, tokens, PII)
- **Automated Backups**: Creates timestamped backups before each sync
- **Column Matching**: Only syncs columns that exist in both environments
- **Validation**: Post-sync validation ensures data integrity
- **Storage Sync**: Optional ActiveStorage file synchronization

## Scripts

### 1. `bin/sync_production_data.sh`
Main sync script that orchestrates the entire process.

**Usage:**
```bash
# Manual run
./bin/sync_production_data.sh

# With storage sync
SYNC_STORAGE_FILES=1 ./bin/sync_production_data.sh

# With email notification
SYNC_NOTIFICATION_EMAIL=admin@example.com ./bin/sync_production_data.sh
```

### 2. `bin/sanitize_dev_data.rb`
Rails script that sanitizes sensitive data after sync.

**What it does:**
- Sets all user passwords to `development123`
- Anonymizes emails (except test accounts)
- Removes API keys and tokens
- Clears IP addresses and sensitive logs

### 3. `bin/sync_storage_files.sh`
Syncs ActiveStorage files from production.

**Usage:**
```bash
# Standalone
./bin/sync_storage_files.sh

# Skip with environment variable
SKIP_STORAGE_SYNC=1 ./bin/sync_storage_files.sh
```

### 4. `bin/validate_sync.rb`
Validates data integrity after sync.

**Usage:**
```bash
# Run validation
bundle exec rails runner bin/validate_sync.rb
```

### 5. `bin/setup_sync_cron.sh`
Sets up automated midnight sync via cron.

**Usage:**
```bash
# Install cron job
./bin/setup_sync_cron.sh

# Remove cron job
crontab -l | grep -v 'sync_production_data.sh' | crontab -
```

## Tables Synced

### Core Data
- `users` - User accounts (passwords sanitized)
- `companies` - Business entities
- `people` - Contacts/employees
- `domains` - Domain ownership
- `communications` - Campaign history

### System Tables
- `service_configurations` - Service settings
- `service_audit_logs` - Audit trail
- `active_storage_*` - File metadata
- `action_text_rich_texts` - Rich content
- `action_mailbox_inbound_emails` - Email data

## Configuration

### Environment Variables

```bash
# Database connection
export PGHOST=localhost
export PGPORT=5432
export PGUSER=your_user
export PGPASSWORD=your_password

# Optional settings
export SYNC_STORAGE_FILES=1              # Enable storage sync
export SKIP_STORAGE_SYNC=1               # Skip storage sync
export SYNC_NOTIFICATION_EMAIL=admin@example.com  # Email notifications
export BATCH_SIZE=5000                   # Rows per batch (default 1000)

# Storage sync settings
export PROD_STORAGE_HOST=app.connectica.no
export PROD_STORAGE_USER=benjamin
export PROD_STORAGE_PATH=/home/benjamin/b2b/storage
```

## Security Considerations

### Data Sanitization
After each sync, the following data is automatically sanitized:

1. **User Passwords**: All set to bcrypt hash of `development123`
2. **Emails**: Anonymized to `user{id}@domain` format
3. **Test Accounts Preserved**:
   - `test@test.no` / `CodemyFTW2`
   - `admin@example.com` / `CodemyFTW2`
4. **API Keys**: Removed from service configurations
5. **Personal Data**: Phone numbers and emails anonymized

### Network Security
- Use SSH tunnels for remote database connections
- Ensure firewall rules allow only necessary connections
- Use strong passwords for database accounts

## Troubleshooting

### Common Issues

**1. "Cannot connect to production database"**
- Check database credentials in environment variables
- Verify network connectivity
- Ensure PostgreSQL is accepting connections

**2. "Table does not exist in production"**
- Normal if development has newer migrations
- Script will skip missing tables automatically

**3. "Foreign key constraint violation"**
- Check table sync order in script
- Ensure all dependent tables are included

**4. "Disk space issues"**
- Check available space for backups
- Old backups are auto-cleaned after 7 days
- Manually clean: `rm ~/Documents/Projects/b2b/backups/dev_backup_*.sql.gz`

**5. "Validation failures"**
- Run `./bin/validate_sync.rb` for detailed report
- Check logs in `log/sync/` directory

### Logs

Sync logs are stored in:
```
log/sync/sync_YYYYMMDD_HHMMSS.log
log/sync/sanitize_YYYYMMDD_HHMMSS.log
log/sync/storage_sync_YYYYMMDD_HHMMSS.log
```

### Manual Recovery

If sync fails, restore from backup:
```bash
# Find latest backup
ls -la backups/dev_backup_*.sql.gz

# Restore
gunzip -c backups/dev_backup_20240629_120000.sql.gz | \
  psql -h localhost -U $PGUSER -d b2b_development
```

## Best Practices

1. **Test First**: Run manually before setting up cron
2. **Monitor Logs**: Check sync logs regularly
3. **Verify Data**: Run validation after major changes
4. **Backup Retention**: Adjust backup retention as needed
5. **Storage Sync**: Only enable if needed (large files = long sync)

## Scheduling

The cron job runs at 5:00 AM daily:
```
0 5 * * * /path/to/sync_production_data.sh >> /tmp/sync_production_data_cron.log 2>&1
```

To check cron status:
```bash
crontab -l | grep sync_production_data
```

## Performance Considerations

- Default batch size: 1000 rows
- Large tables may take time to sync
- Consider running during low-traffic hours
- Monitor disk I/O during sync
- Materialized view refresh can be intensive

## Future Enhancements

- [ ] Incremental sync (only changed records)
- [ ] Parallel table syncing
- [ ] Web UI for sync monitoring
- [ ] Slack/Discord notifications
- [ ] Selective table sync configuration
- [ ] Automatic schema migration detection