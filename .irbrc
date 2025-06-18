# IRB Configuration for enhanced console experience
require 'irb/completion'

# Enable history
IRB.conf[:SAVE_HISTORY] = 1000
IRB.conf[:HISTORY_FILE] = File.expand_path('~/.irb_history')

# Enable autocomplete
IRB.conf[:USE_AUTOCOMPLETE] = true

# Use colorized output
IRB.conf[:USE_COLORIZE] = true

# Show multiline
IRB.conf[:USE_MULTILINE] = true

# Set prompt
IRB.conf[:PROMPT_MODE] = :DEFAULT

# Load awesome_print if available
begin
  require 'awesome_print'
  AwesomePrint.defaults = {
    indent: 2,
    raw: false,
    sort_keys: true,
    color: {
      string: :yellow,
      fixnum: :cyan,
      float: :cyan,
      true: :green,
      false: :red
    }
  }
  # Use awesome_print for output in IRB
  IRB.conf[:USE_INSPECT] = false
  module IRB
    module ExtendCommandBundle
      def ap(*args)
        args.each { |arg| puts arg.ai }
        nil
      end
    end
  end
rescue LoadError
  puts "awesome_print not loaded"
end

# If in Rails environment, add helpful methods
if defined?(Rails)
  puts "Rails #{Rails.version} loaded in #{Rails.env} environment"
  
  # Add model shortcuts
  def reload!
    Rails.application.reloader.reload!
  end
  
  if defined?(User)
    def u
      User.first
    end
  end
  
  if defined?(Company)
    def c
      Company.first
    end
    
    def companies(limit = 5)
      Company.limit(limit)
    end
  end
  
  if defined?(Domain)
    def d
      Domain.first
    end
    
    def domains(limit = 5)
      Domain.limit(limit)
    end
  end
end