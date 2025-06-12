require 'resolv'
require 'timeout'

class DomainTestingService
  DNS_TIMEOUT = 5 # 5 second timeout for DNS lookups
  
  def self.test_dns(domain)
    result = has_dns?(domain.domain)
    domain.update!(dns: result)
    result
  rescue Resolv::ResolvError
    domain.update!(dns: false) 
    false
  rescue Timeout::Error
    domain.update!(dns: false)  # Treat timeouts as DNS failures
    false
  rescue => e
    domain.update!(dns: nil)  # Network errors, other exceptions
    nil
  end
  
  def self.queue_all_domains
    # ONLY queue domains where dns field is NULL
    unchecked_domains = Domain.where(dns: nil)
    count = 0
    
    unchecked_domains.find_each do |domain|
      DomainTestJob.perform_later(domain.id)
      count += 1
    end
    
    count
  end

  def self.queue_100_domains
    # ONLY queue 100 domains where dns field is NULL
    unchecked_domains = Domain.where(dns: nil).limit(100)
    count = 0
    
    unchecked_domains.find_each do |domain|
      DomainTestJob.perform_later(domain.id)
      count += 1
    end
    
    count
  end
  
  private
  
  def self.has_dns?(domain_name)
    Timeout::timeout(DNS_TIMEOUT) do
      Resolv.getaddress(domain_name)
    end
    true
  rescue Resolv::ResolvError
    raise  # Re-raise to be caught specifically above
  rescue Timeout::Error
    raise  # Re-raise to be caught specifically above
  end
end 