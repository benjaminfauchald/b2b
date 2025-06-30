class Domain < ApplicationRecord
  include ServiceAuditable

  # Validations
  validates :domain, presence: true, uniqueness: true
  validates :mx, inclusion: { in: [ true, false ] }, allow_nil: true

  # Scopes for domain testing
  scope :untested, -> { where(dns: nil) }
  scope :dns_active, -> { where(dns: true) }
  scope :dns_inactive, -> { where(dns: false) }
  scope :dns_tested, -> { where.not(dns: nil) }
  scope :with_www, -> { where(www: true) }
  scope :with_mx, -> { where(mx: true) }
  scope :www_active, -> { where(www: true) }
  scope :www_inactive, -> { where(www: false) }
  scope :www_untested, -> { where(www: nil) }
  scope :www_tested, -> { where.not(www: nil) }
  scope :mx_active, -> { where(mx: true) }
  scope :mx_inactive, -> { where(mx: false) }
  scope :mx_untested, -> { where(mx: nil) }
  scope :mx_tested, -> { where.not(mx: nil) }

  # Scopes for web content extraction
  scope :with_a_record, -> { where(www: true).where.not(a_record_ip: nil) }
  scope :with_a_records, -> { with_a_record }
  scope :with_web_content, -> { where.not(web_content_data: nil) }
  scope :needing_web_content, -> { with_a_record.where(web_content_data: nil) }
  scope :needing_web_content_extraction, -> { 
    # Start with domains that have A records
    base_scope = with_a_record
    
    # Get service configuration to check if it's active
    service_config = ServiceConfiguration.find_by(service_name: "domain_web_content_extraction")
    return base_scope.where(web_content_data: nil) unless service_config&.active?
    
    # Include domains without any web content data
    without_content = base_scope.where(web_content_data: nil)
    
    # For domains with content, check if they need refresh using the parent implementation
    with_content = base_scope.where.not(web_content_data: nil)
    needing_refresh = with_content.merge(needing_service("domain_web_content_extraction"))
    
    # Combine both conditions
    where(id: without_content).or(where(id: needing_refresh))
  }
  scope :web_content_extracted, -> { where.not(web_content_data: nil) }
  scope :web_content_failed, -> {
    with_a_record.where(web_content_data: nil)
                 .joins(:service_audit_logs)
                 .where(service_audit_logs: { service_name: "domain_web_content_extraction", status: "failed" })
                 .distinct
  }
  scope :web_content_not_extracted, -> { where(web_content_data: nil) }
  scope :web_content_ready_for_extraction, -> { with_a_record.where(web_content_data: nil) }

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

  def needs_web_content_extraction?
    # Must have www=true and a_record_ip present
    return false unless www == true && a_record_ip.present?
    
    # If no web content data, needs extraction
    return true if web_content_data.nil?
    
    # If has web content data, check if it needs refresh based on service audit logs
    needs_service?("domain_web_content_extraction")
  end

  def web_content_extracted_at
    service_audit_logs
      .where(service_name: "domain_web_content_extraction", status: "success")
      .order(completed_at: :desc)
      .first&.completed_at
  end

  def web_content_extraction_status
    most_recent = service_audit_logs
                   .where(service_name: "domain_web_content_extraction")
                   .order(created_at: :desc)
                   .first

    return :never_attempted unless most_recent

    case most_recent.status
    when "success"
      :success
    when "failed"
      :failed
    when "pending"
      :pending
    else
      :never_attempted
    end
  end

  # Override from ServiceAuditable to handle domain-specific logic
  def self.needing_service(service_name)
    case service_name.to_s
    when "domain_mx_testing"
      # MX testing needs DNS to be active
      where(dns: true, mx: nil)
    when "domain_a_record_testing"
      # A record testing needs DNS to be active but WWW not tested
      dns_active.where(www: nil)
    when "domain_web_content_extraction"
      # Use the parent implementation but only for domains with A records
      with_a_record.merge(super(service_name))
    when "domain_testing"
      # DNS testing specifically targets domains that haven't been tested yet
      where(dns: nil)
    else
      # Fall back to ServiceAuditable logic
      super(service_name)
    end
  end
end
