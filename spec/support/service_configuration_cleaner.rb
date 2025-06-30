# Clean up ServiceConfiguration records between tests to avoid duplicate key errors
RSpec.configure do |config|
  config.before(:each) do
    # Clear any existing ServiceConfiguration records to avoid duplicate key errors
    ServiceConfiguration.destroy_all
  end
end