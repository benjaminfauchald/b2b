namespace :fixtures do
  desc "Generate fixtures from sample production data"
  task generate: :environment do
    puts "Generating fixtures from database..."
    
    # Directory for fixtures
    fixtures_dir = Rails.root.join('spec', 'fixtures')
    FileUtils.mkdir_p(fixtures_dir)
    
    # Generate Company fixtures
    generate_company_fixtures(fixtures_dir)
    
    # Generate Domain fixtures
    generate_domain_fixtures(fixtures_dir)
    
    # Generate ServiceAuditLog fixtures
    generate_service_audit_log_fixtures(fixtures_dir)
    
    # Generate ServiceConfiguration fixtures
    generate_service_configuration_fixtures(fixtures_dir)
    
    puts "Fixtures generated successfully!"
  end
  
  private
  
  def generate_company_fixtures(dir)
    puts "Generating company fixtures..."
    
    companies = {
      # Norwegian companies with different data states
      'norwegian_company_complete' => Company.where(source_country: "NO")
        .where.not(website: [nil, ""])
        .where.not(linkedin_url: [nil, ""])
        .where.not(ordinary_result: nil)
        .first,
        
      'norwegian_company_no_website' => Company.where(source_country: "NO")
        .where(website: [nil, ""])
        .where("operating_revenue > ?", 10_000_000)
        .first,
        
      'norwegian_company_no_financials' => Company.where(source_country: "NO")
        .where(ordinary_result: nil)
        .first,
        
      # Swedish companies
      'swedish_company_high_revenue' => Company.where(source_country: "SE")
        .where("operating_revenue > ?", 50_000_000)
        .first,
        
      # Edge cases
      'company_minimal_data' => Company.where(company_name: nil)
        .or(Company.where(postal_city: nil))
        .first,
        
      'company_with_special_chars' => Company.where("company_name LIKE ?", "%/%")
        .or(Company.where("company_name LIKE ?", "%&%"))
        .first
    }
    
    File.open(dir.join('companies.yml'), 'w') do |file|
      companies.each do |name, company|
        next unless company
        
        file.puts "#{name}:"
        company.attributes.each do |key, value|
          next if %w[id created_at updated_at].include?(key)
          
          if value.is_a?(String) && value.include?("\n")
            file.puts "  #{key}: |"
            value.lines.each { |line| file.puts "    #{line.strip}" }
          elsif value.nil?
            file.puts "  #{key}: null"
          elsif value.is_a?(Hash) || value.is_a?(Array)
            file.puts "  #{key}: #{value.to_json}"
          else
            file.puts "  #{key}: #{value.inspect}"
          end
        end
        file.puts
      end
    end
  end
  
  def generate_domain_fixtures(dir)
    puts "Generating domain fixtures..."
    
    domains = {
      'domain_with_mx' => Domain.where.not(mx: nil)
        .where.not(a_record_ip: nil)
        .first,
        
      'domain_with_www' => Domain.where(www: true).first,
      
      'domain_no_mx' => Domain.where(mx: nil).first,
      
      'swedish_domain' => Domain.where("domain LIKE ?", "%.se").first,
      
      'domain_with_web_content' => Domain.where.not(web_content_data: nil).first
    }
    
    File.open(dir.join('domains.yml'), 'w') do |file|
      domains.each do |name, domain|
        next unless domain
        
        file.puts "#{name}:"
        domain.attributes.each do |key, value|
          next if %w[id created_at updated_at].include?(key)
          
          if value.nil?
            file.puts "  #{key}: null"
          elsif value.is_a?(Hash) || value.is_a?(Array)
            file.puts "  #{key}: #{value.to_json}"
          else
            file.puts "  #{key}: #{value.inspect}"
          end
        end
        file.puts
      end
    end
  end
  
  def generate_service_audit_log_fixtures(dir)
    puts "Generating service audit log fixtures..."
    
    logs = {
      'successful_financial_audit' => ServiceAuditLog
        .where(service_name: "company_financials", status: ServiceAuditLog::STATUS_SUCCESS)
        .first,
        
      'failed_web_discovery' => ServiceAuditLog
        .where(service_name: "company_web_discovery", status: ServiceAuditLog::STATUS_FAILED)
        .first,
        
      'successful_linkedin_discovery' => ServiceAuditLog
        .where(service_name: "company_linkedin_discovery", status: ServiceAuditLog::STATUS_SUCCESS)
        .first
    }
    
    File.open(dir.join('service_audit_logs.yml'), 'w') do |file|
      logs.each do |name, log|
        next unless log
        
        file.puts "#{name}:"
        log.attributes.each do |key, value|
          next if %w[id created_at updated_at].include?(key)
          
          if value.nil?
            file.puts "  #{key}: null"
          elsif value.is_a?(Hash) || value.is_a?(Array)
            file.puts "  #{key}: #{value.to_json}"
          else
            file.puts "  #{key}: #{value.inspect}"
          end
        end
        file.puts
      end
    end
  end
  
  def generate_service_configuration_fixtures(dir)
    puts "Generating service configuration fixtures..."
    
    configs = ServiceConfiguration.all.index_by(&:service_name)
    
    File.open(dir.join('service_configurations.yml'), 'w') do |file|
      configs.each do |service_name, config|
        file.puts "#{service_name}_config:"
        config.attributes.each do |key, value|
          next if %w[id created_at updated_at].include?(key)
          
          if value.nil?
            file.puts "  #{key}: null"
          elsif value.is_a?(Hash) || value.is_a?(Array)
            file.puts "  #{key}: #{value.to_json}"
          else
            file.puts "  #{key}: #{value.inspect}"
          end
        end
        file.puts
      end
    end
  end
end