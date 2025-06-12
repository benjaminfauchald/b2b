require 'resolv'
require 'timeout'

class DomainARecordTestingService
  A_RECORD_TIMEOUT = 5 # 5 second timeout for A record lookups
  
  def self.test_a_record(domain)
    result = has_www_a_record?(domain.domain)
    domain.update!(www: result)
    result
  rescue Resolv::ResolvError
    domain.update!(www: false) 
    false
  rescue Timeout::Error
    domain.update!(www: false)  # Treat timeouts as A record failures
    false
  rescue => e
    domain.update!(www: nil)  # Network errors, other exceptions
    nil
  end
  
  def self.queue_all_domains
    domains = Domain.where(dns: true, www: nil).limit(1000)
    count = 0
    domains.each do |domain|
      DomainARecordTestJob.perform_later(domain.id)
      count += 1
    end
    count
  end
  
  def self.queue_100_domains
    domains = Domain.where(dns: true, www: nil).limit(100)
    count = 0
    domains.each do |domain|
      DomainARecordTestJob.perform_later(domain.id)
      count += 1
    end
    count
  end
  
  private
  
  def self.has_www_a_record?(domain_name)
    Timeout::timeout(A_RECORD_TIMEOUT) do
      Resolv.getaddress("www.#{domain_name}")
    end
    true
  rescue Resolv::ResolvError
    raise  # Re-raise to be caught specifically above
  rescue Timeout::Error
    raise  # Re-raise to be caught specifically above
  end
end 