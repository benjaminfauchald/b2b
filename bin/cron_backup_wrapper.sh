#!/bin/bash

# Cron Backup Wrapper Script
# This script properly loads environment variables for cron execution

# Set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# Change to project directory
cd "$PROJECT_ROOT"

# Load environment variables if .env file exists
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Set default PostgreSQL environment variables if not set
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-$(whoami)}"

# Ensure PATH includes common locations for PostgreSQL tools
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# Execute the actual backup script
exec "$PROJECT_ROOT/bin/db_backup.sh"