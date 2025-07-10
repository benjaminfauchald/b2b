#!/bin/bash

# LinkedIn Discovery Postal Code 3-Company Test Runner
# Tests the postal code LinkedIn discovery functionality

echo "🗺️  LinkedIn Discovery Postal Code Test"
echo "========================================"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js to run Puppeteer tests."
    exit 1
fi

# Check if puppeteer is installed
if ! npm list puppeteer &> /dev/null; then
    echo "📦 Installing Puppeteer..."
    npm install puppeteer
fi

# Change to test directory
cd "$(dirname "$0")"

echo "🚀 Starting LinkedIn Discovery Postal Code test..."
echo "📋 This test will:"
echo "   1. Login to the application"
echo "   2. Navigate to companies page"
echo "   3. Find LinkedIn Discovery by Postal Code component"
echo "   4. Select postal code 2000 (Lillestrøm)"
echo "   5. Set batch size to 3 companies"
echo "   6. Queue companies for LinkedIn discovery"
echo "   7. Verify the queueing works correctly"
echo ""

# Run the test
node linkedin_discovery_postal_code_3_companies_test.js

# Check exit code
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Test completed successfully!"
    echo "📸 Screenshots saved in /tmp/"
    echo "   - postal_code_before_test.png"
    echo "   - postal_code_after_queue.png"
else
    echo ""
    echo "❌ Test failed!"
    echo "📸 Check error screenshot: /tmp/postal_code_test_error.png"
    exit 1
fi