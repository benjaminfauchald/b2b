#!/bin/bash
# Script to set up local.connectica.no domain mapping

echo "🔧 Setting up local.connectica.no domain mapping..."

# Check if the entry already exists
if grep -q "local.connectica.no" /etc/hosts; then
    echo "✅ local.connectica.no is already configured"
else
    echo "📝 Adding local.connectica.no to /etc/hosts (requires sudo)"
    echo "127.0.0.1 local.connectica.no" | sudo tee -a /etc/hosts
    echo "✅ Added local.connectica.no mapping"
fi

echo ""
echo "🌐 You can now access the application at:"
echo "   http://local.connectica.no:3000"
echo ""
echo "⚠️  Note: This gives you HTTP access. For HTTPS, you'll need to set up SSL."