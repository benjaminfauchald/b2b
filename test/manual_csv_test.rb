#!/usr/bin/env ruby
# Test script to verify CSV validation logic

require 'net/http'
require 'uri'
require 'json'

# Test the CSV validation logic
csv_content = <<~CSV
profileUrl,fullName,firstName,lastName,companyName,title,companyId,companyUrl,regularCompanyUrl,summary,titleDescription,industry,companyLocation,location,durationInRole,durationInCompany,pastExperienceCompanyName,pastExperienceCompanyUrl,pastExperienceCompanyTitle,pastExperienceDate,pastExperienceDuration,connectionDegree,profileImageUrl,sharedConnectionsCount,name,vmid,linkedInProfileUrl,isPremium,isOpenLink,query,timestamp,defaultProfileUrl
https://www.linkedin.com/in/test,Test User,Test,User,Test Corp,Developer,123,https://linkedin.com/company/test,https://test.com,Summary,Developer,Tech,Oslo,Oslo,1 year,2 years,,,,,,,https://img.jpg,50,Test User,ABC,https://www.linkedin.com/in/test,false,false,query,2025-01-10,https://www.linkedin.com/in/test
CSV

# Check if the validation would accept this
first_line = csv_content.split("\n")[0].strip.downcase

has_email = first_line.include?('email')
has_phantom_buster = first_line.include?('profileurl') && 
                     first_line.include?('fullname') &&
                     first_line.include?('linkedinprofileurl')

puts "CSV Validation Test"
puts "==================="
puts "First line: #{first_line[0..100]}..."
puts "Has email header: #{has_email}"
puts "Has Phantom Buster headers: #{has_phantom_buster}"
puts "Would be accepted: #{has_email || has_phantom_buster}"