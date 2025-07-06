# frozen_string_literal: true

class FeatureMemories::CompanySearchAutocomplete < FeatureMemories::ApplicationFeatureMemory
  FEATURE_ID = "company_search_autocomplete"
  self.feature_id = FEATURE_ID
  
  # Auto-populated during initial generation
  feature_spec do
    description "Add autocomplete to company search field"
    requested_by "@benjamin"
    created_at "2025-07-06"
    
    requirements do
      feature_type :ui
      ui_location :companies_index_page
      user_interaction "Type in search field to see suggestions"
      components ["CompanySearchAutocompleteComponent"]
      javascript_framework "Stimulus controller with Turbo Streams"
      api_endpoint "GET /companies/search_suggestions"
      debounce_delay "300ms"
      min_characters 2
      max_suggestions 10
      dependencies ["turbo-rails", "stimulus-rails"]
    end
    
    test_data do
      # TODO: Fill in test data
      example_id 12345
      expected_result "sample result"
    end
  end
  
  # Plan your implementation before starting
  implementation_plan do
    task "Research existing autocomplete patterns in codebase" do
      priority :high
      estimated_time "15 minutes"
      tags :research, :ui
    end
    
    task "Create Stimulus controller for autocomplete" do
      priority :high
      estimated_time "45 minutes"
      tags :javascript, :stimulus
    end
    
    task "Add search_suggestions endpoint to CompaniesController" do
      priority :high
      estimated_time "30 minutes"
      tags :backend, :api
    end
    
    task "Create CompanySearchAutocompleteComponent" do
      priority :high
      estimated_time "30 minutes"
      tags :viewcomponent, :ui
    end
    
    task "Implement debouncing and minimum character requirements" do
      priority :medium
      estimated_time "20 minutes"
      tags :javascript, :performance
    end
    
    task "Style dropdown with Flowbite/Tailwind" do
      priority :medium
      estimated_time "30 minutes"
      tags :css, :design
    end
    
    task "Add keyboard navigation support" do
      priority :medium
      estimated_time "30 minutes"
      tags :accessibility, :javascript
    end
    
    task "Write integration tests" do
      priority :high
      estimated_time "45 minutes"
      tags :testing
    end
  end
  
  # Update this as you implement the feature
  implementation_log do
    step "2025-07-06 15:30:19 UTC" do
      action "Feature memory initialized"
      status :planning
    end
  end
  
  # Add issues and solutions as you encounter them
  troubleshooting do
    # Example:
    # issue "Description of problem" do
    #   cause "Why it happens"
    #   solution "How to fix it"
    #   code_example "sample_code"
    #   prevention "How to avoid it"
    # end
  end
  
  # Track performance metrics
  performance_metrics do
    # Example:
    # processing_time "2-5 seconds"
    # memory_usage "50MB"
    # success_rate "95%"
  end
end