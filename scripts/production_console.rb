#!/usr/bin/env ruby

# Production Console Script - Bypasses credential issues
# Usage: ruby scripts/production_console.rb

# Set environment
ENV['RAILS_ENV'] = 'production'

# Add current directory to load path
$LOAD_PATH.unshift(File.expand_path('..', __dir__))

# Load bundler and gems first
require 'bundler'
Bundler.require(:default, :production)

# Load Rails components we need without full initialization
require 'active_record'
require 'active_support/all'

# Configure database connection directly
ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  encoding: 'unicode',
  pool: 5,
  database: 'b2b_production',
  host: 'app.connectica.no',
  port: 5432,
  username: 'benjamin',
  password: 'Charcoal2020!'
)

# Load our models
require_relative '../app/models/application_record'
Dir[File.expand_path('../app/models/*.rb', __dir__)].each { |f| require f }

# Set up awesome_print
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
rescue LoadError
  puts "awesome_print not loaded"
end

# Helper methods
def c
  Company.first
end

def companies(limit = 5)
  Company.limit(limit)
end

def d
  Domain.first
end

def domains(limit = 5)
  Domain.limit(limit)
end

def company_stats
  puts "📊 Company Statistics:"
  puts "Total companies: #{Company.count}"
  puts "With financial data: #{Company.where.not(ordinary_result: nil).count}"
  puts "Norwegian companies: #{Company.where(source_country: 'NO').count}"
end

def domain_stats
  puts "🌐 Domain Statistics:"
  puts "Total domains: #{Domain.count}"
  puts "With MX records: #{Domain.where(mx: true).count}"
  puts "With WWW: #{Domain.where(www: true).count}"
end

def db_stats
  puts "🗄️  Database Statistics:"
  ActiveRecord::Base.connection.tables.each do |table|
    count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}")
    puts "#{table}: #{count} records"
  end
end

# Welcome message
puts <<-BANNER
╔══════════════════════════════════════════════════════════════╗
║                🏢 B2B Production Console                    ║
║                                                              ║
║  Database: Connected to b2b_production                       ║
║                                                              ║
║  Shortcuts:                                                  ║
║    c               -> Company.first                          ║
║    companies(10)   -> Company.limit(10)                     ║
║    d               -> Domain.first                           ║
║    domains(10)     -> Domain.limit(10)                      ║
║    company_stats   -> Show company statistics                ║
║    domain_stats    -> Show domain statistics                 ║
║    db_stats        -> Show all table counts                  ║
║                                                              ║
║  Enhanced with awesome_print for beautiful output            ║
╚══════════════════════════════════════════════════════════════╝

BANNER

puts "🚀 Production environment loaded successfully!"
puts "📊 Quick stats:"
puts "   Companies: #{Company.count}"
puts "   Domains: #{Domain.count}"
puts ""

# Start pry console
require 'pry'
Pry.start
