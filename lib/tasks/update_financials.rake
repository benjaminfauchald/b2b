namespace :financials do
  desc "Update financial data for companies"
  task :update, [ :batch_size, :offset ] => :environment do |_t, args|
    batch_size = (args[:batch_size] || 1000).to_i
    offset = (args[:offset] || 0).to_i
    total = Company.count
    processed = 0

    logger = Logger.new(STDOUT)
    logger.info "Starting financial data update for #{total} companies"
    logger.info "Batch size: #{batch_size}, Offset: #{offset}"

    Company.offset(offset).find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |company|
        begin
          UpdateCompanyFinancialsWorker.perform_async(company.id)
          processed += 1
          logger.info "[#{processed}/#{total}] Enqueued update for #{company.registration_number}"
        rescue => e
          logger.error "Error enqueuing update for company #{company.id}: #{e.message}"
        end
      end
    end

    logger.info "Enqueued updates for #{processed} companies"
  end

  desc "Update financial data for a specific company"
  task :update_company, [ :registration_number ] => :environment do |_t, args|
    registration_number = args[:registration_number]
    unless registration_number
      puts "Please provide a registration number: rake financials:update_company[123456789]"
      next
    end

    company = Company.find_by(registration_number: registration_number)
    unless company
      puts "Company with registration number #{registration_number} not found"
      next
    end

    puts "Updating financial data for #{company.name} (#{company.registration_number})..."
    CompanyFinancialsUpdater.new(company).call
    company.reload

    puts "\nUpdate complete!"
    puts "Status: #{company.financial_data_status}"
    puts "Last updated: #{company.last_financial_data_fetch_at}"
    puts "Ordinary Result: #{company.ordinary_result}"
    puts "Annual Result: #{company.annual_result}"
    puts "Operating Revenue: #{company.operating_revenue}"
    puts "Operating Costs: #{company.operating_costs}"
    if company.financial_data_status == "failed"
      puts "Error: #{company.http_error_message}"
    end
  end
end
