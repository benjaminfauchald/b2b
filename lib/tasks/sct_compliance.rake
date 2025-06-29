# frozen_string_literal: true

namespace :sct do
  desc "Check SCT pattern compliance for all ApplicationService subclasses"
  task compliance: :environment do
    puts "🔍 Checking SCT Pattern Compliance..."
    puts "=" * 60

    services = find_all_services
    compliance_results = []

    services.each do |service_class|
      result = check_service_compliance(service_class)
      compliance_results << result
      print_service_result(result)
    end

    print_summary(compliance_results)

    # Exit with error code if any services are non-compliant
    non_compliant = compliance_results.count { |r| !r[:compliant] }
    exit(1) if non_compliant > 0
  end

  desc "Generate ServiceConfiguration records for services missing them"
  task generate_configs: :environment do
    puts "🔧 Generating missing ServiceConfiguration records..."

    services = find_all_services
    created_count = 0

    services.each do |service_class|
      service_name = extract_service_name(service_class)
      next if service_name.nil?

      unless ServiceConfiguration.exists?(service_name: service_name)
        ServiceConfiguration.create!(
          service_name: service_name,
          active: true,
          refresh_interval_hours: 24,
          batch_size: 100,
          max_retries: 3,
          retry_delay_minutes: 5,
          description: "Auto-generated configuration for #{service_class.name}",
          metadata: {
            auto_generated: true,
            created_at: Time.current.iso8601,
            service_class: service_class.name
          }
        )
        puts "✅ Created ServiceConfiguration for #{service_name}"
        created_count += 1
      end
    end

    puts "\n📊 Summary: Created #{created_count} ServiceConfiguration records"
  end

  desc "Run SCT compliance tests"
  task test: :environment do
    puts "🧪 Running SCT compliance tests..."
    system("bundle exec rspec spec/support/shared_examples/sct_compliance.rb -v")
  end

  desc "Full SCT compliance check (compliance + configs + tests)"
  task full_check: [ :compliance, :generate_configs, :test ] do
    puts "\n✅ Full SCT compliance check completed!"
  end

  private

  def find_all_services
    # Load all service files
    Dir.glob(Rails.root.join("app/services/**/*.rb")).each { |f| require f }

    # Find all ApplicationService subclasses
    ApplicationService.descendants.reject do |klass|
      # Exclude abstract base classes and test utilities
      klass.name.in?([ "ApplicationService", "TestService" ]) ||
      klass.name.include?("Test") ||
      klass.name.include?("Mock")
    end
  end

  def check_service_compliance(service_class)
    result = {
      service_class: service_class,
      service_name: extract_service_name(service_class),
      compliant: true,
      errors: [],
      warnings: []
    }

    begin
      # Check if we can instantiate the service
      instance = service_class.new

      # Check required methods
      check_required_methods(result, instance)

      # Check service configuration
      check_service_configuration(result, instance)

      # Check inheritance
      check_inheritance(result, service_class)

    rescue => e
      result[:errors] << "Cannot instantiate service: #{e.message}"
      result[:compliant] = false
    end

    result
  end

  def extract_service_name(service_class)
    return nil unless service_class.respond_to?(:new)

    begin
      instance = service_class.new
      instance.service_name if instance.respond_to?(:service_name)
    rescue
      # If we can't instantiate, derive from class name
      service_class.name.underscore
    end
  end

  def check_required_methods(result, instance)
    required_methods = [ :perform, :service_active?, :success_result, :error_result ]

    required_methods.each do |method|
      unless instance.respond_to?(method, true)
        result[:errors] << "Missing required method: #{method}"
        result[:compliant] = false
      end
    end

    # Check for audit_service_operation (warning if missing)
    unless instance.respond_to?(:audit_service_operation, true)
      result[:warnings] << "Should implement audit_service_operation for proper audit tracking"
    end
  end

  def check_service_configuration(result, instance)
    return unless instance.respond_to?(:service_name) && instance.service_name.present?

    config = ServiceConfiguration.find_by(service_name: instance.service_name)
    unless config
      result[:warnings] << "No ServiceConfiguration record found for '#{instance.service_name}'"
    end
  end

  def check_inheritance(result, service_class)
    unless service_class < ApplicationService
      result[:errors] << "Must inherit from ApplicationService"
      result[:compliant] = false
    end
  end

  def print_service_result(result)
    service_name = result[:service_class].name
    status = result[:compliant] ? "✅ PASS" : "❌ FAIL"

    puts "#{status} #{service_name}"

    if result[:service_name]
      puts "    Service Name: #{result[:service_name]}"
    end

    result[:errors].each do |error|
      puts "    ❌ Error: #{error}"
    end

    result[:warnings].each do |warning|
      puts "    ⚠️  Warning: #{warning}"
    end

    puts unless result[:errors].empty? && result[:warnings].empty?
  end

  def print_summary(results)
    total = results.count
    compliant = results.count { |r| r[:compliant] }
    non_compliant = total - compliant

    puts "=" * 60
    puts "📊 SCT Compliance Summary"
    puts "   Total Services: #{total}"
    puts "   ✅ Compliant: #{compliant}"
    puts "   ❌ Non-Compliant: #{non_compliant}"

    if non_compliant > 0
      puts "\n🚨 Action Required: #{non_compliant} service(s) need SCT compliance fixes"
      puts "   Run 'rake sct:generate_configs' to create missing ServiceConfiguration records"
    else
      puts "\n🎉 All services are SCT compliant!"
    end
  end
end
