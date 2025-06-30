# Guard configuration file for enhanced notifications

# Configure notification settings
notification :terminal_notifier, sticky: true, activate: 'com.googlecode.iterm2' if `uname`.chomp == 'Darwin'

# Set Guard options
Guard.options[:clear] = true
Guard.options[:notify] = true

# Callback for test results
Guard::Notifier.turn_on

# Custom notification configuration for macOS
if RUBY_PLATFORM.downcase.include?('darwin')
  require 'terminal-notifier-guard'
  
  # Configure terminal-notifier-guard for traffic light notifications
  TerminalNotifier::Guard.setup do
    # Green light for passing tests
    success_image = "✅"
    # Red light for failing tests  
    failure_image = "❌"
    # Yellow light for pending/warnings
    pending_image = "⚠️"
    
    # Set notification sounds
    success_sound = "Glass"
    failure_sound = "Basso"
    pending_sound = "Funk"
  end
end