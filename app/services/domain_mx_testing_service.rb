require 'resolv'
require 'timeout'

class DomainMxTestingService < KafkaService
  attr_reader :domain, :batch_size, :max_retries

  MX_TIMEOUT = 5 # seconds

  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
    super(service_name: 'domain_mx_testing_service', action: 'test_mx')
  end

  def call
    return test_single_domain if domain
    test_domains_in_batches
  end

  def self.queue_all_domains
    domains = Domain.where(mx: nil)
    count = 0
    domains.find_each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end
    count
  end

  def self.queue_100_domains
    domains = Domain.where(mx: nil).limit(100)
    count = 0
    domains.each do |domain|
      DomainMxTestingWorker.perform_async(domain.id)
      count += 1
    end
    count
  end

  private

  def test_single_domain
    result = perform_mx_test(domain.domain)
    update_domain_status(result)
    result
  end

  def test_domains_in_batches
    Domain.where(mx: nil).find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |domain|
        result = perform_mx_test(domain.domain)
        update_domain_status(result)
        produce_message_with_retry(
          topic: 'domain_mx_testing',
          payload: {
            domain: domain.domain,
            status: result[:status],
            mx_records: result[:mx_records],
            error: result[:error],
            duration: result[:duration],
            timestamp: Time.current.iso8601
          }.to_json,
          key: domain.id.to_s,
          max_retries: max_retries
        )
      end
    end
  end

  def perform_mx_test(domain_name)
    start_time = Time.current
    resolver = Resolv::DNS.new
    resolver.timeouts = MX_TIMEOUT
    begin
      mx_records = resolver.getresources(domain_name, Resolv::DNS::Resource::IN::MX)
      {
        status: :success,
        mx_records: mx_records.map { |mx| mx.exchange.to_s },
        duration: Time.current - start_time
      }
    rescue Resolv::ResolvError => e
      {
        status: :error,
        error: e.message,
        duration: Time.current - start_time
      }
    rescue Timeout::Error => e
      {
        status: :timeout,
        error: "DNS lookup timed out after #{MX_TIMEOUT} seconds",
        duration: Time.current - start_time
      }
    end
  end

  def update_domain_status(result)
    return unless domain
    case result[:status]
    when :success
      domain.update(mx: result[:mx_records].any?)
    when :error, :timeout
      domain.update(mx: false)
    end
  end
end 