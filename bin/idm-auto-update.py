#!/usr/bin/env python3
"""
IDM Auto-Updater for Claude Code Hooks

This script automatically updates IDM (Integrated Development Memory) logs
based on file changes detected in PostToolUse hooks. It provides intelligent
semantic analysis of code changes and generates appropriate IDM log entries.

Usage:
    bin/idm-auto-update.py post-edit    # After file edits
    bin/idm-auto-update.py post-test     # After test runs
    bin/idm-auto-update.py post-deploy   # After deployments
"""

import json
import sys
import os
import subprocess
import re
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

class IDMAutoUpdater:
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
        print(f"IDM Auto-Updater Error: {message}", file=sys.stderr)
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
        
    def analyze_file_changes(self, input_data: Dict) -> Dict:
        """Analyze the changes made to understand what was done"""
        tool_name = input_data.get("tool_name", "")
        tool_input = input_data.get("tool_input", {})
        file_path = self.get_file_path(input_data)
        
        analysis = {
            "tool_name": tool_name,
            "file_path": file_path,
            "action_type": "unknown",
            "description": "File modified",
            "changes": []
        }
        
        # Analyze based on tool type
        if tool_name == "Write":
            analysis["action_type"] = "file_creation" if not os.path.exists(file_path) else "file_rewrite"
            analysis["description"] = f"{'Created' if analysis['action_type'] == 'file_creation' else 'Rewrote'} {os.path.basename(file_path)}"
            
        elif tool_name in ["Edit", "MultiEdit"]:
            analysis["action_type"] = "file_edit"
            analysis["description"] = f"Modified {os.path.basename(file_path)}"
            
            # Try to extract edit details
            if tool_name == "Edit":
                old_string = tool_input.get("old_string", "")
                new_string = tool_input.get("new_string", "")
                if old_string and new_string:
                    analysis["changes"].append({
                        "type": "replacement",
                        "old": old_string[:100] + "..." if len(old_string) > 100 else old_string,
                        "new": new_string[:100] + "..." if len(new_string) > 100 else new_string
                    })
            elif tool_name == "MultiEdit":
                edits = tool_input.get("edits", [])
                for edit in edits:
                    old_str = edit.get("old_string", "")
                    new_str = edit.get("new_string", "")
                    analysis["changes"].append({
                        "type": "replacement",
                        "old": old_str[:100] + "..." if len(old_str) > 100 else old_str,
                        "new": new_str[:100] + "..." if len(new_str) > 100 else new_str
                    })
                    
        return analysis
        
    def detect_change_patterns(self, analysis: Dict) -> Dict:
        """Detect common change patterns to generate better descriptions"""
        patterns = {
            "bug_fix": ["fix", "error", "bug", "issue", "problem", "correct"],
            "feature_addition": ["add", "new", "implement", "create", "build"],
            "refactor": ["refactor", "improve", "optimize", "clean", "reorganize"],
            "style_update": ["style", "format", "css", "design", "ui", "ux"],
            "test_update": ["test", "spec", "rspec", "jest", "assert"],
            "config_change": ["config", "setting", "environment", "env", "yaml"],
            "dependency_update": ["gem", "npm", "package", "dependency", "library"],
            "documentation": ["comment", "doc", "readme", "documentation", "guide"]
        }
        
        detected_patterns = []
        text_to_analyze = f"{analysis['description']} {analysis['file_path']}"
        
        for change in analysis.get("changes", []):
            text_to_analyze += f" {change.get('old', '')} {change.get('new', '')}"
            
        text_to_analyze = text_to_analyze.lower()
        
        for pattern_name, keywords in patterns.items():
            if any(keyword in text_to_analyze for keyword in keywords):
                detected_patterns.append(pattern_name)
                
        return {
            "patterns": detected_patterns,
            "primary_pattern": detected_patterns[0] if detected_patterns else "general_change"
        }
        
    def generate_idm_log_entry(self, analysis: Dict, patterns: Dict, tracking_info: Dict) -> Dict:
        """Generate an IDM log entry based on the analysis"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Generate action description
        primary_pattern = patterns["primary_pattern"]
        file_name = os.path.basename(analysis["file_path"])
        
        action_templates = {
            "bug_fix": f"Fixed issue in {file_name}",
            "feature_addition": f"Added functionality to {file_name}",
            "refactor": f"Refactored {file_name}",
            "style_update": f"Updated styling in {file_name}",
            "test_update": f"Updated tests in {file_name}",
            "config_change": f"Modified configuration in {file_name}",
            "dependency_update": f"Updated dependencies in {file_name}",
            "documentation": f"Updated documentation in {file_name}",
            "general_change": f"Modified {file_name}"
        }
        
        action = action_templates.get(primary_pattern, action_templates["general_change"])
        
        # Generate decision explanation
        decision_templates = {
            "bug_fix": "Fixed identified issue to resolve functionality problem",
            "feature_addition": "Implemented new feature as per requirements",
            "refactor": "Improved code structure and maintainability",
            "style_update": "Enhanced user interface and visual design",
            "test_update": "Ensured code quality and test coverage",
            "config_change": "Updated configuration for proper functionality",
            "dependency_update": "Updated dependencies for security and features",
            "documentation": "Improved code documentation and clarity",
            "general_change": "Made necessary changes to implement functionality"
        }
        
        decision = decision_templates.get(primary_pattern, decision_templates["general_change"])
        
        # Generate code reference
        code_ref = f"{file_name}"
        
        # Create IDM log entry
        log_entry = {
            "timestamp": timestamp,
            "action": action,
            "decision": decision,
            "code_ref": code_ref,
            "status": "completed",
            "tool_info": {
                "tool_name": analysis["tool_name"],
                "patterns": patterns["patterns"],
                "changes_count": len(analysis.get("changes", []))
            }
        }
        
        return log_entry
        
    def update_idm_log(self, feature_id: str, log_entry: Dict) -> bool:
        """Update IDM log using Ruby integration"""
        try:
            # Create a temporary Ruby script to update IDM
            class_name = "".join(word.capitalize() for word in feature_id.split("_"))
            ruby_script = f"""
require_relative '{self.project_root}/config/environment'

feature_class = "FeatureMemories::{class_name}".constantize
memory = feature_class.new

memory.log_step(
  "{log_entry['action']}",
  decision: "{log_entry['decision']}",
  code_ref: "{log_entry['code_ref']}",
  status: :{log_entry['status']},
  auto_generated: true,
  tool_info: {log_entry['tool_info']}
)

puts "IDM log updated successfully"
"""
            
            # Write temporary script
            temp_script_path = os.path.join(self.project_root, "tmp", "idm_auto_update.rb")
            os.makedirs(os.path.dirname(temp_script_path), exist_ok=True)
            
            with open(temp_script_path, 'w') as f:
                f.write(ruby_script)
                
            # Execute Ruby script
            result = subprocess.run(
                ["ruby", temp_script_path],
                capture_output=True,
                text=True,
                cwd=self.project_root
            )
            
            # Clean up temp script
            os.remove(temp_script_path)
            
            return result.returncode == 0
            
        except Exception as e:
            print(f"Error updating IDM log: {e}", file=sys.stderr)
            return False
            
    def generate_user_notification(self, log_entry: Dict, feature_id: str) -> str:
        """Generate user notification about IDM update"""
        return f"""
📝 IDM AUTO-UPDATE COMPLETED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ IDM Log Updated for Feature: {feature_id}

Action: {log_entry['action']}
Decision: {log_entry['decision']}
Code Reference: {log_entry['code_ref']}
Status: {log_entry['status']}
Timestamp: {log_entry['timestamp']}

Auto-generated by IDM Auto-Updater
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
        
    def handle_post_edit(self, input_data: Dict):
        """Handle post-edit hook (automatically update IDM logs)"""
        file_path = self.get_file_path(input_data)
        
        if not file_path:
            self.exit_with_json({"continue": True})
            
        tracking_info = self.check_idm_tracking(file_path)
        
        if not tracking_info:
            # File not tracked by IDM - no action needed
            self.exit_with_json({"continue": True})
            
        # Analyze the changes
        analysis = self.analyze_file_changes(input_data)
        patterns = self.detect_change_patterns(analysis)
        
        # Generate IDM log entry
        log_entry = self.generate_idm_log_entry(analysis, patterns, tracking_info)
        
        # Update IDM log
        success = self.update_idm_log(tracking_info["feature_id"], log_entry)
        
        if success:
            notification = self.generate_user_notification(log_entry, tracking_info["feature_id"])
            print(notification)
            
        response = {
            "continue": True,
            "suppressOutput": False
        }
        
        self.exit_with_json(response)
        
    def handle_post_test(self, input_data: Dict):
        """Handle post-test hook (update IDM with test results)"""
        # For now, just continue - could be enhanced to parse test results
        self.exit_with_json({"continue": True})
        
    def handle_post_deploy(self, input_data: Dict):
        """Handle post-deploy hook (update IDM with deployment status)"""
        # For now, just continue - could be enhanced to track deployments
        self.exit_with_json({"continue": True})
        
    def main(self):
        """Main entry point"""
        if len(sys.argv) < 2:
            self.exit_with_error("Usage: idm-auto-update.py <command>")
            
        command = sys.argv[1]
        input_data = self.get_input_data()
        
        # Route to appropriate handler
        if command == "post-edit":
            self.handle_post_edit(input_data)
        elif command == "post-test":
            self.handle_post_test(input_data)
        elif command == "post-deploy":
            self.handle_post_deploy(input_data)
        else:
            self.exit_with_error(f"Unknown command: {command}")

if __name__ == "__main__":
    updater = IDMAutoUpdater()
    updater.main()