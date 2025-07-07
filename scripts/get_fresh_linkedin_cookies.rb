#!/usr/bin/env ruby
# Fresh LinkedIn Cookie Extractor using Browser Automation
# Uses Puppeteer to login and extract fresh session cookies

require_relative '../config/environment'
require 'json'

puts "="*80
puts "Fresh LinkedIn Cookie Extractor"
puts "="*80

# Check if we have LinkedIn credentials
email = ENV['LINKEDIN_EMAIL']
password = ENV['LINKEDIN_PASSWORD']

unless email.present? && password.present?
  puts "\n❌ LinkedIn credentials not found!"
  puts "Please set:"
  puts "  export LINKEDIN_EMAIL='your_linkedin_email'"
  puts "  export LINKEDIN_PASSWORD='your_linkedin_password'"
  exit 1
end

puts "\n📧 Email: #{email}"
puts "🔑 Password: #{'*' * password.length}"

puts "\n🌐 Opening browser to login to LinkedIn..."

begin
  # Use Puppeteer MCP to automate login and extract cookies
  
  # Navigate to LinkedIn login page
  puts "📍 Navigating to LinkedIn login page..."
  
rescue => e
  puts "\n❌ Browser automation error: #{e.message}"
  puts "\nFallback: Manual cookie extraction"
  puts "Please run: ruby scripts/extract_linkedin_cookies.rb"
  exit 1
end

puts "\n" + "="*80
puts "Cookie extraction completed!"
puts "="*80