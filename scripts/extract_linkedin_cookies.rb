#!/usr/bin/env ruby
# LinkedIn Cookie Extraction Helper
# Helps users extract and save LinkedIn session cookies for API access

require 'json'
require 'pathname'

puts "="*80
puts "LinkedIn Cookie Extraction Helper"
puts "="*80

puts "\nThis script helps you save LinkedIn session cookies for API access."
puts "\nTo get your LinkedIn cookies:"
puts "1. Open LinkedIn in your browser and make sure you're logged in"
puts "2. Open Developer Tools (F12 or right-click -> Inspect)"
puts "3. Go to Application tab > Storage > Cookies > https://www.linkedin.com"
puts "4. Find and copy the following cookie values:"
puts "   - li_at (most important - your session token)"
puts "   - JSESSIONID (session identifier)"
puts "   - li_gc (guest cookie)"
puts "   - bcookie (browser cookie)"
puts "   - bscookie (browser session cookie)"

puts "\n" + "-"*60

# Get Rails root directory
script_dir = Pathname.new(__FILE__).dirname
rails_root = script_dir.parent
tmp_dir = rails_root.join('tmp')
cookie_file = tmp_dir.join('linkedin_cookies.json')

# Ensure tmp directory exists
tmp_dir.mkpath unless tmp_dir.exist?

puts "Cookie file location: #{cookie_file}"

if cookie_file.exist?
  begin
    existing_cookies = JSON.parse(cookie_file.read)
    puts "\n📁 Existing cookies found:"
    existing_cookies.each { |name, value| puts "  #{name}: #{value[0..20]}..." }
    
    print "\nDo you want to update the existing cookies? (y/n): "
    response = gets.chomp.downcase
    
    unless response == 'y' || response == 'yes'
      puts "Keeping existing cookies."
      exit 0
    end
  rescue JSON::ParserError
    puts "\n⚠️  Existing cookie file appears corrupted, will overwrite."
  end
end

puts "\n" + "-"*60
puts "Enter your LinkedIn cookie values:"
puts "(Press Enter to skip optional cookies)"

cookies = {}

# Required cookies
print "\n🔑 li_at (REQUIRED): "
li_at = gets.chomp.strip
if li_at.empty?
  puts "❌ li_at cookie is required for authentication!"
  exit 1
end
cookies['li_at'] = li_at

print "🔑 JSESSIONID (REQUIRED): "
jsessionid = gets.chomp.strip
if jsessionid.empty?
  puts "❌ JSESSIONID cookie is required for authentication!"
  exit 1
end
# Remove quotes if present
jsessionid = jsessionid.gsub(/^"/, '').gsub(/"$/, '')
cookies['JSESSIONID'] = jsessionid

# Optional cookies
print "🔸 li_gc (optional): "
li_gc = gets.chomp.strip
cookies['li_gc'] = li_gc unless li_gc.empty?

print "🔸 bcookie (optional): "
bcookie = gets.chomp.strip
cookies['bcookie'] = bcookie unless bcookie.empty?

print "🔸 bscookie (optional): "
bscookie = gets.chomp.strip
cookies['bscookie'] = bscookie unless bscookie.empty?

# Validate cookie format
unless li_at.match(/^[A-Za-z0-9+\/=_-]+$/)
  puts "\n⚠️  Warning: li_at cookie format looks unusual. Make sure you copied it correctly."
end

# Save cookies to file
begin
  cookie_file.write(JSON.pretty_generate(cookies))
  puts "\n✅ Cookies saved successfully to: #{cookie_file}"
  
  puts "\n📋 Saved cookies:"
  cookies.each { |name, value| puts "  #{name}: #{value[0..20]}..." }
  
  puts "\n🔒 Security note:"
  puts "  • These cookies provide access to your LinkedIn account"
  puts "  • Keep them secure and don't share them"
  puts "  • The cookies will expire - you may need to refresh them periodically"
  
  puts "\n🚀 Next steps:"
  puts "  • Run the Sales Navigator scraper test: scripts/test_sales_navigator_scraper.rb"
  puts "  • Or use environment variables instead:"
  puts "    export LINKEDIN_COOKIE_LI_AT='#{li_at[0..20]}...'"
  puts "    export LINKEDIN_COOKIE_JSESSIONID='#{jsessionid[0..20]}...'"

rescue => e
  puts "\n❌ Error saving cookies: #{e.message}"
  exit 1
end

# Test cookie validity (basic check)
puts "\n" + "-"*60
puts "🧪 Testing cookie validity..."

require 'net/http'
require 'openssl'

begin
  uri = URI('https://www.linkedin.com/feed')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  
  request = Net::HTTP::Get.new(uri)
  request['Cookie'] = cookies.map { |name, value| "#{name}=#{value}" }.join('; ')
  request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  
  response = http.request(request)
  
  case response.code.to_i
  when 200
    if response.body.include?('linkedin.com/in/')
      puts "✅ Cookies appear to be valid (logged in successfully)"
    else
      puts "⚠️  Cookies may be expired or invalid (not seeing profile links)"
    end
  when 302, 301
    puts "🔄 Got redirect - cookies may be partially valid"
  when 401, 403
    puts "❌ Authentication failed - cookies may be expired"
  else
    puts "⚠️  Unexpected response: #{response.code}"
  end
  
rescue => e
  puts "⚠️  Cookie test failed: #{e.message}"
end

puts "\n" + "="*80
puts "Cookie extraction completed!"
puts "="*80