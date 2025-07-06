#!/bin/bash
# Claude Code post-edit hook to remind about IDM updates

FILE_PATH="$1"
PROJECT_ROOT="/Users/benjamin/Documents/Projects/b2b"

# Check if we're in the b2b project and file has IDM tracking
if [[ "$PWD" == "$PROJECT_ROOT"* ]] && grep -q "Feature tracked by IDM:" "$FILE_PATH" 2>/dev/null; then
  echo ""
  echo "📝 IDM REMINDER: File edit completed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Extract the IDM file path
  IDM_PATH=$(grep "Feature tracked by IDM:" "$FILE_PATH" | sed 's/.*Feature tracked by IDM: //' | tr -d '#' | xargs)
  FEATURE_ID=$(basename "$IDM_PATH" .rb)
  
  echo "Don't forget to update the IDM implementation log!"
  echo ""
  echo "Example Ruby code to add to your next message:"
  echo ""
  echo "memory = FeatureMemories::${FEATURE_ID^}"
  echo "memory.log_step(\"Fixed dark mode styling\","
  echo "                decision: \"Used Flowbite alert component patterns\","
  echo "                code_ref: \"$(basename $FILE_PATH):LINE_NUMBER\","
  echo "                status: :completed)"
  echo ""
  echo "Or run: rails idm:status[$FEATURE_ID]"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit 0