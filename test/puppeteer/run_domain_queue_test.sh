#!/bin/bash

echo "🚀 Domain Queue Integration Test Runner"
echo "======================================"
echo ""

# Change to project directory
cd /Users/benjamin/Documents/Projects/b2b

# Ensure Rails server is running
echo "📦 Ensuring Rails server is running..."
bundle exec rake dev:status

# Check if server is running
if ! curl -s https://local.connectica.no > /dev/null; then
    echo "❌ Rails server is not running. Starting it now..."
    bundle exec rake dev
    sleep 5
fi

# Ensure Sidekiq is running
echo "📦 Checking Sidekiq status..."
if ! ps aux | grep -v grep | grep sidekiq > /dev/null; then
    echo "⚠️  Sidekiq is not running. Please start it with: bundle exec sidekiq"
    echo "    The test will continue but queue processing won't work properly."
fi

# Clear any existing test domains
echo "🧹 Cleaning up any existing test domains..."
bundle exec rails runner 'Domain.where("domain LIKE ?", "test-domain-%").destroy_all'

# Run the Puppeteer test
echo ""
echo "🎬 Running Puppeteer integration test..."
echo ""
node test/puppeteer/domain_queue_integration_test.js

echo ""
echo "✅ Test runner completed"