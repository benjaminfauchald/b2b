# frozen_string_literal: true

namespace :linkedin_company_data do
  desc "Set up LinkedIn Company Data Service configuration"
  task setup: :environment do
    puts "Setting up LinkedIn Company Data Service..."
    
    # Ensure service configuration exists
    config = LinkedinCompanyDataService.ensure_configuration!
    
    puts "✓ Service configuration: #{config.active? ? 'Active' : 'Inactive'}"
    puts "✓ Configuration data: #{config.configuration_data}"
    
    # Check environment variables
    puts "\nChecking environment variables..."
    
    email = ENV['LINKEDIN_EMAIL']
    password = ENV['LINKEDIN_PASSWORD']
    cookie = ENV['LINKEDIN_COOKIE_LI_AT']
    
    if email.present? && password.present?
      puts "✓ Username/password authentication configured"
    elsif cookie.present?
      puts "✓ Cookie authentication configured"
    else
      puts "✗ No authentication configured"
      puts "  Set LINKEDIN_EMAIL and LINKEDIN_PASSWORD or LINKEDIN_COOKIE_LI_AT"
    end
    
    # Test connectivity
    puts "\nTesting service connectivity..."
    begin
      service = LinkedinCompanyDataService.new(company_identifier: 'microsoft')
      puts "✓ Service initialized successfully"
    rescue => e
      puts "✗ Service initialization failed: #{e.message}"
    end
    
    puts "\nSetup complete!"
  end
  
  desc "Test LinkedIn Company Data Service with a sample company"
  task test: :environment do
    puts "Testing LinkedIn Company Data Service..."
    
    test_cases = [
      { type: 'slug', value: 'microsoft' },
      { type: 'numeric_id', value: '1035' },
      { type: 'url', value: 'https://www.linkedin.com/company/microsoft' }
    ]
    
    test_cases.each do |test_case|
      puts "\n--- Testing #{test_case[:type]}: #{test_case[:value]} ---"
      
      begin
        result = case test_case[:type]
                when 'slug', 'numeric_id'
                  LinkedinCompanyDataService.extract_from_id(test_case[:value])
                when 'url'
                  LinkedinCompanyDataService.extract_from_url(test_case[:value])
                end
        
        if result[:success]
          data = result[:data]
          puts "✓ Success!"
          puts "  Company: #{data[:name]}"
          puts "  ID: #{data[:id]}"
          puts "  Universal Name: #{data[:universal_name]}"
          puts "  Industry: #{data[:industry]}"
          puts "  Staff Count: #{data[:staff_count]}"
          puts "  Website: #{data[:website]}"
        else
          puts "✗ Failed: #{result[:error]}"
        end
      rescue => e
        puts "✗ Exception: #{e.message}"
      end
    end
  end
  
  desc "Extract company data from LinkedIn URL"
  task :extract_url, [:url] => :environment do |t, args|
    url = args[:url]
    
    unless url.present?
      puts "Usage: rake linkedin_company_data:extract_url[https://www.linkedin.com/company/microsoft]"
      exit 1
    end
    
    puts "Extracting company data from: #{url}"
    
    begin
      result = LinkedinCompanyDataService.extract_from_url(url)
      
      if result[:success]
        data = result[:data]
        puts "\n✓ Company Data:"
        puts "  Name: #{data[:name]}"
        puts "  ID: #{data[:id]}"
        puts "  Universal Name: #{data[:universal_name]}"
        puts "  Description: #{data[:description]&.truncate(100)}"
        puts "  Industry: #{data[:industry]}"
        puts "  Staff Count: #{data[:staff_count]}"
        puts "  Website: #{data[:website]}"
        puts "  Headquarters: #{data[:headquarters]}"
        puts "  Founded: #{data[:founded_year]}"
        puts "  Specialties: #{data[:specialties]&.join(', ')}"
      else
        puts "✗ Failed: #{result[:error]}"
      end
    rescue => e
      puts "✗ Exception: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end
  
  desc "Convert LinkedIn company slug to numeric ID"
  task :slug_to_id, [:slug] => :environment do |t, args|
    slug = args[:slug]
    
    unless slug.present?
      puts "Usage: rake linkedin_company_data:slug_to_id[microsoft]"
      exit 1
    end
    
    puts "Converting slug to ID: #{slug}"
    
    begin
      company_id = LinkedinCompanyDataService.slug_to_id(slug)
      
      if company_id
        puts "✓ Company ID: #{company_id}"
        puts "  Numeric URL: https://www.linkedin.com/company/#{company_id}"
        puts "  Slug URL: https://www.linkedin.com/company/#{slug}"
      else
        puts "✗ Could not find company ID for slug: #{slug}"
      end
    rescue => e
      puts "✗ Exception: #{e.message}"
    end
  end
  
  desc "Convert LinkedIn company ID to slug"
  task :id_to_slug, [:id] => :environment do |t, args|
    company_id = args[:id]
    
    unless company_id.present?
      puts "Usage: rake linkedin_company_data:id_to_slug[1035]"
      exit 1
    end
    
    puts "Converting ID to slug: #{company_id}"
    
    begin
      slug = LinkedinCompanyDataService.id_to_slug(company_id)
      
      if slug
        puts "✓ Company Slug: #{slug}"
        puts "  Numeric URL: https://www.linkedin.com/company/#{company_id}"
        puts "  Slug URL: https://www.linkedin.com/company/#{slug}"
      else
        puts "✗ Could not find company slug for ID: #{company_id}"
      end
    rescue => e
      puts "✗ Exception: #{e.message}"
    end
  end
  
  desc "Check service audit logs"
  task audit_logs: :environment do
    puts "Recent LinkedIn Company Data Service audit logs:"
    
    logs = ServiceAuditLog.where(service_name: 'linkedin_company_data')
                         .order(created_at: :desc)
                         .limit(10)
    
    if logs.empty?
      puts "No audit logs found."
    else
      logs.each do |log|
        puts "\n--- #{log.created_at.strftime('%Y-%m-%d %H:%M:%S')} ---"
        puts "Status: #{log.status}"
        puts "Operation: #{log.operation_type}"
        puts "Duration: #{log.execution_time_ms}ms" if log.execution_time_ms
        puts "Metadata: #{log.metadata}" if log.metadata.present?
        puts "Error: #{log.error_message}" if log.error_message.present?
      end
    end
  end
  
  desc "Install Python dependencies"
  task install_deps: :environment do
    puts "Installing Python dependencies for LinkedIn Company Data Service..."
    
    requirements = [
      'linkedin-api>=2.0.0',
      'requests>=2.25.1',
      'urllib3>=1.26.0'
    ]
    
    # Check if virtual environment exists
    venv_path = Rails.root.join('venv')
    
    if Dir.exist?(venv_path)
      puts "Using existing virtual environment at #{venv_path}"
      pip_cmd = "#{venv_path}/bin/pip"
    else
      puts "Creating virtual environment..."
      system("python3 -m venv #{venv_path}")
      pip_cmd = "#{venv_path}/bin/pip"
    end
    
    # Install dependencies
    puts "Installing dependencies..."
    requirements.each do |req|
      puts "  Installing #{req}..."
      system("#{pip_cmd} install #{req}")
    end
    
    puts "✓ Python dependencies installed successfully"
  end
end