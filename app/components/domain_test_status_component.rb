# frozen_string_literal: true

class DomainTestStatusComponent < ViewComponent::Base
  attr_reader :domain

  def initialize(domain:)
    @domain = domain
  end

  def render?
    domain.present?
  end

  private

  def test_statuses
    {
      dns: dns_status,
      mx: mx_status,
      a_record: a_record_status
    }
  end

  def dns_status
    case domain.dns
    when true
      { label: "DNS", status: "success", icon: "✓" }
    when false
      { label: "DNS", status: "error", icon: "✗" }
    when nil
      { label: "DNS", status: "testing", icon: "..." }
    end
  end

  def mx_status
    case domain.mx
    when true
      { label: "MX", status: "success", icon: "✓" }
    when false
      { label: "MX", status: "error", icon: "✗" }
    when nil
      if domain.dns == false
        { label: "MX", status: "skipped", icon: "-" }
      else
        { label: "MX", status: "testing", icon: "..." }
      end
    end
  end

  def a_record_status
    case domain.www
    when true
      { label: "A Record", status: "success", icon: "✓" }
    when false
      { label: "A Record", status: "error", icon: "✗" }
    when nil
      if domain.dns == false
        { label: "A Record", status: "skipped", icon: "-" }
      else
        { label: "A Record", status: "testing", icon: "..." }
      end
    end
  end

  def status_classes(status)
    case status
    when "success"
      "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"
    when "error"
      "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300"
    when "testing"
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300 animate-pulse"
    when "skipped"
      "bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-500"
    else
      "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    end
  end

  def any_testing?
    domain.dns.nil? || 
    (domain.dns == true && domain.mx.nil?) || 
    (domain.dns == true && domain.www.nil?)
  end
end