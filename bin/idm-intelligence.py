#!/usr/bin/env python3
"""
IDM Intelligence Engine for Claude Code Hooks

This script provides intelligent IDM (Integrated Development Memory) integration
for Claude Code hooks. It enforces IDM workflows and ensures proper feature
tracking throughout the development process.

Usage:
    bin/idm-intelligence.py pre-read    # Before reading files
    bin/idm-intelligence.py pre-edit    # Before editing files
    bin/idm-intelligence.py pre-task    # Before Task tool usage
    bin/idm-intelligence.py stop-check  # Before stopping/completion
"""

import json
import sys
import os
import subprocess
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class IDMIntelligence:
    def __init__(self, project_root: str = None):
        self.project_root = project_root or "/Users/benjamin/Documents/Projects/b2b"
        self.idm_memories_path = os.path.join(self.project_root, "app/services/feature_memories")
        
    def get_input_data(self) -> Dict:
        """Parse JSON input from stdin"""
        try:
            return json.load(sys.stdin)
        except json.JSONDecodeError as e:
            self.exit_with_error(f"Invalid JSON input: {e}")
            
    def exit_with_error(self, message: str, exit_code: int = 1):
        """Exit with error message"""
        print(f"IDM Intelligence Error: {message}", file=sys.stderr)
        sys.exit(exit_code)
        
    def exit_with_json(self, response: Dict, exit_code: int = 0):
        """Exit with JSON response"""
        print(json.dumps(response, indent=2))
        sys.exit(exit_code)
        
    def get_file_path(self, input_data: Dict) -> Optional[str]:
        """Extract file path from tool input"""
        tool_input = input_data.get("tool_input", {})
        
        # Handle different tool types
        if "file_path" in tool_input:
            return tool_input["file_path"]
        elif "notebook_path" in tool_input:
            return tool_input["notebook_path"]
        elif "path" in tool_input:
            return tool_input["path"]
        
        return None
        
    def check_idm_tracking(self, file_path: str) -> Optional[Dict]:
        """Check if file is tracked by IDM and return tracking info"""
        if not file_path or not os.path.exists(file_path):
            return None
            
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Look for IDM tracking comment
            idm_pattern = r'Feature tracked by IDM:\s*([^\n\r]+)'
            match = re.search(idm_pattern, content)
            
            if match:
                idm_path = match.group(1).strip()
                feature_id = os.path.basename(idm_path).replace('.rb', '')
                
                return {
                    "tracked": True,
                    "idm_path": idm_path,
                    "feature_id": feature_id,
                    "full_idm_path": os.path.join(self.project_root, idm_path)
                }
                
        except Exception as e:
            pass
            
        return None
        
    def get_idm_status(self, feature_id: str) -> Dict:
        """Get IDM status for a feature"""
        try:
            # Run rails command to get IDM status
            cmd = ["rails", "idm:status", f"[{feature_id}]"]
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)
            
            if result.returncode == 0:
                return {
                    "available": True,
                    "output": result.stdout,
                    "error": None
                }
            else:
                return {
                    "available": False,
                    "output": result.stdout,
                    "error": result.stderr
                }
        except Exception as e:
            return {
                "available": False,
                "output": "",
                "error": str(e)
            }
            
    def detect_new_feature_work(self, input_data: Dict) -> Optional[Dict]:
        """Detect if this might be new feature work that needs IDM tracking"""
        tool_name = input_data.get("tool_name", "")
        tool_input = input_data.get("tool_input", {})
        
        # Check Task tool for new feature work
        if tool_name == "Task":
            prompt = tool_input.get("prompt", "").lower()
            feature_keywords = [
                "implement", "create", "add", "build", "develop", "new feature",
                "enhancement", "functionality", "service", "component", "api",
                "integration", "workflow", "system", "module"
            ]
            
            if any(keyword in prompt for keyword in feature_keywords):
                return {
                    "likely_new_feature": True,
                    "keywords_found": [kw for kw in feature_keywords if kw in prompt],
                    "prompt": prompt
                }
                
        # Check file operations for new feature patterns
        elif tool_name in ["Write", "Edit", "MultiEdit"]:
            file_path = self.get_file_path(input_data)
            if file_path:
                # Only flag as new feature if it's a NEW file (Write operation)
                if tool_name == "Write" and not os.path.exists(file_path):
                    # Check if it's in feature-related directories
                    feature_dirs = [
                        "app/services/", "app/components/", "app/controllers/",
                        "app/workers/", "app/lib/", "app/javascript/"
                    ]
                    
                    if any(dir_path in file_path for dir_path in feature_dirs):
                        return {
                            "likely_new_feature": True,
                            "file_path": file_path,
                            "reason": "New file in feature directory"
                        }
                
                # For Edit/MultiEdit, check if content suggests major new feature
                # This is more conservative - only flag obvious new features
                elif tool_name in ["Edit", "MultiEdit"]:
                    tool_input = input_data.get("tool_input", {})
                    new_content = tool_input.get("new_string", "") or tool_input.get("content", "")
                    
                    # Look for class/module creation patterns
                    if new_content:
                        new_feature_patterns = [
                            r"class\s+\w+.*<.*Service",
                            r"class\s+\w+.*Component",
                            r"module\s+\w+.*",
                            r"def\s+initialize.*service",
                            r"ApplicationService",
                            r"ViewComponent"
                        ]
                        
                        if any(re.search(pattern, new_content, re.IGNORECASE) for pattern in new_feature_patterns):
                            return {
                                "likely_new_feature": True,
                                "file_path": file_path,
                                "reason": "New class/service/component detected"
                            }
                    
        return None
        
    def format_idm_guidance(self, tracking_info: Dict, idm_status: Dict) -> str:
        """Format IDM guidance message"""
        feature_id = tracking_info["feature_id"]
        
        guidance = f"""
🚨 IDM ENFORCEMENT ACTIVE 🚨
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Feature: {feature_id}
📁 IDM File: {tracking_info['idm_path']}

REQUIRED ACTIONS BEFORE PROCEEDING:
1. Check IDM status: rails idm:status[{feature_id}]
2. Follow IDM Communication Protocol in CLAUDE.md
3. Update IDM implementation_log after changes

IDM Status Check:
{idm_status.get('output', 'Unable to retrieve status')}

To continue, you MUST:
✅ Acknowledge IDM requirements
✅ Show IDM plan status to user
✅ Follow IDM workflow throughout development

Emergency bypass: Set SKIP_IDM=1 (NOT RECOMMENDED)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
        return guidance
        
    def format_new_feature_guidance(self, detection: Dict) -> str:
        """Format guidance for potential new feature work"""
        return f"""
🔍 POTENTIAL NEW FEATURE DETECTED 🔍
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This appears to be new feature work that may need IDM tracking.

REQUIRED ACTIONS:
1. Search for existing IDM: rails idm:find[feature_keyword]
2. If no IDM exists, create one: rails generate feature_memory feature_name "Description"
3. Follow IDM workflow as documented in CLAUDE.md

Detection Details:
{json.dumps(detection, indent=2)}

IDM is MANDATORY for all feature development.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
        
    def handle_pre_read(self, input_data: Dict):
        """Handle pre-read hook"""
        file_path = self.get_file_path(input_data)
        
        if not file_path:
            self.exit_with_json({"continue": True})
            
        tracking_info = self.check_idm_tracking(file_path)
        
        if tracking_info:
            # File is IDM tracked - show status
            idm_status = self.get_idm_status(tracking_info["feature_id"])
            
            response = {
                "continue": True,
                "suppressOutput": False
            }
            
            guidance = f"""
📋 IDM-TRACKED FILE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Feature: {tracking_info['feature_id']}
IDM File: {tracking_info['idm_path']}

Quick Commands:
• rails idm:status[{tracking_info['feature_id']}] - Check current status
• rails idm:find[{tracking_info['feature_id']}] - Find all related files
• Read docs/IDM_RULES.md for IDM guidelines

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            
            print(guidance)
            self.exit_with_json(response)
        else:
            # File is not IDM tracked - normal read
            self.exit_with_json({"continue": True})
            
    def handle_pre_edit(self, input_data: Dict):
        """Handle pre-edit hook (non-blocking, only shows info for IDM-tracked files)"""
        file_path = self.get_file_path(input_data)
        
        if not file_path:
            self.exit_with_json({"continue": True})
            
        tracking_info = self.check_idm_tracking(file_path)
        
        if tracking_info:
            # File is IDM tracked - show info but don't block
            idm_status = self.get_idm_status(tracking_info["feature_id"])
            
            info_message = f"""
📋 IDM-TRACKED FILE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Feature: {tracking_info['feature_id']}
IDM File: {tracking_info['idm_path']}

Quick Commands:
• rails idm:status[{tracking_info['feature_id']}] - Check current status
• rails idm:find[{tracking_info['feature_id']}] - Find all related files

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            
            print(info_message)
            self.exit_with_json({"continue": True})
        else:
            # Normal file - allow edit with no blocking
            self.exit_with_json({"continue": True})
                
    def handle_pre_task(self, input_data: Dict):
        """Handle pre-task hook (non-blocking, shows guidance for feature work)"""
        # Check if this is feature-related work
        detection = self.detect_new_feature_work(input_data)
        
        if detection:
            guidance = f"""
💡 FEATURE WORK DETECTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This looks like feature development work.

Consider using IDM tracking:
• rails idm:find[feature_keyword] - Search for existing IDM
• rails generate feature_memory feature_name "Description" - Create new IDM

Detection: {detection.get('prompt', 'Feature work detected')}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            print(guidance)
            self.exit_with_json({"continue": True})
        else:
            # Normal task - allow execution
            self.exit_with_json({"continue": True})
            
    def handle_post_edit(self, input_data: Dict):
        """Handle post-edit hook (helpful context gathering after edit)"""
        file_path = self.get_file_path(input_data)
        
        if not file_path:
            self.exit_with_json({"continue": True})
            
        tracking_info = self.check_idm_tracking(file_path)
        
        if tracking_info:
            # File is IDM tracked - remind about logging
            feature_id = tracking_info["feature_id"]
            
            reminder = f"""
📝 IDM UPDATE REMINDER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You've edited an IDM-tracked file: {os.path.basename(file_path)}
Feature: {feature_id}

Consider updating the IDM log with:

memory = FeatureMemories::{feature_id.upper().replace('-', '_')}
memory.log_step("Your description here",
                decision: "Why you made this change",
                code_ref: "{os.path.basename(file_path)}:LINE_NUMBER",
                status: :in_progress)

Or run: rails idm:status[{feature_id}]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            
            print(reminder)
            self.exit_with_json({"continue": True})
        else:
            # Check if this might be feature work worth tracking
            detection = self.detect_new_feature_work(input_data)
            
            if detection:
                suggestion = f"""
💡 CHANGE DETECTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You've edited: {os.path.basename(file_path)}

Was this:
□ Bug fix
□ New feature
□ Refactoring
□ Performance improvement
□ Other

Consider tracking significant changes with IDM:
• rails generate feature_memory feature_name "Description"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
                
                print(suggestion)
                self.exit_with_json({"continue": True})
            else:
                # Normal edit - no action needed
                self.exit_with_json({"continue": True})
            
    def handle_stop_check(self, input_data: Dict):
        """Handle stop/completion check (ensures IDM is properly updated)"""
        # Check if there are any IDM-tracked files that might need updates
        # This is a basic implementation - could be enhanced with more sophisticated tracking
        
        response = {
            "continue": True,
            "suppressOutput": False
        }
        
        reminder = """
📝 IDM COMPLETION REMINDER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Before completing work, ensure:
✅ All IDM logs are updated with recent changes
✅ Task statuses are properly set
✅ Implementation decisions are documented

Quick check: rails idm:list
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
        
        print(reminder)
        self.exit_with_json(response)
        
    def main(self):
        """Main entry point"""
        if len(sys.argv) < 2:
            self.exit_with_error("Usage: idm-intelligence.py <command>")
            
        command = sys.argv[1]
        input_data = self.get_input_data()
        
        # Route to appropriate handler
        if command == "pre-read":
            self.handle_pre_read(input_data)
        elif command == "pre-edit":
            self.handle_pre_edit(input_data)
        elif command == "post-edit":
            self.handle_post_edit(input_data)
        elif command == "pre-task":
            self.handle_pre_task(input_data)
        elif command == "stop-check":
            self.handle_stop_check(input_data)
        else:
            self.exit_with_error(f"Unknown command: {command}")

if __name__ == "__main__":
    intelligence = IDMIntelligence()
    intelligence.main()