#!/usr/bin/env ruby

# Minimal Production Console - Direct database access without Rails initialization
# Usage: ruby scripts/minimal_console.rb

# Add the vendor/bundle path to load installed gems
$LOAD_PATH.unshift(File.expand_path('../vendor/bundle/ruby/3.3.0/gems', __dir__))

# Load required gems directly
require 'bundler/setup'
require 'pg'
require 'pry'

# Database configuration
DB_CONFIG = {
  host: 'app.connectica.no',
  port: 5432,
  dbname: 'b2b_production',
  user: 'benjamin',
  password: 'Charcoal2020!'
}

# Connect to database
begin
  puts "🔌 Connecting to production database..."
  @conn = PG.connect(DB_CONFIG)
  puts "✅ Connected successfully!"
rescue PG::Error => e
  puts "❌ Database connection failed: #{e.message}"
  exit 1
end

# Helper methods for common queries
def companies(limit = 5)
  result = @conn.exec("SELECT id, company_name, registration_number, website FROM companies LIMIT #{limit}")
  puts "📊 Companies (showing #{result.ntuples} of #{company_count}):"
  puts "-" * 80
  result.each do |row|
    puts "ID: #{row['id']}, Name: #{row['company_name']}, Reg: #{row['registration_number']}"
    puts "Website: #{row['website']}" if row['website']
    puts
  end
  nil
end

def domains(limit = 5)
  result = @conn.exec("SELECT id, domain, mx, www, dns, created_at FROM domains LIMIT #{limit}")
  puts "🌐 Domains (showing #{result.ntuples} of #{domain_count}):"
  puts "-" * 60
  result.each do |row|
    flags = []
    flags << "MX" if row['mx'] == 't'
    flags << "WWW" if row['www'] == 't'
    flags << "DNS" if row['dns'] == 't'
    puts "#{row['domain']} [#{flags.join(', ')}] (#{row['created_at']})"
  end
  nil
end

def company_count
  @conn.exec("SELECT COUNT(*) FROM companies")[0]['count'].to_i
end

def domain_count
  @conn.exec("SELECT COUNT(*) FROM domains")[0]['count'].to_i
end

def stats
  puts "📊 Database Statistics:"
  puts "=" * 50

  # Get all table counts
  tables_query = "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
  tables = @conn.exec(tables_query)

  tables.each do |table|
    table_name = table['table_name']
    count = @conn.exec("SELECT COUNT(*) FROM #{table_name}")[0]['count']
    puts "#{table_name.ljust(20)}: #{count.rjust(10)} records"
  end
  puts "=" * 50
  nil
end

def search_companies(name)
  result = @conn.exec_params(
    "SELECT id, company_name, registration_number, website FROM companies WHERE company_name ILIKE $1 LIMIT 10",
    [ "%#{name}%" ]
  )
  puts "🔍 Companies matching '#{name}':"
  puts "-" * 60
  result.each do |row|
    puts "#{row['company_name']} (#{row['registration_number']})"
    puts "Website: #{row['website']}" if row['website']
    puts
  end
  nil
end

def search_domains(domain)
  result = @conn.exec_params(
    "SELECT id, domain, mx, www, dns FROM domains WHERE domain ILIKE $1 LIMIT 10",
    [ "%#{domain}%" ]
  )
  puts "🔍 Domains matching '#{domain}':"
  puts "-" * 40
  result.each do |row|
    flags = []
    flags << "MX" if row['mx'] == 't'
    flags << "WWW" if row['www'] == 't'
    flags << "DNS" if row['dns'] == 't'
    puts "#{row['domain']} [#{flags.join(', ')}]"
  end
  nil
end

def query(sql)
  puts "🔍 Executing: #{sql}"
  begin
    result = @conn.exec(sql)
    if result.ntuples > 0
      puts "Found #{result.ntuples} results:"
      puts "-" * 60
      result.each_with_index do |row, i|
        puts "Row #{i + 1}:"
        row.each { |k, v| puts "  #{k}: #{v}" }
        puts
      end
    else
      puts "No results found."
    end
  rescue PG::Error => e
    puts "❌ Query failed: #{e.message}"
  end
  nil
end

# Welcome message
puts <<-BANNER
╔══════════════════════════════════════════════════════════════╗
║              🏢 B2B Production Database Console             ║
║                                                              ║
║  Direct PostgreSQL connection to production database         ║
║                                                              ║
║  Available methods:                                          ║
║    companies(10)           -> Show first 10 companies       ║
║    domains(10)             -> Show first 10 domains         ║
║    company_count           -> Total company count            ║
║    domain_count            -> Total domain count             ║
║    stats                   -> Show all table statistics     ║
║    search_companies('abc') -> Search companies by name      ║
║    search_domains('com')   -> Search domains                ║
║    query('SELECT ...')     -> Execute custom SQL            ║
║                                                              ║
║  Database: #{DB_CONFIG[:dbname]}@#{DB_CONFIG[:host]}                      ║
╚══════════════════════════════════════════════════════════════╝

BANNER

puts "📊 Quick stats:"
puts "   Companies: #{company_count}"
puts "   Domains: #{domain_count}"
puts ""
puts "🚀 Console ready! Type 'stats' for detailed table information."
puts ""

# Start pry console with database connection
Pry.start
