#!/bin/bash

# Deploy to Production Script
# This script handles the complete deployment process:
# 1. Merges develop to master
# 2. Creates a version tag
# 3. Pushes everything to trigger deployment

set -e  # Exit on error

echo "🚀 Deploy to Production Script"
echo "=============================="

# Check if we're on develop branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "develop" ]; then
    echo "❌ Error: You must be on the 'develop' branch to deploy"
    echo "   Current branch: $CURRENT_BRANCH"
    echo "   Run: git checkout develop"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "❌ Error: You have uncommitted changes"
    echo "   Please commit or stash your changes first"
    exit 1
fi

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull origin develop

# Get the latest version tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo "📌 Latest version: $LATEST_TAG"

# Parse version components
VERSION_REGEX="^v([0-9]+)\.([0-9]+)\.([0-9]+)$"
if [[ $LATEST_TAG =~ $VERSION_REGEX ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
else
    echo "❌ Error: Invalid version format in tag: $LATEST_TAG"
    exit 1
fi

# Determine version bump type
echo ""
echo "Select version bump type:"
echo "1) Patch (v$MAJOR.$MINOR.$PATCH → v$MAJOR.$MINOR.$((PATCH + 1)))"
echo "2) Minor (v$MAJOR.$MINOR.$PATCH → v$MAJOR.$((MINOR + 1)).0)"
echo "3) Major (v$MAJOR.$MINOR.$PATCH → v$((MAJOR + 1)).0.0)"
echo -n "Enter choice [1-3] (default: 1): "
read -r BUMP_TYPE

case $BUMP_TYPE in
    2)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    3)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    *)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_VERSION="v$MAJOR.$MINOR.$PATCH"
echo "🏷️  New version: $NEW_VERSION"

# Get release notes
echo ""
echo "Enter release notes (press Ctrl+D when done):"
echo "Tip: Start with a summary, then use ## for sections like Features, Bug Fixes, etc."
echo ""
RELEASE_NOTES=$(cat)

if [ -z "$RELEASE_NOTES" ]; then
    # Generate automatic release notes from commits
    echo "📝 Generating release notes from commits..."
    RELEASE_NOTES="Release $NEW_VERSION

## Changes since $LATEST_TAG

$(git log --oneline $LATEST_TAG..HEAD | head -20)

## Deployment Info
- Deployed: $(date)
- Branch: develop → master
- Previous version: $LATEST_TAG

🤖 Generated automatically"
fi

# Confirm deployment
echo ""
echo "========================================"
echo "📋 Deployment Summary:"
echo "  Current version: $LATEST_TAG"
echo "  New version: $NEW_VERSION"
echo "  Commits to deploy: $(git rev-list --count $LATEST_TAG..HEAD)"
echo "========================================"
echo ""
echo -n "Deploy to production? [y/N]: "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo ""
echo "🚀 Starting deployment..."

# Checkout master and merge
echo "1️⃣ Switching to master branch..."
git checkout master
git pull origin master

echo "2️⃣ Merging develop into master..."
git merge develop --no-edit

# Create and push tag
echo "3️⃣ Creating version tag $NEW_VERSION..."
git tag -a "$NEW_VERSION" -m "$RELEASE_NOTES"

echo "4️⃣ Pushing to master (triggers deployment)..."
git push origin master

echo "5️⃣ Pushing version tag..."
git push origin "$NEW_VERSION"

# Create GitHub release if gh CLI is available
if command -v gh &> /dev/null; then
    echo "6️⃣ Creating GitHub release..."
    gh release create "$NEW_VERSION" \
        --title "$NEW_VERSION" \
        --notes "$RELEASE_NOTES" \
        2>/dev/null || echo "   ⚠️  Could not create GitHub release (check gh auth status)"
fi

# Switch back to develop
echo "7️⃣ Switching back to develop branch..."
git checkout develop
git pull origin develop

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Deployment Summary:"
echo "  • Version: $NEW_VERSION"
echo "  • Tag pushed: ✓"
echo "  • Deployment triggered: ✓"
echo "  • GitHub Actions: https://github.com/benjaminfauchald/b2b/actions"
echo ""
echo "📝 Next steps:"
echo "  1. Monitor deployment: https://github.com/benjaminfauchald/b2b/actions"
echo "  2. Verify production: [your-production-url]"
echo "  3. Check application version: [your-production-url]/version"
echo ""