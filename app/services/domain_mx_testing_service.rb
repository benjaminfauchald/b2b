require 'resolv'
require 'timeout'

class DomainMxTestingService < KafkaService
  attr_reader :domain, :batch_size, :max_retries

  MX_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: 'domain_mx_testing', action: 'test_mx')
  end

  def call
    return test_single_domain if domain
    return { processed: 0, successful: 0, failed: 0, errors: 0 } unless service_active?
    test_domains_in_batches(Domain.needing_service('domain_mx_testing'))
  end

  def self.queue_all_domains
    domains = Domain.needing_service('domain_mx_testing')
    count = 0
    
    domains.find_each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end

  def self.queue_100_domains
    domains = Domain.needing_service('domain_mx_testing').limit(100)
    count = 0
    
    domains.each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end

  def check_mx_record(domain_name)
    resolver = Resolv::DNS.new
    begin
      Timeout.timeout(MX_TIMEOUT) do
        mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
        return !mx_records.empty?
      end
    rescue Timeout::Error, Resolv::ResolvError, StandardError
      false
    end
  end

  private

  def test_single_domain
    result = perform_mx_test(domain.domain)
    update_domain_status(domain, result)
    result
  end

  def test_domains_in_batches(domains)
    results = { processed: 0, successful: 0, failed: 0, errors: 0 }
    domains.find_each(batch_size: batch_size) do |domain|
      audit_log = nil
      begin
        audit_log = ServiceAuditLog.create!(
          auditable: domain,
          service_name: service_name,
          action: action,
          status: :pending,
          columns_affected: ['mx'],
          metadata: { domain_name: domain.domain }
        )
        result = perform_mx_test(domain.domain)
        if result[:status] == :success
          update_domain_status(domain, result)
          audit_log.mark_success!({
            'domain_name' => domain.domain,
            'mx_status' => domain.mx,
            'test_duration_ms' => result[:duration]
          }, ['mx'])
          results[:successful] += 1
        else
          update_domain_status(domain, result)
          audit_log.mark_failed!(result[:error] || 'MX test failed', { 'error' => result[:error] || 'MX test failed', 'domain_name' => domain.domain }, [])
          results[:failed] += 1
        end
        results[:processed] += 1
      rescue StandardError => e
        results[:errors] += 1
        audit_log.mark_failed!(e.message, { 'error' => e.message, 'domain_name' => domain.domain }, []) if audit_log
      end
    end
    results
  end

  def perform_mx_test(domain_name)
    start_time = Time.current
    resolver = Resolv::DNS.new
    begin
      Timeout.timeout(MX_TIMEOUT) do
        mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
        {
          status: mx_records.any? ? :success : :no_records,
          mx_records: mx_records.map { |mx| mx.exchange.to_s },
          duration: Time.current - start_time
        }
      end
    rescue Resolv::ResolvError => e
      {
        status: :error,
        error: 'DNS resolution failed',
        duration: Time.current - start_time
      }
    rescue Timeout::Error => e
      {
        status: :error,
        error: "DNS resolution timed out after #{MX_TIMEOUT} seconds",
        duration: Time.current - start_time
      }
    end
  end

  def update_domain_status(domain, result)
    case result[:status]
    when :success
      domain.update_columns(mx: true)
    when :no_records, :error, :timeout
      domain.update_columns(mx: false)
    end
  end

  def service_active?
    ServiceConfiguration.active?(service_name)
  end

  # Legacy class methods for backward compatibility
  def self.test_mx(domain)
    service = new(domain: domain)
    result = service.send(:perform_mx_test, domain.domain)
    if result[:status] == 'success'
      domain.update_columns(mx: true)
      true
    else
      domain.update_columns(mx: false)
      false
    end
  end
end 