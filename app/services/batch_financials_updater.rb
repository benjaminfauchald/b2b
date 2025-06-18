class BatchFinancialsUpdater
  BATCH_SIZE = 1000

  def self.update_all(batch_size: nil, limit: nil)
    new(batch_size: batch_size, limit: limit).update_all
  end

  def initialize(batch_size: nil, limit: nil)
    @batch_size = batch_size || BATCH_SIZE
    @limit = limit
    @logger = Rails.logger
  end

  def update_all
    companies = Company.needs_financial_update
    companies = companies.limit(@limit) if @limit.present?
    total = companies.count

    @logger.info "Starting batch update for #{total} companies"

    processed = 0
    companies.find_in_batches(batch_size: @batch_size) do |batch|
      batch.each do |company|
        begin
          company.update_financials_async
          processed += 1
          @logger.info "[#{processed}/#{total}] Enqueued update for #{company.registration_number}"
        rescue => e
          @logger.error "Error enqueuing update for company #{company.id}: #{e.message}"
        end
      end
    end

    @logger.info "Completed enqueuing updates for #{processed} companies"
    processed
  end

  def self.update_stale
    companies = Company.all.select { |c| c.last_financial_update_at.nil? || c.last_financial_update_at < 6.months.ago }
    updater = new
    updater.instance_variable_set(:@logger, Rails.logger)
    updater.instance_exec { update_companies(companies) }
  end

  private

  def update_companies(companies)
    total = companies.count
    return 0 if total.zero?

    @logger.info "Updating #{total} companies with stale financial data"

    processed = 0
    companies.find_each do |company|
      begin
        company.update_financials_async
        processed += 1
        @logger.info "[#{processed}/#{total}] Enqueued update for #{company.registration_number}" if (processed % 100).zero?
      rescue => e
        @logger.error "Error enqueuing update for company #{company.id}: #{e.message}"
      end
    end

    @logger.info "Completed enqueuing updates for #{processed} companies"
    processed
  end
end
