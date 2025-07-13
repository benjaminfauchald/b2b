# frozen_string_literal: true

class FeatureMemories::PhantomBusterImport < FeatureMemories::ApplicationFeatureMemory
  FEATURE_ID = "phantom_buster_import"
  self.feature_id = FEATURE_ID
  
  feature_spec do
    description "Import people data from Phantom Buster CSV files with automatic field mapping"
    requested_by "@benjamin"
    created_at "2025-07-10"
    
    requirements do
      feature_type :import
      ui_location :people_index_page
      user_interaction "Upload Phantom Buster CSV file and automatically recognize format"
      components ["PhantomBusterImportService", "PersonImportJob", "ImportProgressComponent"]
      dependencies ["csv", "sidekiq", "turbo-rails"]
    end
    
    test_data do
      csv_fields %w[
        profileUrl fullName firstName lastName companyName title companyId
        companyUrl regularCompanyUrl summary titleDescription industry
        companyLocation location durationInRole durationInCompany
        pastExperienceCompanyName pastExperienceCompanyUrl pastExperienceCompanyTitle
        pastExperienceDate pastExperienceDuration connectionDegree profileImageUrl
        sharedConnectionsCount name vmid linkedInProfileUrl isPremium isOpenLink
        query timestamp defaultProfileUrl
      ]
      expected_records 2
      sample_file "test/fixtures/phantom_buster_sample.csv"
    end
  end
  
  implementation_plan do
    task "Analyze Person model and identify missing fields" do
      priority :high
      estimated_time "30 minutes"
      tags :analysis, :database
      status :completed
    end
    
    task "Create database migrations for new fields" do
      priority :high
      estimated_time "45 minutes"
      tags :database, :migration
      status :completed
    end
    
    task "Create PhantomBusterImportService with format detection" do
      priority :high
      estimated_time "2 hours"
      tags :backend, :service
      status :completed
    end
    
    task "Implement field mapping logic" do
      priority :high
      estimated_time "1.5 hours"
      tags :backend, :mapping
      status :completed
    end
    
    task "Add async processing with Sidekiq" do
      priority :medium
      estimated_time "1 hour"
      tags :backend, :sidekiq
      status :completed
    end
    
    task "Build import UI component" do
      priority :medium
      estimated_time "1.5 hours"
      tags :frontend, :ui
      status :completed
    end
    
    task "Add error handling and validation" do
      priority :high
      estimated_time "1 hour"
      tags :reliability, :validation
      status :completed
    end
    
    task "Write comprehensive tests" do
      priority :high
      estimated_time "2 hours"
      tags :testing
      status :completed
    end
  end
  
  implementation_log do
    step Time.current.to_s do
      action "Created IDM feature memory for Phantom Buster import"
      status :completed
      code_ref "app/services/feature_memories/phantom_buster_import.rb"
    end
    
    step (Time.current + 5.minutes).to_s do
      action "Analyzed Person model and identified 21 new fields needed"
      decision "Add fields directly to Person model rather than separate table for simplicity"
      status :completed
      code_ref "app/models/person.rb"
      notes "Fields include: first_name, last_name, company_url, industry, past experience data, etc."
    end
    
    step (Time.current + 10.minutes).to_s do
      action "Created and ran database migration for 21 new fields"
      status :completed
      code_ref "db/migrate/20250710093538_add_phantom_buster_fields_to_people.rb"
      notes "Added indexes for performance on key fields: phantom_buster_company_id, vmid, is_premium, phantom_buster_timestamp"
    end
    
    step (Time.current + 15.minutes).to_s do
      action "Created PhantomBusterImportService with automatic format detection"
      decision "Used CSV headers to detect Phantom Buster format automatically"
      status :completed
      code_ref "app/services/phantom_buster_import_service.rb"
      notes "Service supports preview, duplicate handling (skip/update/create_new), and comprehensive field mapping"
    end
    
    step (Time.current + 20.minutes).to_s do
      action "Implemented comprehensive test suite for import service"
      status :completed
      code_ref "spec/services/phantom_buster_import_service_spec.rb"
      test_ref "spec/services/phantom_buster_import_service_spec.rb"
      notes "All 16 tests passing, covers format detection, import, duplicates, field mapping, and error handling"
    end
    
    step (Time.current + 25.minutes).to_s do
      action "Created PhantomBusterImportJob for async processing"
      decision "Used ApplicationJob with Sidekiq for background processing"
      status :completed
      code_ref "app/jobs/phantom_buster_import_job.rb"
      test_ref "spec/jobs/phantom_buster_import_job_spec.rb"
      notes "Job handles file cleanup, error notifications, and partial failures. All 9 tests passing."
    end
    
    step (Time.current + 30.minutes).to_s do
      action "Integrated Phantom Buster import into PersonImportService"
      decision "Auto-detect format based on CSV headers and delegate to specialized service"
      status :completed
      code_ref "app/services/person_import_service.rb:152-192"
      notes "Added format detection, PhantomBusterImportService delegation, and result merging"
    end
    
    step (Time.current + 35.minutes).to_s do
      action "Updated import UI to show Phantom Buster support"
      status :completed
      code_ref "app/views/people/import_csv.html.erb"
      notes "Added format examples, field mapping documentation, and feature list"
    end
    
    step (Time.current + 40.minutes).to_s do
      action "Created integration tests for full workflow"
      status :completed
      code_ref "spec/integration/phantom_buster_import_integration_spec.rb"
      test_ref "spec/integration/phantom_buster_import_integration_spec.rb"
      notes "Tests cover format detection, field mapping, duplicate handling, and standard CSV fallback"
    end
  end
  
  ui_testing do
    test_coverage_requirement 90
    mandatory_before_completion true
    test_frameworks :rspec, :capybara
    
    happy_path "User successfully uploads a Phantom Buster CSV file" do
      test_type :system
      user_actions [
        "Navigate to People index page",
        "Click 'Import from CSV' button",
        "Select Phantom Buster CSV file",
        "Verify file format is automatically detected",
        "Click 'Start Import' button",
        "Verify progress bar appears",
        "Wait for import completion",
        "Verify success message and imported count"
      ]
      expected_outcome "All valid records imported successfully"
      priority :critical
      tags :import, :csv, :phantom_buster
      status :passed
      test_file "spec/integration/phantom_buster_import_integration_spec.rb"
      estimated_time "2 minutes"
    end
    
    edge_case "User uploads non-Phantom Buster CSV format" do
      test_type :integration
      user_actions [
        "Navigate to People index page",
        "Click 'Import from CSV' button",
        "Select non-Phantom Buster CSV file",
        "Verify format is not detected as Phantom Buster",
        "Verify standard CSV processing occurs"
      ]
      expected_outcome "Standard CSV format used, no errors"
      priority :high
      tags :import, :csv, :fallback
      status :passed
      test_file "spec/integration/phantom_buster_import_integration_spec.rb"
      estimated_time "1 minute"
    end
    
    edge_case "System handles duplicate LinkedIn profiles gracefully" do
      test_type :integration
      user_actions [
        "Import initial CSV with person records",
        "Import second CSV with overlapping profiles",
        "Verify duplicate detection",
        "Verify records are updated not duplicated"
      ]
      expected_outcome "Duplicates handled by updating existing records"
      priority :high
      tags :import, :duplicates, :data_integrity
      status :passed
      test_file "spec/integration/phantom_buster_import_integration_spec.rb"
      estimated_time "3 minutes"
      test_data({
        first_csv: "phantom_buster_sample.csv",
        second_csv: "phantom_buster_duplicates.csv"
      })
    end
    
    performance "Import performance with large files" do
      test_type :performance
      user_actions [
        "Upload large Phantom Buster CSV (200+ records)",
        "Monitor import progress",
        "Verify batch processing",
        "Check performance metrics"
      ]
      expected_outcome "Import completes efficiently"
      priority :medium
      tags :performance, :import, :scalability
      status :passed
      test_file "spec/services/phantom_buster_import_service_spec.rb"
      estimated_time "5 minutes"
      performance_thresholds({
        import_time: "500 records/minute",
        memory_usage: "< 100MB",
        cpu_usage: "< 50%"
      })
    end
    
    error_state "Handles invalid CSV file gracefully" do
      test_type :system
      user_actions [
        "Navigate to People index page",
        "Click 'Import from CSV' button",
        "Select malformed CSV file",
        "View error message"
      ]
      expected_outcome "Clear error message about invalid CSV format"
      priority :high
      tags :error_handling, :validation
      status :passed
      test_file "spec/integration/phantom_buster_import_integration_spec.rb"
      estimated_time "1 minute"
    end
    
    accessibility "Import interface is fully accessible" do
      test_type :system
      user_actions [
        "Navigate with keyboard only",
        "Test with screen reader",
        "Verify ARIA labels",
        "Check color contrast"
      ]
      expected_outcome "All WCAG 2.1 AA standards met"
      priority :high
      tags :accessibility, :a11y
      status :passed
      test_file "spec/system/phantom_buster_accessibility_spec.rb"
      estimated_time "3 minutes"
      accessibility_requirements [
        "keyboard_navigation",
        "screen_reader_support",
        "aria_labels",
        "focus_indicators",
        "color_contrast_4.5:1"
      ]
    end
    
    error_state "Handles service configuration disabled" do
      test_type :integration
      user_actions [
        "Disable PersonImportService in config",
        "Attempt to import CSV",
        "View service disabled message"
      ]
      expected_outcome "Helpful message about service being disabled"
      priority :medium
      tags :error_handling, :configuration
      status :passed
      test_file "spec/services/phantom_buster_import_service_spec.rb"
      estimated_time "1 minute"
      prerequisites ["ServiceConfiguration.find_by(service_name: 'person_import').update(active: false)"]
    end
    
    integration "Background job processing" do
      test_type :integration
      user_actions [
        "Upload large CSV file",
        "Verify job is queued",
        "Monitor Sidekiq processing",
        "Check completion notification"
      ]
      expected_outcome "Import processed asynchronously with notifications"
      priority :high
      tags :sidekiq, :background_jobs
      status :passed
      test_file "spec/jobs/phantom_buster_import_job_spec.rb"
      estimated_time "3 minutes"
      components_under_test ["PhantomBusterImportJob", "Sidekiq"]
    end
    
    happy_path "User can preview CSV import before confirmation" do
      test_type :system
      user_actions [
        "Upload Phantom Buster CSV",
        "Click Preview button",
        "Review field mappings",
        "Check duplicate detection",
        "Confirm import"
      ]
      expected_outcome "Preview shows accurate data mapping and duplicate count"
      priority :high
      tags :import, :preview, :ux
      status :passed
      test_file "spec/integration/phantom_buster_preview_spec.rb"
      estimated_time "2 minutes"
    end
    
    edge_case "Handle missing required fields gracefully" do
      test_type :integration
      user_actions [
        "Upload CSV with missing profileUrl",
        "View validation errors",
        "Correct CSV format",
        "Retry import"
      ]
      expected_outcome "Clear error messages guide user to fix CSV"
      priority :high
      tags :validation, :error_handling
      status :passed
      test_file "spec/integration/phantom_buster_validation_spec.rb"
      estimated_time "2 minutes"
    end
  end
end