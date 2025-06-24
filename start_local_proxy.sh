#!/bin/bash
# Script to start local proxy for local.connectica.no

echo "🔍 Checking proxy setup for local.connectica.no..."

# Check if Rails is running on port 3000
if lsof -ti:3000 > /dev/null; then
    echo "✅ Rails server is running on port 3000"
else
    echo "❌ Rails server is not running on port 3000"
    echo "   Starting Rails server..."
    ./bin/rake restart &
    sleep 5
fi

# Check if something is listening on port 80
if lsof -ti:80 > /dev/null 2>&1; then
    echo "✅ Something is listening on port 80"
    echo "   You should be able to access: http://local.connectica.no"
else
    echo "❌ Nothing is listening on port 80"
    echo ""
    echo "Options to set up the proxy:"
    echo ""
    echo "1. Using ngrok (if you have ngrok installed):"
    echo "   ngrok http 3000 --host-header=rewrite"
    echo ""
    echo "2. Using nginx (requires nginx installation):"
    echo "   brew install nginx (if not installed)"
    echo "   Then configure nginx to proxy local.connectica.no to localhost:3000"
    echo ""
    echo "3. Using Ruby's built-in proxy:"
    echo "   We can create a simple Ruby proxy server"
fi

echo ""
echo "Current status:"
echo "- Rails on port 3000: http://localhost:3000"
echo "- Direct access works: http://localhost:3000/companies"