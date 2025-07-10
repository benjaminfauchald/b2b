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


  def batch_size_options
    base_options = [10, 25, 50, 100, 200, 500, 1000]
    available_count = company_preview[:count]
    
    if available_count > 0
      # Only show options that don't exceed available company count
      valid_options = base_options.select { |option| option <= available_count }
      
      # Always include the exact available count if it's not already in the list
      # and it's greater than the largest valid option
      if valid_options.empty? || available_count < base_options.first
        # If available count is less than 10, just show that number
        valid_options = [available_count]
      elsif available_count > valid_options.last
        valid_options << available_count
      end
      
      valid_options.sort
    else
      # If no companies available, return empty array
      []
    end
  end

  private

  def calculate_company_preview
    return { count: 0, revenue_range: nil } if postal_code.blank?

    # Use same filtering logic as controller - companies that need LinkedIn discovery
    companies = Company.where(postal_code: postal_code)
                      .where.not(operating_revenue: nil)
                      .needing_service("company_linkedin_discovery")
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