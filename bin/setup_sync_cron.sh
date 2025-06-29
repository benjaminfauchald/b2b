#!/bin/bash

# Setup script for production data sync cron job
# This adds a cron entry to run the sync at midnight daily

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync_production_data.sh"

# Check if sync script exists
if [ ! -f "$SYNC_SCRIPT" ]; then
  echo "Error: sync_production_data.sh not found at $SYNC_SCRIPT"
  exit 1
fi

# Define the cron job
# Runs at 5:00 AM every day
CRON_JOB="0 5 * * * $SYNC_SCRIPT >> /tmp/sync_production_data_cron.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "sync_production_data.sh"; then
  echo "Cron job already exists. Current cron entries:"
  crontab -l | grep "sync_production_data.sh"
  echo ""
  read -p "Do you want to update it? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cron setup cancelled."
    exit 0
  fi
  # Remove existing entry
  crontab -l | grep -v "sync_production_data.sh" | crontab -
fi

# Add the cron job
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "Cron job added successfully!"
echo "The sync will run daily at 5:00 AM."
echo ""
echo "Current cron configuration:"
crontab -l | grep "sync_production_data.sh"
echo ""
echo "To monitor sync logs:"
echo "  tail -f /tmp/sync_production_data_cron.log"
echo ""
echo "To view sync history:"
echo "  ls -la $SCRIPT_DIR/../log/sync/"
echo ""
echo "To remove the cron job:"
echo "  crontab -l | grep -v 'sync_production_data.sh' | crontab -"