class Domain < ApplicationRecord
  include ServiceAuditable

  # Validations
  validates :domain, presence: true, uniqueness: true
  validates :mx, inclusion: { in: [ true, false ] }, allow_nil: true

  # Scopes for domain testing
  scope :untested, -> { where(dns: nil) }
  scope :dns_active, -> { where(dns: true) }
  scope :dns_inactive, -> { where(dns: false) }
  scope :with_www, -> { where(www: true) }
  scope :with_mx, -> { where(mx: true) }
  scope :www_active, -> { where(www: true) }
  scope :www_inactive, -> { where(www: false) }
  scope :www_untested, -> { where(www: nil) }

  # Instance methods
  def needs_testing?(service_name = "domain_testing")
    dns.nil? || needs_service?(service_name)
  end

  def test_status
    case dns
    when true then "active"
    when false then "inactive"
    when nil then "untested"
    end
  end

  def needs_www_testing?(service_name = "domain_a_record_testing")
    dns? && (www.nil? || needs_service?(service_name))
  end

  def needs_dns_testing?
    dns.nil? || needs_service?("domain_testing")
  end

  # Override from ServiceAuditable to handle domain-specific logic
  def self.needing_service(service_name)
    case service_name.to_s
    when "domain_mx_testing"
      # MX testing needs DNS to be active and WWW to be tested
      where(dns: true, www: true, mx: nil)
    when "domain_a_record_testing"
      # A record testing needs DNS to be active but WWW not tested
      dns_active.where(www: nil)
    when "domain_testing"
      # Use the ServiceAuditable logic for DNS testing
      super(service_name)
    else
      # Fall back to ServiceAuditable logic
      super(service_name)
    end
  end
end
