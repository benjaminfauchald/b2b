# Pry Configuration for enhanced console experience
Pry.config.editor = 'vim'

# Enable color
Pry.config.color = true

# History settings
Pry.config.history_save = true
Pry.config.history_load = true
Pry.config.history_file = "~/.pry_history"

# Use awesome_print for output
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
      false: :red,
      nil: :magenta
    }
  }
  Pry.config.print = proc { |output, value| output.puts value.ai }
rescue LoadError
  puts "awesome_print not loaded"
end

# Enable Rails helpers if in Rails console
if defined?(Rails)
  puts "Rails #{Rails.version} console loaded in #{Rails.env} environment 🚀"
  
  begin
    require 'rails/console/app'
    require 'rails/console/helpers'
    extend Rails::ConsoleMethods if defined?(Rails::ConsoleMethods)
  rescue LoadError
    # Rails console helpers not available
  end
  
  # Add useful aliases and shortcuts
  def reload!
    puts "🔄 Reloading Rails application..."
    Rails.application.reloader.reload!
    puts "✅ Reload complete!"
  end
  
  if defined?(User)
    def u
      User.first
    end
    
    def users(limit = 5)
      User.limit(limit)
    end
  end

  if defined?(Company)
    def c
      Company.first
    end
    
    def companies(limit = 5)
      Company.limit(limit)
    end
    
    def company_stats
      puts "📊 Company Statistics:"
      puts "Total companies: #{Company.count}"
      puts "With financial data: #{Company.where.not(ordinary_result: nil).count}"
      puts "Norwegian companies: #{Company.where(source_country: 'NO').count}"
    end
  end

  if defined?(Domain)
    def d
      Domain.first
    end
    
    def domains(limit = 5)
      Domain.limit(limit)
    end
    
    def domain_stats
      puts "🌐 Domain Statistics:"
      puts "Total domains: #{Domain.count}"
      puts "With MX records: #{Domain.where(mx: true).count}"
      puts "With WWW: #{Domain.where(www: true).count}"
    end
  end
  
  # Database shortcuts
  def db_stats
    puts "🗄️  Database Statistics:"
    ActiveRecord::Base.connection.tables.each do |table|
      count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}")
      puts "#{table}: #{count} records"
    end
  end
  
  # Quick model shortcuts
  def models
    puts "📋 Available Models:"
    Rails.application.eager_load!
    ApplicationRecord.descendants.map(&:name).sort.each do |model|
      puts "  #{model}"
    end
  end
end

# Custom commands
Pry::Commands.create_command "clear" do
  description "Clear the terminal screen"
  def process
    system('clear') || system('cls')
  end
end

# Enhanced tab completion for models
if defined?(Rails)
  # Add custom completion for common patterns
  Pry.config.completer = proc do |input, context|
    # Standard Pry completion
    completer = Pry::InputCompleter.new(context)
    completions = completer.call(input)
    
    # Add model completions
    if input =~ /^[A-Z]/
      Rails.application.eager_load! rescue nil
      model_names = ApplicationRecord.descendants.map(&:name) rescue []
      model_completions = model_names.select { |name| name.start_with?(input) }
      completions.concat(model_completions)
    end
    
    completions.uniq.sort
  end
end

# Welcome message
puts <<-BANNER
╔══════════════════════════════════════════════════════════════╗
║                    🏢 B2B Rails Console                     ║
║                                                              ║
║  Shortcuts:                                                  ║
║    c          -> Company.first                               ║
║    d          -> Domain.first                                ║
║    reload!    -> Reload Rails app                            ║
║    models     -> List all models                             ║
║    db_stats   -> Show database statistics                    ║
║                                                              ║
║  Enhanced with pry-rails & awesome_print                     ║
╚══════════════════════════════════════════════════════════════╝
BANNER