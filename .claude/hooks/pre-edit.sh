##!/bin/bash
format_output() {
  local message="$1"
  local exit_code="${2:-0}"
  
  if [[ -n "$CLAUDE_CODE_CONTEXT" ]] || [[ "$(ps -p $PPID -o comm= 2>/dev/null)" == *"claude-code"* ]]; then
    if [[ $exit_code -eq 1 ]]; then
      echo "{\"message\": \"$message\", \"blocked\": true}"
    else
      echo "{\"message\": \"$message\", \"blocked\": false}"
    fi
  else
    echo "$message"
  fi
}

FILE_PATH="$1"
PROJECT_ROOT="/Users/benjamin/Documents/Projects/b2b"

if [[ "$PWD" == "$PROJECT_ROOT"* ]]; then
  if grep -q "Feature tracked by IDM:" "$FILE_PATH" 2>/dev/null; then
    IDM_PATH=$(grep "Feature tracked by IDM:" "$FILE_PATH" | sed "s/.*Feature tracked by IDM: //" | tr -d "#" | xargs)
    if [[ -f "$PROJECT_ROOT/$IDM_PATH" ]]; then
      FEATURE_ID=$(basename "$IDM_PATH" .rb)
      BLOCK_MESSAGE="IDM ENFORCEMENT: File tracked by IDM. Feature: $FEATURE_ID. Set SKIP_IDM=1 to bypass."
      if [[ "$SKIP_IDM" != "1" ]]; then
        format_output "$BLOCK_MESSAGE" 1
        exit 1
      fi
    fi
  fi
fi

exit 0
