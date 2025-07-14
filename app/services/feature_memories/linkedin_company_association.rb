# frozen_string_literal: true

module FeatureMemories
  class LinkedinCompanyAssociation < ApplicationFeatureMemory
    self.feature_id = 'linkedin_company_association'

    # Initialize the feature memory
    feature_spec do
      description "Associate unassociated people with companies based on LinkedIn company IDs"
      requested_by "Development Team"
      created_at Time.current.to_s
      
      requirements do
        feature_type "Data Association Service"
        user_interaction "Background Processing"
        components ["LinkedinCompanyAssociationService", "LinkedinCompanyLookup", "LinkedinCompanySlugService"]
        queue_system "Sidekiq"
        api_endpoint "Internal Background Jobs"
        dependencies ["LinkedinCompanyDataService", "ServiceConfiguration", "PhantomBuster Import"]
        
        # Technical requirements
        processing_schedule "Every 2 hours for associations, every 12 hours for lookup refresh"
        batch_size 500
        lookup_strategy "Multi-tier: Direct ID → Slug conversion → Fuzzy matching"
        performance_target "< 2 seconds per record, 95%+ success rate"
        
        # Data requirements
        source_data "People with linkedin_company_id but no company_id"
        target_data "Companies with linkedin_company_id or linkedin_slug"
        lookup_table "LinkedinCompanyLookup with caching and confidence scoring"
        
        # Service requirements
        sct_compliance true
        audit_logging true
        error_recovery true
        monitoring_dashboard true
      end
      
      test_data do
        sample_person_linkedin_id "51649953"
        sample_company_slug "betonmast"
        sample_company_linkedin_id "51649953"
        unassociated_people_count "~2000 records"
        companies_with_linkedin_data "~800 records"
        expected_match_rate "85-95%"
      end
    end

    # Implementation plan with detailed tasks
    implementation_plan do
      task "Phase 1: Foundation & Data Normalization" do
        priority :high
        estimated_time "1 week"
        tags :foundation, :data_normalization
        
        dependencies []
        notes "Create base infrastructure for LinkedIn company association"
      end
      
      task "Create LinkedinCompanyLookup model and migration" do
        priority :high
        estimated_time "2 hours"
        tags :model, :database
        dependencies []
        notes "Persistent lookup table for efficient company resolution"
      end
      
      task "Implement LinkedinCompanySlugService" do
        priority :high
        estimated_time "4 hours"
        tags :service, :data_processing
        dependencies []
        notes "Extracts slugs from company LinkedIn URLs and populates linkedin_slug field"
      end
      
      task "Create service configuration for slug population" do
        priority :medium
        estimated_time "1 hour"
        tags :configuration, :sct
        dependencies []
        notes "SCT configuration for LinkedIn slug population service"
      end
      
      task "Phase 2: Association Engine" do
        priority :high
        estimated_time "1 week"
        tags :core_logic, :association
        dependencies []
        notes "Core association logic and background processing"
      end
      
      task "Implement LinkedinCompanyAssociationService" do
        priority :high
        estimated_time "6 hours"
        tags :service, :core_logic
        dependencies []
        notes "Main service for associating people with companies via LinkedIn IDs"
      end
      
      task "Create LinkedinCompanyAssociationWorker" do
        priority :high
        estimated_time "2 hours"
        tags :background_job, :sidekiq
        dependencies []
        notes "Sidekiq worker for background processing of associations"
      end
      
      task "Add Person and Company model scopes" do
        priority :medium
        estimated_time "1 hour"
        tags :model, :scopes
        dependencies []
        notes "Efficient querying for unassociated people and companies with LinkedIn data"
      end
      
      task "Phase 3: Lookup Optimization" do
        priority :medium
        estimated_time "1 week"
        tags :optimization, :caching
        dependencies []
        notes "Implement caching and lookup optimization strategies"
      end
      
      task "Implement LinkedinCompanyResolver" do
        priority :medium
        estimated_time "4 hours"
        tags :resolver, :caching
        dependencies []
        notes "Multi-strategy lookup resolver with caching and fallback mechanisms"
      end
      
      task "Add Redis caching for lookups" do
        priority :medium
        estimated_time "2 hours"
        tags :caching, :redis
        dependencies []
        notes "Cache hot lookup data with 1-hour TTL"
      end
      
      task "Implement lookup table refresh mechanism" do
        priority :medium
        estimated_time "3 hours"
        tags :maintenance, :background_job
        dependencies []
        notes "Periodic refresh of lookup table data"
      end
      
      task "Phase 4: Error Recovery & Monitoring" do
        priority :medium
        estimated_time "1 week"
        tags :monitoring, :error_handling
        dependencies []
        notes "Comprehensive error handling and monitoring dashboard"
      end
      
      task "Implement LinkedinAssociationErrorHandler" do
        priority :medium
        estimated_time "3 hours"
        tags :error_handling, :recovery
        dependencies []
        notes "Handles malformed data, API limits, and processing failures"
      end
      
      task "Create monitoring dashboard" do
        priority :low
        estimated_time "4 hours"
        tags :monitoring, :dashboard
        dependencies []
        notes "Status dashboard for association success rates and queue health"
      end
      
      task "Add service configurations" do
        priority :high
        estimated_time "1 hour"
        tags :configuration, :sct
        dependencies []
        notes "SCT configurations for all LinkedIn association services"
      end
      
      task "Write comprehensive tests" do
        priority :high
        estimated_time "8 hours"
        tags :testing, :rspec
        dependencies []
        notes "Unit tests, integration tests, and performance tests"
      end
      
      task "Create documentation" do
        priority :medium
        estimated_time "3 hours"
        tags :documentation
        dependencies []
        notes "Comprehensive documentation for the LinkedIn association feature"
      end
      
      task "Deploy and monitor" do
        priority :low
        estimated_time "4 hours"
        tags :deployment, :monitoring
        dependencies []
        notes "Production deployment with monitoring and alerting"
      end
    end

    # Initial implementation log
    implementation_log do
      step Time.current.to_s do
        action "Created LinkedIn Company Association feature memory"
        decision "Using IDM system for comprehensive feature documentation and tracking"
        status :planning
        notes "Established feature memory with detailed implementation plan and requirements"
      end
    end

    # Performance metrics tracking
    performance_metrics do
      target_processing_time "< 2 seconds per record"
      target_success_rate "95%+"
      target_daily_processing "2000+ records"
      cache_hit_rate "85%+"
      api_call_efficiency "< 1000 LinkedIn API calls per day"
      queue_processing_time "< 30 minutes per batch"
      lookup_table_size "< 10MB"
      memory_usage "< 500MB per worker"
    end

    # UI Testing requirements
    ui_testing do
      scenario "admin_association_monitoring" do
        description "Admin can monitor association processing status"
        priority :high
        test_steps [
          "Navigate to admin dashboard",
          "View LinkedIn association status",
          "Check processing queue health",
          "Review error logs and success rates"
        ]
        expected_result "Clear visibility into association processing"
        status :pending
      end
      
      scenario "error_handling_display" do
        description "Error handling displays meaningful messages"
        priority :medium
        test_steps [
          "Trigger association error",
          "Check error logging",
          "Verify recovery mechanisms",
          "Test notification system"
        ]
        expected_result "Graceful error handling with recovery options"
        status :pending
      end
      
      scenario "performance_monitoring" do
        description "Performance metrics are tracked and displayed"
        priority :medium
        test_steps [
          "Run large batch processing",
          "Monitor processing times",
          "Check success rates",
          "Verify cache efficiency"
        ]
        expected_result "Real-time performance monitoring"
        status :pending
      end
    end

    # Troubleshooting guide
    troubleshooting do
      issue "Low association success rate" do
        cause "LinkedIn IDs may be malformed or companies may not exist in database"
        solution "Implement confidence scoring and fallback matching strategies"
        prevention "Validate LinkedIn IDs before processing and maintain lookup table freshness"
      end
      
      issue "Processing queue backup" do
        cause "Large volume of new people or slow processing times"
        solution "Increase batch size, add more workers, or optimize lookup queries"
        prevention "Monitor queue depth and auto-scale processing capacity"
      end
      
      issue "Memory usage spikes" do
        cause "Large batch processing or inefficient caching"
        solution "Optimize batch sizes, implement memory-efficient caching, and add garbage collection"
        prevention "Monitor memory usage and implement circuit breakers"
      end
    end
  end
end