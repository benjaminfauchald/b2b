#!/bin/bash
# Claude Code pre-read hook to show IDM status

FILE_PATH="$1"
PROJECT_ROOT="/Users/benjamin/Documents/Projects/b2b"

# Check if file has IDM tracking
if [[ -f "$FILE_PATH" ]] && grep -q "Feature tracked by IDM:" "$FILE_PATH" 2>/dev/null; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📋 This file is tracked by IDM"
  
  # Extract the IDM file path
  IDM_PATH=$(grep "Feature tracked by IDM:" "$FILE_PATH" | sed 's/.*Feature tracked by IDM: //' | tr -d '#' | xargs)
  FEATURE_ID=$(basename "$IDM_PATH" .rb)
  
  echo "Feature: $FEATURE_ID"
  echo ""
  echo "Quick commands:"
  echo "• rails idm:status[$FEATURE_ID] - Check current status"
  echo "• rails idm:find[$FEATURE_ID] - Find all related files"
  echo "• Read docs/IDM_RULES.md for IDM guidelines"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

exit 0