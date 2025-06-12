class Domain < ApplicationRecord
  include ServiceAuditable
  
  # Validations
  validates :domain, presence: true, uniqueness: true
  
  # Scopes for domain testing
  scope :untested, -> { where(dns: nil) }
  scope :dns_active, -> { where(dns: true) }
  scope :dns_inactive, -> { where(dns: false) }
  scope :with_www, -> { where(www: true) }
  scope :with_mx, -> { where(mx: true) }
  
  # Instance methods
  def needs_dns_test?
    dns.nil? || needs_service?('domain_dns_testing_v1')
  end
  
  def test_status
    case dns
    when true then 'active'
    when false then 'inactive'
    when nil then 'untested'
    end
  end
end
