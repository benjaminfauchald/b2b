#!/bin/bash

# Domain Migration Script from b2b.connectica.no to app.connectica.no
# This script directly migrates domain data using PostgreSQL

echo "Starting domain migration from remote to local database..."
echo "============================================================"

# Database connection parameters
REMOTE_HOST="b2b.connectica.no"
REMOTE_DB="b2b_development"
REMOTE_USER="postgres"
REMOTE_PASS="Charcoal2020!"

LOCAL_HOST="app.connectica.no"
LOCAL_DB="b2b_production"
LOCAL_USER="benjamin"
LOCAL_PASS="Charcoal2020!"

# Export PGPASSWORD to avoid password prompts
export PGPASSWORD="$REMOTE_PASS"

# Get total count from remote database
echo "Getting record count from remote database..."
TOTAL_REMOTE=$(psql -h "$REMOTE_HOST" -U "$REMOTE_USER" -d "$REMOTE_DB" -t -c "SELECT COUNT(*) FROM domains;" | xargs)
echo "Total remote records: $TOTAL_REMOTE"

# Export local password
export PGPASSWORD="$LOCAL_PASS"

# Get current local count
LOCAL_BEFORE=$(psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -t -c "SELECT COUNT(*) FROM domains;" | xargs)
echo "Local records before migration: $LOCAL_BEFORE"

# Create temp file for data
TEMP_FILE="/tmp/domains_migration_$(date +%s).sql"

echo "Exporting data from remote database..."
export PGPASSWORD="$REMOTE_PASS"

# Export domains data to SQL file, excluding duplicates that might already exist locally
psql -h "$REMOTE_HOST" -U "$REMOTE_USER" -d "$REMOTE_DB" -c "
COPY (
  SELECT 
    domain,
    www,
    mx,
    dns,
    mx_error,
    created_at,
    updated_at
  FROM domains 
  ORDER BY id
) TO STDOUT WITH CSV HEADER;
" > "${TEMP_FILE}.csv"

echo "Creating SQL insert statements..."
cat > "$TEMP_FILE" << 'EOF'
-- Domain migration SQL
BEGIN;

-- Create temporary table for staging
CREATE TEMP TABLE temp_domains (
  domain VARCHAR,
  www BOOLEAN,
  mx BOOLEAN,
  dns BOOLEAN,
  mx_error VARCHAR,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

EOF

# Add the CSV import command
echo "\\copy temp_domains FROM '${TEMP_FILE}.csv' WITH CSV HEADER;" >> "$TEMP_FILE"

# Add the merge logic
cat >> "$TEMP_FILE" << 'EOF'

-- Insert only new domains (avoid duplicates)
INSERT INTO domains (domain, www, mx, dns, mx_error, created_at, updated_at)
SELECT 
  t.domain,
  t.www,
  t.mx,
  t.dns,
  t.mx_error,
  t.created_at,
  t.updated_at
FROM temp_domains t
LEFT JOIN domains d ON d.domain = t.domain
WHERE d.domain IS NULL;

-- Show results
SELECT 'Migration completed. Records inserted: ' || COUNT(*)::text as result
FROM temp_domains t
LEFT JOIN domains d ON d.domain = t.domain
WHERE d.domain IS NULL;

COMMIT;
EOF

echo "Importing data to local database..."
export PGPASSWORD="$LOCAL_PASS"

# Execute the migration
psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -f "$TEMP_FILE"

# Get final counts
LOCAL_AFTER=$(psql -h "$LOCAL_HOST" -U "$LOCAL_USER" -d "$LOCAL_DB" -t -c "SELECT COUNT(*) FROM domains;" | xargs)
NET_INCREASE=$((LOCAL_AFTER - LOCAL_BEFORE))

echo ""
echo "============================================================"
echo "Migration completed!"
echo "Remote records: $TOTAL_REMOTE"
echo "Local before: $LOCAL_BEFORE"
echo "Local after: $LOCAL_AFTER"
echo "Net increase: $NET_INCREASE"
echo "============================================================"

# Cleanup
rm -f "$TEMP_FILE" "${TEMP_FILE}.csv"
echo "Temporary files cleaned up."