# Database cleanup strategy for tests
RSpec.configure do |config|
  # For system tests, we need to clean the database manually
  # since they don't use transactional fixtures
  config.before(:each, type: :system) do
    # Clean up all test data to ensure isolation
    Company.destroy_all
    ServiceAuditLog.destroy_all
    Domain.destroy_all
    Person.destroy_all
    # ServiceConfiguration is handled by service_configuration_cleaner.rb
  end

  # Also clean up for component tests that might have system-like behavior
  config.before(:each, type: :component) do |example|
    # Only clean if the test uses database data
    if example.metadata[:full_description].include?("Service Stats") || 
       example.metadata[:full_description].include?("Business Logic")
      Company.destroy_all
      ServiceAuditLog.destroy_all
      Domain.destroy_all
      Person.destroy_all
    end
  end

  # Clean up for any test that mentions service stats or business logic (regardless of type)
  config.before(:each) do |example|
    if example.metadata[:full_description].include?("Service Stats") || 
       example.metadata[:full_description].include?("Business Logic") ||
       example.metadata[:file_path].include?("service_stats_consistency_spec.rb")
      Company.destroy_all
      ServiceAuditLog.destroy_all
      Domain.destroy_all
      Person.destroy_all
    end
  end
end