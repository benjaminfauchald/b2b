# frozen_string_literal: true

# ============================================================================
# LinkedIn Discovery Internal Worker
# ============================================================================
# Feature tracked by IDM: app/services/feature_memories/linkedin_discovery_internal.rb
# 
# IMPORTANT: When making changes to this worker:
# 1. Check IDM status: FeatureMemories::LinkedinDiscoveryInternal.plan_status
# 2. Update implementation_log with your changes
# 3. Follow the IDM communication protocol in CLAUDE.md
# ============================================================================
#
# Background worker for LinkedIn Discovery Internal service
class LinkedinDiscoveryInternalWorker
  include Sidekiq::Worker

  sidekiq_options queue: "linkedin_discovery_internal", retry: 3

  def perform(company_id, sales_navigator_url = nil)
    Rails.logger.info "LinkedinDiscoveryInternalWorker: Processing company #{company_id}"
    
    begin
      Rails.logger.info "LinkedinDiscoveryInternalWorker: Initializing service..."
      service = LinkedinDiscoveryInternalService.new
      Rails.logger.info "LinkedinDiscoveryInternalWorker: Service initialized, calling process_single_company..."
      result = service.process_single_company(company_id, sales_navigator_url)
      Rails.logger.info "LinkedinDiscoveryInternalWorker: process_single_company returned: #{result.inspect}"
    rescue StandardError => e
      Rails.logger.error "LinkedinDiscoveryInternalWorker: Error during processing: #{e.message}"
      Rails.logger.error "LinkedinDiscoveryInternalWorker: Backtrace: #{e.backtrace.first(5).join('\n')}"
      raise e
    end
    
    if result[:success]
      Rails.logger.info "LinkedinDiscoveryInternalWorker: Successfully processed company #{company_id} - found #{result[:profiles_count]} profiles"
    else
      Rails.logger.error "LinkedinDiscoveryInternalWorker: Failed to process company #{company_id} - #{result[:error]}"
      
      # Re-raise error for Sidekiq retry logic
      raise StandardError, result[:error]
    end
  end
end