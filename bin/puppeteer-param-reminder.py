#!/usr/bin/env python3
"""
Puppeteer Parameter Reminder Hook
This hook reminds Claude to use the correct viewport parameters when using MCP Puppeteer tools.
"""

import sys
import json
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: puppeteer-param-reminder.py <tool_name>")
        sys.exit(1)
    
    tool_name = sys.argv[1]
    
    # Check if this is a Puppeteer tool
    if tool_name.startswith('mcp__puppeteer__'):
        
        # Read the input data if provided
        input_data = {}
        if len(sys.argv) > 2:
            try:
                input_data = json.loads(sys.argv[2])
            except:
                pass
        
        # Check for viewport parameters
        needs_reminder = False
        
        if tool_name == 'mcp__puppeteer__puppeteer_navigate':
            launch_options = input_data.get('launchOptions', {})
            viewport = launch_options.get('defaultViewport', {})
            
            if viewport.get('width') != 1920 or viewport.get('height') != 1080:
                needs_reminder = True
                
        elif tool_name == 'mcp__puppeteer__puppeteer_screenshot':
            width = input_data.get('width', 800)
            height = input_data.get('height', 600)
            
            if width != 1920 or height != 1080:
                needs_reminder = True
        
        if needs_reminder:
            reminder = f"""
🖥️ PUPPETEER VIEWPORT REMINDER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You're using {tool_name} without the required large viewport parameters!

Required parameters:
"""
            
            if tool_name == 'mcp__puppeteer__puppeteer_navigate':
                reminder += """
launchOptions: {
  headless: false,
  defaultViewport: { width: 1920, height: 1080 },
  args: ["--window-size=1920,1080", "--start-maximized"]
}
"""
            elif tool_name == 'mcp__puppeteer__puppeteer_screenshot':
                reminder += """
width: 1920,
height: 1080
"""
            
            reminder += """
⚠️ Screenshots without these parameters will be too small and incomplete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            
            print(reminder)
    
    # Allow the tool to continue
    print(json.dumps({"continue": True}))

if __name__ == "__main__":
    main()