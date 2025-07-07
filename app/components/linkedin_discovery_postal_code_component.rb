# frozen_string_literal: true

# ============================================================================
# LinkedIn Discovery Postal Code Component
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/test_for_lillestrom.rb
#
# IMPORTANT: When making changes to this component:
# 1. Check IDM status: FeatureMemories::TestForLillestrom.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
#
# ViewComponent for LinkedIn Discovery by Postal Code feature
# Displays form for postal code and batch size selection with company preview
class LinkedinDiscoveryPostalCodeComponent < ViewComponent::Base
  include Turbo::FramesHelper
  
  attr_reader :postal_code, :batch_size, :company_preview

  def initialize(postal_code: '2000', batch_size: 100)
    @postal_code = postal_code
    @batch_size = batch_size
    @company_preview = calculate_company_preview
  end

  def render?
    # Only show if LinkedIn discovery service is active
    ServiceConfiguration.active?("company_linkedin_discovery")
  end

  def preview_text
    return "No companies found in postal code #{postal_code}" if company_preview[:count] == 0
    
    count = company_preview[:count]
    batch_text = batch_size < count ? "top #{batch_size}" : "all #{count}"
    
    if company_preview[:revenue_range]
      highest = format_revenue(company_preview[:revenue_range][:highest])
      lowest = format_revenue(company_preview[:revenue_range][:lowest])
      
      "#{count} companies found. Will process #{batch_text} (revenue range: #{lowest} - #{highest})"
    else
      "#{count} companies found. Will process #{batch_text}"
    end
  end

  def can_process?
    company_preview[:count] > 0 && batch_size <= company_preview[:count]
  end

  def postal_code_options
    # Get most common postal codes with companies that have operating revenue
    Company.where.not(operating_revenue: nil)
           .where.not(postal_code: nil)
           .group(:postal_code)
           .having('COUNT(*) >= 10')
           .order(Arel.sql('COUNT(*) DESC'))
           .limit(20)
           .pluck(:postal_code)
  end

  def batch_size_options
    [10, 25, 50, 100, 200, 500, 1000]
  end

  private

  def calculate_company_preview
    return { count: 0, revenue_range: nil } if postal_code.blank?

    companies = Company.where(postal_code: postal_code)
                      .where.not(operating_revenue: nil)
                      .order(operating_revenue: :desc)
    
    count = companies.count
    
    if count > 0
      revenue_range = {
        highest: companies.first.operating_revenue,
        lowest: companies.limit(batch_size).last&.operating_revenue || companies.first.operating_revenue
      }
    else
      revenue_range = nil
    end

    { count: count, revenue_range: revenue_range }
  end

  def format_revenue(amount)
    return 'N/A' unless amount

    if amount >= 1_000_000_000
      "#{(amount / 1_000_000_000.0).round(1)}B NOK"
    elsif amount >= 1_000_000
      "#{(amount / 1_000_000.0).round(1)}M NOK" 
    elsif amount >= 1_000
      "#{(amount / 1_000.0).round(0)}K NOK"
    else
      "#{amount} NOK"
    end
  end
end