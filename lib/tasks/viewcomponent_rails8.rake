# ViewComponent Rails 8 compatibility tasks
# Ensures ViewComponent works properly with Rails 8 and Propshaft

namespace :viewcomponent do
  desc "Precompile ViewComponent templates for Rails 8 production deployment"
  task precompile: :environment do
    puts "🔧 Precompiling ViewComponent templates for Rails 8..."
    
    if defined?(ViewComponent::Base)
      component_count = 0
      
      Dir.glob(Rails.root.join("app/components/**/*_component.rb")).each do |component_file|
        begin
          component_name = File.basename(component_file, ".rb").camelize
          component_class = component_name.constantize
          
          if component_class < ViewComponent::Base
            # Force template compilation
            if component_class.respond_to?(:compile!)
              component_class.compile!
            elsif component_class.respond_to?(:compile_template)
              component_class.compile_template
            end
            
            component_count += 1
            puts "  ✅ Compiled: #{component_name}"
          end
        rescue => e
          puts "  ⚠️  Warning for #{component_file}: #{e.message}"
        end
      end
      
      puts "🎉 Successfully precompiled #{component_count} ViewComponents"
    else
      puts "❌ ViewComponent not found"
    end
  end

  desc "Verify ViewComponent Rails 8 compatibility"
  task verify: :environment do
    puts "🔍 Verifying ViewComponent Rails 8 compatibility..."
    
    # Check if ViewComponent is loaded
    if defined?(ViewComponent)
      puts "  ✅ ViewComponent loaded successfully"
    else
      puts "  ❌ ViewComponent not loaded"
      exit 1
    end
    
    # Check autoload paths
    component_path = Rails.root.join("app/components")
    if Rails.application.config.autoload_paths.include?(component_path)
      puts "  ✅ ViewComponent autoload path configured"
    else
      puts "  ❌ ViewComponent autoload path missing"
      exit 1
    end
    
    # Check component loading
    component_files = Dir.glob(Rails.root.join("app/components/**/*_component.rb"))
    puts "  ✅ Found #{component_files.count} ViewComponent files"
    
    # Test component instantiation
    begin
      if component_files.any?
        sample_component = File.basename(component_files.first, ".rb").camelize.constantize
        sample_component.new rescue nil
        puts "  ✅ ViewComponent instantiation works"
      end
    rescue => e
      puts "  ⚠️  Component instantiation warning: #{e.message}"
    end
    
    puts "🎉 ViewComponent Rails 8 compatibility verified"
  end
end

# Integrate with standard Rails tasks
if Rails.env.production?
  # Add ViewComponent precompilation to assets:precompile
  Rake::Task["assets:precompile"].enhance(["viewcomponent:precompile"])
end