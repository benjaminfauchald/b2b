namespace :linkedin_discovery do
  desc "Force reprocess LinkedIn discovery for companies in a specific postal code"
  task :force_reprocess, [:postal_code] => :environment do |task, args|
    postal_code = args[:postal_code] || '2000'
    
    puts "🔍 Finding companies in postal code #{postal_code}..."
    
    companies = Company.where(postal_code: postal_code)
                      .where('operating_revenue > ?', 10_000_000)
                      .order(operating_revenue: :desc)
    
    puts "📊 Found #{companies.count} companies with revenue > 10M in postal code #{postal_code}"
    
    companies.each do |company|
      # Check if company has linkedin_alternatives data
      has_alternatives = company.linkedin_alternatives.present? && company.linkedin_alternatives.any?
      
      # Find recent service audit logs
      recent_logs = company.service_audit_logs
                          .where(service_name: 'company_linkedin_discovery')
                          .where('completed_at > ?', 720.hours.ago)
      
      puts "🏢 #{company.company_name}:"
      puts "   LinkedIn AI URL: #{company.linkedin_ai_url || 'None'}"
      puts "   LinkedIn Alternatives: #{has_alternatives ? 'Yes' : 'No'}"
      puts "   Recent logs: #{recent_logs.count}"
      
      if !has_alternatives || recent_logs.where(status: 'skipped').any?
        puts "   ❌ Clearing recent logs to force reprocessing..."
        recent_logs.destroy_all
        
        # Also clear linkedin processing flags to ensure fresh processing
        company.update_columns(
          linkedin_processed: false,
          linkedin_last_processed_at: nil
        )
      else
        puts "   ✅ Already properly processed"
      end
    end
    
    puts "\n🎯 Companies now available for LinkedIn discovery:"
    available_companies = Company.where(postal_code: postal_code)
                                .where('operating_revenue > ?', 10_000_000)
                                .needing_service('company_linkedin_discovery')
    
    puts "#{available_companies.count} companies ready for processing"
  end
  
  desc "Queue LinkedIn discovery for companies in a specific postal code"
  task :queue_postal_code, [:postal_code, :batch_size] => :environment do |task, args|
    postal_code = args[:postal_code] || '2000'
    batch_size = (args[:batch_size] || '10').to_i
    
    puts "🚀 Queuing LinkedIn discovery for postal code #{postal_code}..."
    
    companies = Company.where(postal_code: postal_code)
                      .where('operating_revenue > ?', 10_000_000)
                      .needing_service('company_linkedin_discovery')
                      .order(operating_revenue: :desc)
                      .limit(batch_size)
    
    puts "📋 Found #{companies.count} companies ready for processing"
    
    queued = 0
    companies.each do |company|
      puts "   Queuing: #{company.company_name}"
      CompanyLinkedinDiscoveryWorker.perform_async(company.id)
      queued += 1
    end
    
    puts "✅ Queued #{queued} companies for LinkedIn discovery"
  end
end