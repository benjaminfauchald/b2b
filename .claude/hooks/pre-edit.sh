#!/bin/bash
# Claude Code pre-edit hook to enforce IDM usage

# This hook runs before any file edit in the b2b project
# It checks if the file being edited has IDM tracking and enforces IDM workflow

FILE_PATH="$1"
PROJECT_ROOT="/Users/benjamin/Documents/Projects/b2b"

# Check if we're in the b2b project
if [[ "$PWD" == "$PROJECT_ROOT"* ]]; then
  # Check if the file has IDM tracking indicator
  if grep -q "Feature tracked by IDM:" "$FILE_PATH" 2>/dev/null; then
    echo "⚠️  IDM ENFORCEMENT HOOK TRIGGERED ⚠️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This file is tracked by IDM (Integrated Development Memory)"
    echo ""
    
    # Extract the IDM file path from the comment
    IDM_PATH=$(grep "Feature tracked by IDM:" "$FILE_PATH" | sed 's/.*Feature tracked by IDM: //' | tr -d '#' | xargs)
    
    if [[ -f "$PROJECT_ROOT/$IDM_PATH" ]]; then
      echo "📋 IDM File: $IDM_PATH"
      
      # Extract feature ID from the IDM path
      FEATURE_ID=$(basename "$IDM_PATH" .rb)
      
      echo "🔍 Feature ID: $FEATURE_ID"
      echo ""
      echo "REQUIRED ACTIONS:"
      echo "1. Run: rails idm:status[$FEATURE_ID]"
      echo "2. Update IDM implementation_log after changes"
      echo "3. Follow IDM Communication Protocol in CLAUDE.md"
      echo ""
      echo "To continue without IDM (NOT RECOMMENDED):"
      echo "Set SKIP_IDM=1 environment variable"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      
      # Block the edit unless SKIP_IDM is set
      if [[ "$SKIP_IDM" != "1" ]]; then
        echo ""
        echo "❌ EDIT BLOCKED: You must acknowledge IDM requirements first"
        echo "   Please read the IDM status and plan before making changes"
        exit 1
      fi
    fi
  fi
fi

exit 0