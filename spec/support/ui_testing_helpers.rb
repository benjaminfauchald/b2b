# frozen_string_literal: true

# UI Testing Helpers for IDM Feature Development
# Provides standardized test templates and utilities for comprehensive UI testing

module UITestingHelpers
  # Template for happy path system tests
  def self.happy_path_template(feature_name, component_name, user_actions)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Happy Path", type: :system do
        let(:user) { create(:user) }
        
        before do
          sign_in user
          # Add any specific setup for #{feature_name}
        end

        it "allows user to complete #{feature_name} successfully" do
          # Navigate to the feature
          visit #{component_name.underscore}_path
          
          # Execute user actions
          #{user_actions.map { |action| "# #{action}" }.join("\n          ")}
          
          # Verify successful completion
          expect(page).to have_text("Success")
          expect(page).to have_current_path(success_path)
          
          # Take screenshot for documentation
          screenshot_and_save_page
        end
      end
    TEMPLATE
  end

  # Template for edge case tests
  def self.edge_case_template(feature_name, test_scenario, expected_behavior)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Edge Cases", type: :system do
        let(:user) { create(:user) }
        
        before do
          sign_in user
        end

        it "handles #{test_scenario} appropriately" do
          # Setup edge case conditions
          
          # Execute the scenario
          
          # Verify expected behavior
          expect(page).to have_text("#{expected_behavior}")
          
          # Verify system remains stable
          expect(page).not_to have_text("Error")
          expect(page).not_to have_text("500")
        end
      end
    TEMPLATE
  end

  # Template for error state tests
  def self.error_state_template(feature_name, error_condition, expected_message)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Error Handling", type: :system do
        let(:user) { create(:user) }
        
        before do
          sign_in user
        end

        it "displays appropriate error for #{error_condition}" do
          # Setup error condition
          
          # Trigger the error
          
          # Verify graceful error handling
          expect(page).to have_text("#{expected_message}")
          expect(page).to have_css(".alert, .error, [role='alert']")
          
          # Verify user can recover
          expect(page).to have_button("Try Again").or(have_link("Back"))
        end
      end
    TEMPLATE
  end

  # Template for accessibility tests
  def self.accessibility_template(feature_name, component_name)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Accessibility", type: :system do
        let(:user) { create(:user) }
        
        before do
          sign_in user
          visit #{component_name.underscore}_path
        end

        it "supports keyboard navigation" do
          # Test tab navigation
          page.driver.browser.action.send_keys(:tab).perform
          expect(page).to have_selector(':focus')
          
          # Test enter/space activation
          find(':focus').send_keys(:enter)
          
          # Verify functionality works with keyboard
          expect(page).to have_text("Action completed")
        end

        it "has proper ARIA labels and roles" do
          # Check for required ARIA attributes
          expect(page).to have_css('[role]')
          expect(page).to have_css('[aria-label], [aria-labelledby]')
          
          # Check form labels
          page.all('input, select, textarea').each do |field|
            field_id = field[:id]
            expect(page).to have_css("label[for='\#{field_id}']") if field_id
          end
        end

        it "provides proper error announcements" do
          # Trigger validation error
          click_button "Submit"
          
          # Check for aria-live regions
          expect(page).to have_css('[aria-live], [role="alert"]')
        end

        it "maintains focus management" do
          # Test focus management during dynamic updates
          click_button "Show Modal"
          expect(page).to have_selector(':focus', wait: 1)
          
          # Test focus return
          find('[data-dismiss="modal"]').click
          expect(page).to have_selector(':focus')
        end
      end
    TEMPLATE
  end

  # Template for performance tests
  def self.performance_template(feature_name, performance_thresholds)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Performance", type: :system do
        let(:user) { create(:user) }
        
        before do
          sign_in user
        end

        it "loads within acceptable time limits" do
          start_time = Time.current
          visit #{feature_name.underscore}_path
          load_time = Time.current - start_time
          
          expect(load_time).to be < #{performance_thresholds[:page_load] || 3}.seconds
        end

        it "handles form submission efficiently" do
          visit #{feature_name.underscore}_path
          
          start_time = Time.current
          # Fill and submit form
          submit_time = Time.current - start_time
          
          expect(submit_time).to be < #{performance_thresholds[:form_submit] || 2}.seconds
        end

        it "responds to user interactions quickly" do
          visit #{feature_name.underscore}_path
          
          # Test interaction response time
          start_time = Time.current
          click_button "Interactive Button"
          response_time = Time.current - start_time
          
          expect(response_time).to be < #{performance_thresholds[:interaction] || 1}.second
        end
      end
    TEMPLATE
  end

  # Template for ViewComponent unit tests
  def self.component_test_template(component_name, required_props)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe #{component_name}, type: :component do
        let(:component) { described_class.new(#{required_props.join(', ')}) }

        it "renders successfully with required props" do
          render_inline(component)
          
          expect(rendered_component).to be_present
          expect(rendered_component).not_to include("Error")
        end

        it "includes proper accessibility attributes" do
          render_inline(component)
          
          expect(rendered_component).to have_css('[role], [aria-label], [aria-labelledby]')
        end

        it "applies correct CSS classes" do
          render_inline(component)
          
          expect(rendered_component).to have_css('.#{component_name.underscore.dasherize}')
        end

        it "handles missing optional props gracefully" do
          minimal_component = described_class.new(#{required_props.take(1).join(', ')})
          render_inline(minimal_component)
          
          expect(rendered_component).to be_present
        end
      end
    TEMPLATE
  end

  # Template for integration tests
  def self.integration_template(feature_name, api_endpoints)
    <<~TEMPLATE
      require 'rails_helper'

      RSpec.describe "#{feature_name} Integration", type: :request do
        let(:user) { create(:user) }
        let(:headers) { { 'Content-Type' => 'application/json' } }

        before do
          sign_in user
        end

        #{api_endpoints.map do |endpoint|
          <<~ENDPOINT
            describe "#{endpoint[:method].upcase} #{endpoint[:path]}" do
              it "returns successful response" do
                #{endpoint[:method]}(#{endpoint[:path]}, headers: headers)
                
                expect(response).to have_http_status(:success)
                expect(response.content_type).to include('application/json')
              end

              it "includes required data structure" do
                #{endpoint[:method]}(#{endpoint[:path]}, headers: headers)
                
                json = JSON.parse(response.body)
                expect(json).to include(#{endpoint[:required_fields].map(&:to_s).join(', ')})
              end
            end
          ENDPOINT
        end.join("\n\n        ")}
      end
    TEMPLATE
  end

  # Helper method to generate complete test suite
  def self.generate_complete_test_suite(feature_name, options = {})
    tests = {}
    
    tests[:happy_path] = happy_path_template(
      feature_name,
      options[:component_name] || feature_name,
      options[:user_actions] || ["navigate to #{feature_name}", "interact with form", "submit data"]
    )
    
    tests[:edge_cases] = edge_case_template(
      feature_name,
      options[:edge_scenario] || "invalid input",
      options[:edge_behavior] || "validation error displayed"
    )
    
    tests[:error_states] = error_state_template(
      feature_name,
      options[:error_condition] || "server error",
      options[:error_message] || "Something went wrong. Please try again."
    )
    
    tests[:accessibility] = accessibility_template(
      feature_name,
      options[:component_name] || feature_name
    )
    
    tests[:performance] = performance_template(
      feature_name,
      options[:performance_thresholds] || {}
    )
    
    if options[:component_name]
      tests[:component] = component_test_template(
        options[:component_name],
        options[:required_props] || ["text: 'Test'"]
      )
    end
    
    if options[:api_endpoints]
      tests[:integration] = integration_template(
        feature_name,
        options[:api_endpoints]
      )
    end
    
    tests
  end

  # Helper for Puppeteer E2E test template
  def self.puppeteer_template(feature_name, test_scenario)
    <<~TEMPLATE
      const puppeteer = require('puppeteer');
      const { PUPPETEER_CONFIG, createConfiguredPage, takeStandardScreenshot } = require('./puppeteer_config');

      async function test#{feature_name.camelize}#{test_scenario.camelize}() {
        const browser = await puppeteer.launch(PUPPETEER_CONFIG.launch);
        
        try {
          const page = await createConfiguredPage(browser);
          
          // Navigate to the application
          await page.goto('https://local.connectica.no/#{feature_name.underscore}');
          
          // Wait for page to load
          await page.waitForSelector('[data-testid="#{feature_name.underscore}-container"]', { timeout: 10000 });
          
          // Execute test scenario
          // #{test_scenario.humanize}
          
          // Take screenshot
          await takeStandardScreenshot(page, `tmp/screenshots/#{feature_name.underscore}_#{test_scenario}.png`);
          
          // Verify expected outcome
          const successElement = await page.$('[data-testid="success-message"]');
          if (!successElement) {
            throw new Error('Success message not found');
          }
          
          console.log('✅ #{feature_name.humanize} #{test_scenario.humanize} test passed');
          
        } catch (error) {
          console.error('❌ #{feature_name.humanize} #{test_scenario.humanize} test failed:', error.message);
          
          // Take failure screenshot
          await takeStandardScreenshot(page, `tmp/screenshots/#{feature_name.underscore}_#{test_scenario}_failure.png`);
          
          throw error;
        } finally {
          await browser.close();
        }
      }

      // Run the test
      if (require.main === module) {
        test#{feature_name.camelize}#{test_scenario.camelize}()
          .then(() => process.exit(0))
          .catch(() => process.exit(1));
      }

      module.exports = test#{feature_name.camelize}#{test_scenario.camelize};
    TEMPLATE
  end
end

# Extension for RSpec to include UI testing helpers
RSpec.configure do |config|
  config.include UITestingHelpers, type: :system
  config.include UITestingHelpers, type: :component
  config.include UITestingHelpers, type: :request
end