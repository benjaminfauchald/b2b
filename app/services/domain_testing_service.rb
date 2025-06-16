require 'resolv'
require 'timeout'

class DomainTestingService < ApplicationService
  attr_reader :domain, :batch_size, :max_retries

  DNS_TIMEOUT = 5 # seconds
  
  def initialize(domain: nil, batch_size: 100, max_retries: 3)
    super(action: 'test_dns')
    @domain = domain
    @batch_size = batch_size
    @max_retries = max_retries
  end
  
  def call
    return test_single_domain if domain
    test_domains_in_batches
  end
  
  # Legacy class methods for backward compatibility
  def self.test_dns(domain)
    new(domain: domain).send(:perform_dns_test)[:records]
  end
  
  def self.queue_all_domains
    domains = Domain.needing_service('domain_testing')
    count = 0
    
    domains.find_each do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end
  
  def self.queue_100_domains
    domains = Domain.needing_service('domain_testing').limit(100)
    count = 0
    
    domains.each do |domain|
      DomainDnsTestingWorker.perform_async(domain.id)
      count += 1
    end
    
    count
  end
  
  def has_dns?(domain_name)
    resolver = Resolv::DNS.new
    resolver.timeouts = DNS_TIMEOUT

    begin
      Timeout.timeout(DNS_TIMEOUT) do
        resolver.getresources(domain_name, Resolv::DNS::Resource::IN::A).any?
      end
    rescue Resolv::ResolvError, Timeout::Error
      false
    end
  end

  def test_domain_dns(domain, audit_log = nil)
    start_time = Time.current
    result = perform_dns_test_for_domain(domain)
    duration = Time.current - start_time
    context = {
      'test_duration_ms' => (duration * 1000).to_i,
      'domain_name' => domain.domain
    }

    if audit_log
      audit_log.add_context(context)
    end

    if result[:status] == 'success'
      domain.update!(dns: true)
      context['dns_result'] = true
      context['dns_status'] = 'active'
      status = :successful
    else
      domain.update!(dns: false)
      context['dns_result'] = false
      context['dns_status'] = 'inactive'
      status = :failed
    end

    { status: status, context: context }
  rescue Resolv::ResolvError => e
    if audit_log
      audit_log.mark_failed!(e.message, { 'error_type' => 'resolve_error' })
    end
    domain.update!(dns: false)
    { status: :failed, context: context.merge('dns_result' => false, 'error_type' => 'resolve_error') }
  rescue Timeout::Error => e
    if audit_log
      audit_log.mark_failed!("DNS resolution timed out after #{DNS_TIMEOUT} seconds", { 'error_type' => 'timeout_error' })
    end
    domain.update!(dns: false)
    { status: :failed, context: context.merge('dns_result' => false, 'error_type' => 'timeout_error') }
  rescue StandardError => e
    if audit_log
      audit_log.mark_failed!(e.message, { 'error_type' => e.class.name })
    end
    { status: :failed, context: context.merge('dns_result' => false, 'error_type' => e.class.name) }
  end
  
  private
  
  def test_single_domain
    start_time = Time.current
    result = perform_dns_test
    duration = Time.current - start_time

    {
      status: result[:status],
      records: result[:records],
      duration: duration
    }
  end

  def test_domains_in_batches
    Domain.untested.find_each(batch_size: batch_size) do |domain|
      produce_message_with_retry(
        topic: 'domain_testing',
        payload: { domain: domain.domain }.to_json,
        key: domain.id.to_s,
        max_retries: max_retries
      )
    end
  end

  def perform_dns_test
    resolver = Resolv::DNS.new
    records = {
      a: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::A).map(&:address),
      mx: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::MX).map(&:exchange),
      txt: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::TXT).map(&:strings).flatten
    }

    {
      status: records.values.any?(&:any?) ? 'success' : 'no_records',
      records: records
    }
  rescue Resolv::ResolvError => e
    {
      status: 'error',
      records: { error: e.message }
    }
  end

  def perform_dns_test_for_domain(domain)
    resolver = Resolv::DNS.new
    resolver.timeouts = DNS_TIMEOUT

    Timeout.timeout(DNS_TIMEOUT) do
      records = {
        a: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::A).map(&:address),
        mx: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::MX).map(&:exchange),
        txt: resolver.getresources(domain.domain, Resolv::DNS::Resource::IN::TXT).map(&:strings).flatten
      }

      {
        status: records.values.any?(&:any?) ? 'success' : 'no_records',
        records: records
      }
    end
  end

  def produce_message(topic:, payload:, key:)
    Karafka.producer.produce_sync(
      topic: topic,
      payload: payload.to_json,
      key: key
    )
  end

  def produce_message_with_retry(topic:, payload:, key:, max_retries: 3)
    retries = 0
    begin
      produce_message(topic: topic, payload: payload, key: key)
    rescue StandardError => e
      retries += 1
      if retries <= max_retries
        sleep(2 ** retries) # Exponential backoff
        retry
      else
        raise e
      end
    end
  end

  def test_domains_in_batches(domains)
    domains.each_slice(batch_size) do |batch|
      batch.each do |domain|
        result = test_domain_dns(domain)
        next unless result

        payload = {
          domain_id: domain.id,
          result: result
        }

        produce_message_with_retry(
          topic: 'domain_test_results',
          payload: payload,
          key: domain.id.to_s
        )
      end
    end
  end

  def log_error(domain, error)
    Rails.logger.error(
      message: "Domain testing error",
      domain_id: domain.id,
      domain_name: domain.domain,
      error: error.message,
      error_type: error.class.name,
      timestamp: Time.current
    )
  end
end 