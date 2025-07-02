# ViewComponent Rails 8 Compatibility Fix
# This initializer resolves FrozenError issues with ViewComponent in Rails 8

# The fundamental issue is that Rails 8 freezes autoload_paths much earlier
# We need to configure paths before ViewComponent's engine initialization

if defined?(ViewComponent)
  # Override ViewComponent::Engine to prevent autoload_paths modification
  module ViewComponentRails8Patch
    def set_autoload_paths
      # Skip the problematic autoload_paths modification in Rails 8
      # The paths are already configured in application.rb
      Rails.logger.debug "ViewComponent: Skipping autoload_paths modification for Rails 8 compatibility"
    end
  end
  
  # Patch ViewComponent::Engine to prevent FrozenError
  ViewComponent::Engine.prepend(ViewComponentRails8Patch)
end

# Ensure ViewComponent compilation works properly in all environments
Rails.application.config.after_initialize do
  if defined?(ViewComponent::Base)
    # Log ViewComponent initialization
    Rails.logger.info "ViewComponent initialized with Rails 8 compatibility patch"
    
    # Force early compilation of ViewComponent templates in production
    if Rails.env.production?
      Rails.logger.info "Precompiling ViewComponent templates for production..."
      
      # Precompile all ViewComponent templates to prevent runtime compilation issues
      Dir.glob(Rails.root.join("app/components/**/*_component.rb")).each do |component_file|
        begin
          component_name = File.basename(component_file, ".rb").camelize
          component_class = component_name.constantize
          
          # Trigger template compilation if the component has templates
          if component_class < ViewComponent::Base && component_class.respond_to?(:compile_template)
            component_class.compile_template
            Rails.logger.debug "Compiled ViewComponent: #{component_name}"
          end
        rescue => e
          Rails.logger.warn "ViewComponent compilation warning for #{component_file}: #{e.message}"
        end
      end
      
      Rails.logger.info "ViewComponent template precompilation completed"
    end
  end
end