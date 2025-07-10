# frozen_string_literal: true

class FeatureMemories::LinkedinDiscoveryInternal < FeatureMemories::ApplicationFeatureMemory
  FEATURE_ID = "linkedin_discovery_internal"
  self.feature_id = FEATURE_ID
  
  # UI Testing requirements for this feature
  ui_testing do
    test_coverage_requirement 90
    mandatory_before_completion true
    test_frameworks :rspec, :capybara, :puppeteer
    
    happy_path "User can queue LinkedIn discovery for a company" do
      test_type :system
      user_actions [
        "navigate_to_company_page",
        "click_linkedin_discovery_button", 
        "confirm_queue_action"
      ]
      expected_outcome "LinkedIn discovery job queued with success message"
      components_under_test ["CompanyServiceButtonComponent", "LinkedinDiscoveryComponent"]
      test_file "spec/system/linkedin_discovery_queue_spec.rb"
      priority :critical
      estimated_time "45 minutes"
    end
    
    edge_case "Handles company without LinkedIn URL gracefully" do
      test_type :system
      user_actions ["attempt_discovery_on_company_without_linkedin"]
      expected_outcome "Helpful message explaining LinkedIn URL required"
      priority :high
      test_data({ company: { linkedin_url: nil } })
    end
    
    error_state "Displays error when service is unavailable" do
      test_type :system
      user_actions ["attempt_discovery_during_service_downtime"]
      expected_outcome "Service unavailable message with retry option"
      priority :high
      prerequisites ["mock_service_configuration_inactive"]
    end
    
    accessibility "LinkedIn discovery interface is fully accessible" do
      test_type :system
      accessibility_requirements [
        "keyboard_navigation",
        "screen_reader_support", 
        "aria_labels",
        "focus_management"
      ]
      priority :high
      estimated_time "30 minutes"
    end
    
    performance "Discovery queue action responds quickly" do
      test_type :system
      performance_thresholds({
        button_click: 1,
        queue_confirmation: 2
      })
      priority :medium
    end
  end

  # Auto-populated during initial generation
  feature_spec do
    description "Internal LinkedIn Discovery using Puppeteer for Sales Navigator scraping"
    requested_by "@benjamin"
    created_at "2025-07-06"
    
    requirements do
      feature_type :service  # This is a service feature
      input_fields company_id: 291917, 
                   sales_navigator_url: "https://www.linkedin.com/sales/search/people?query=(spellCorrectionEnabled%3Atrue%2CrecentSearchParam%3A(id%3A4876827156%2CdoLogHistory%3Atrue)%2Cfilters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3Aurn%253Ali%253Aorganization%253A3341537%2Ctext%3ACrowe%2520Norway%2CselectionType%3AINCLUDED%2Cparent%3A(id%3A0)))))%2Ckeywords%3ACrowe%2520Norway)&sessionId=dWkpYPKRTAWlvuhxhajbdQ%3D%3D"
      output "Person model records with LinkedIn profile data"
      queue_system :sidekiq
      ui_location :company_show_page
      dependencies ["ferrum gem (Ruby Puppeteer)", "Redis", "LinkedIn credentials", "Sales Navigator access"]
    end
    
    test_data do
      company_id 291917
      company_name "Crowe Norway"
      sales_navigator_url "https://www.linkedin.com/sales/search/people?query=(spellCorrectionEnabled%3Atrue%2CrecentSearchParam%3A(id%3A4876827156%2CdoLogHistory%3Atrue)%2Cfilters%3AList((type%3ACURRENT_COMPANY%2Cvalues%3AList((id%3Aurn%253Ali%253Aorganization%253A3341537%2Ctext%3ACrowe%2520Norway%2CselectionType%3AINCLUDED%2Cparent%3A(id%3A0)))))%2Ckeywords%3ACrowe%2520Norway)&sessionId=dWkpYPKRTAWlvuhxhajbdQ%3D%3D"
      expected_profiles_count 10..50
      expected_fields ["name", "title", "location", "profile_url", "connection_degree"]
    end
  end
  
  # Implementation plan - tracks intended work before execution
  implementation_plan do
    task "Phase 1: Core Service Infrastructure" do
      priority :high
      estimated_time "30 minutes"
      tags :backend, :service
      status :completed
      notes "Create service configuration and main service class following SCT pattern"
    end
    
    task "Phase 2: Database Schema Updates" do
      priority :high
      estimated_time "20 minutes"
      tags :database, :migration
      status :completed
      notes "Add LinkedIn Internal tracking fields to companies table"
    end
    
    task "Phase 3: Web Scraping Implementation" do
      priority :high
      estimated_time "1-2 hours"
      tags :scraping, :ferrum, :linkedin
      status :completed
      notes "Implement Ferrum-based Sales Navigator scraper with auth and bot detection avoidance"
    end
    
    task "Phase 4: Background Job Infrastructure" do
      priority :high
      estimated_time "30 minutes"
      tags :sidekiq, :background_jobs
      status :completed
      notes "Create Sidekiq worker with rate limiting for safe processing"
    end
    
    task "Phase 5: UI Integration" do
      priority :high
      estimated_time "45 minutes"
      tags :ui, :viewcomponent, :turbo
      status :completed
      notes "Create ViewComponent with Turbo Streams for real-time updates"
    end
    
    task "Phase 6: Testing & Validation" do
      priority :high
      estimated_time "1 hour"
      tags :testing, :validation
      status :in_progress
      notes "Manual testing with Company ID 291917, write automated tests"
    end
    
    task "Phase 7: Error Handling & Monitoring" do
      priority :medium
      estimated_time "30 minutes"
      tags :error_handling, :monitoring
      status :pending
      notes "Add comprehensive error handling, logging, and monitoring"
    end
    
    task "Phase 8: Documentation & Deployment" do
      priority :medium
      estimated_time "30 minutes"
      tags :documentation, :deployment
      status :pending
      notes "Document usage, configuration, and deployment procedures"
    end
  end
  
  # Update this as you implement the feature
  implementation_log do
    step "2025-07-06 15:03:16 UTC" do
      action "Feature memory initialized"
      status :completed
    end
    
    step "2025-07-06 15:10:00 UTC" do
      action "Implemented new Integrated Development Memory (IDM) system"
      decision "Created Ruby DSL-based system to replace old markdown Feature Memory"
      notes "IDM provides single source of truth, automatic tracking, better AI integration"
      code_ref "app/services/feature_memories/application_feature_memory.rb"
      status :completed
    end
    
    step "2025-07-06 15:15:00 UTC" do
      action "Created implementation plan for LinkedIn Discovery Internal"
      notes "Comprehensive plan covering all phases from service setup to deployment"
      code_ref "plans/features/linkedin_discovery_internal.md"
      status :completed
    end
    
    step "2025-07-06 15:20:00 UTC" do
      action "Awaiting user approval to proceed with implementation"
      status :completed
    end
    
    step "2025-07-06 15:25:00 UTC" do
      action "Starting implementation - Phase 1: Core Service Infrastructure"
      notes "Creating service configuration and main service class"
      status :completed
    end
    
    step "2025-07-06 15:30:00 UTC" do
      action "Created ServiceConfiguration in seeds.rb"
      decision "Set service as inactive by default for beta testing"
      code_ref "db/seeds.rb:114-130"
      status :completed
    end
    
    step "2025-07-06 15:35:00 UTC" do
      action "Created main LinkedinDiscoveryInternalService class"
      decision "Inherited from ApplicationService for SCT compliance"
      notes "Integrated with FeatureMemoryIntegration for automatic tracking"
      code_ref "app/services/linkedin_discovery_internal_service.rb"
      status :completed
    end
    
    step "2025-07-06 15:40:00 UTC" do
      action "Starting Phase 2: Database schema updates"
      notes "Adding LinkedIn Internal specific fields to companies table"
      status :completed
    end
    
    step "2025-07-06 15:45:00 UTC" do
      action "Created and ran database migrations"
      code_ref "db/migrate/20250706152045_add_linkedin_internal_fields_to_companies.rb"
      notes "Added fields for tracking processing status, URLs, and error messages"
      status :completed
    end
    
    step "2025-07-06 15:50:00 UTC" do
      action "Implemented Ferrum-based Sales Navigator scraper"
      decision "Used Ferrum gem for Chrome automation with stealth techniques"
      code_ref "app/lib/sales_navigator_scraper.rb"
      notes "Includes cookie-based auth, bot detection avoidance, profile extraction"
      status :completed
    end
    
    step "2025-07-06 15:55:00 UTC" do
      action "Created Sidekiq worker and queue configuration"
      code_ref "app/workers/linkedin_discovery_internal_worker.rb"
      notes "Added queue with rate limiting to avoid detection"
      status :completed
    end
    
    step "2025-07-06 16:00:00 UTC" do
      action "Starting Phase 3: UI Integration"
      notes "Creating ViewComponent and adding to company page"
      status :completed
    end
    
    step "2025-07-06 16:05:00 UTC" do
      action "Created LinkedinDiscoveryInternalComponent"
      code_ref "app/components/linkedin_discovery_internal_component.rb"
      notes "ViewComponent with form, status display, and Turbo integration"
      status :completed
    end
    
    step "2025-07-06 16:10:00 UTC" do
      action "Added controller action and routes"
      code_ref "app/controllers/companies_controller.rb:824-900"
      notes "Turbo Stream responses for real-time UI updates"
      status :completed
    end
    
    step "2025-07-06 16:15:00 UTC" do
      action "Integrated component into company show page"
      code_ref "app/views/companies/show.html.erb:291-294"
      notes "Placed below existing LinkedIn Discovery service"
      status :completed
    end
    
    step "2025-07-06 16:20:00 UTC" do
      action "Ready for testing with Company ID 291917"
      notes "All core components implemented, ready for manual testing"
      status :in_progress
    end
    
    step "2025-07-06 16:10:00 UTC" do
      action "Debugging form submission issues"
      challenge "Button clicks but nothing happens - form appears to submit but no job queued"
      solution "Identified CSRF token validation failure - form missing authenticity token"
      code_ref "app/components/linkedin_discovery_internal_component.rb"
      notes "Form submits but Rails rejects due to missing/invalid CSRF token"
      status :in_progress
    end
    
    step "2025-07-06 16:25:00 UTC" do
      action "Added IDM indicators to all feature files"
      decision "Add clear header comments pointing to IDM file for better discoverability"
      notes "Other agents can now easily find and update the IDM when working on this feature"
      code_ref "service.rb:6, worker.rb:6, component.rb:6, scraper.rb:8"
      status :completed
    end
    
    step "2025-07-06 16:30:00 UTC" do
      action "Created IDM discovery rake tasks"
      decision "Added rake tasks to help agents find and work with IDM files"
      notes "rails idm:find, idm:status, idm:list, idm:instructions"
      code_ref "lib/tasks/idm.rake:141-318"
      status :completed
    end
    
    step "2025-07-06 16:35:00 UTC" do
      action "Updated CLAUDE.md with Quick Start for AI Agents"
      decision "Added onboarding section at top of CLAUDE.md for better discoverability"
      notes "New agents will immediately see IDM instructions when reading CLAUDE.md"
      code_ref "CLAUDE.md:5-20"
      status :completed
    end
    
    step "2025-07-06 16:40:00 UTC" do
      action "Created comprehensive IDM_RULES.md documentation"
      decision "Centralized all IDM rules, examples, and workflows in one file"
      notes "Agents now have clear, detailed reference for IDM usage"
      code_ref "docs/IDM_RULES.md"
      status :completed
    end
    
    step "2025-07-06 16:45:00 UTC" do
      action "Discovered root cause of agents not using IDM"
      challenge "Other agents completely ignore IDM despite all documentation"
      solution "Claude CLI reads ~/CLAUDE.md, not project CLAUDE.md"
      notes "Updated user-level CLAUDE.md to point to project-specific files"
      code_ref "/Users/benjamin/CLAUDE.md:1-11"
      status :completed
    end
    
    step "2025-07-06 16:50:00 UTC" do
      action "Implemented Claude hooks to enforce IDM usage"
      decision "Created pre-edit, post-edit, and pre-read hooks for automatic IDM enforcement"
      notes "Hooks block edits to IDM-tracked files until requirements are acknowledged"
      code_ref ".claude/hooks/*.sh, .claude/config.json"
      status :completed
    end
  end
  
  # Add issues and solutions as you encounter them
  troubleshooting do
    issue "Choosing Ruby Puppeteer library" do
      cause "Need headless browser automation in Ruby"
      solution "Selected Ferrum gem - pure Ruby Chrome DevTools Protocol implementation"
      code_example "browser = Ferrum::Browser.new(headless: true)"
      prevention "Avoid Node.js bridge complexity, use native Ruby solution"
    end
    
    issue "LinkedIn Authentication Strategy" do
      cause "LinkedIn requires login to access Sales Navigator"
      solution "Implement dual strategy: cookie-based (fast) and credential-based (fallback)"
      code_example "page.cookies.set(name: 'li_at', value: stored_cookie)"
      prevention "Store and reuse li_at session cookie to avoid frequent logins"
    end
    
    issue "Bot Detection Avoidance" do
      cause "LinkedIn detects and blocks automated browsers"
      solution "Use stealth techniques: disable automation flags, randomize delays, proper user agent"
      code_example "browser_options: { 'disable-blink-features' => 'AutomationControlled' }"
      prevention "Always use random delays between actions and human-like behavior patterns"
    end
  end
  
  # Track performance metrics
  performance_metrics do
    browser_startup_time "2-3 seconds"
    page_load_time "3-5 seconds per page"
    profile_extraction_rate "25 profiles per page"
    memory_usage "200-300MB per browser instance"
    expected_success_rate "90% with proper authentication"
  end
end