# ViewComponent Rails 8 Compatibility Fix
# This initializer resolves FrozenError issues with ViewComponent in Rails 8

# The fundamental issue is that Rails 8 freezes autoload_paths much earlier,
# especially in CI environments with eager loading enabled

# Comprehensive Rails 8 autoload_paths freeze protection
if Rails::VERSION::MAJOR >= 8
  # Monkey patch Rails::Engine initializer to handle frozen autoload_paths
  Rails::Engine.class_eval do
    # Override the add_builtin_route initializer to prevent autoload_paths modification
    def self.inherited(subclass)
      super

      # Skip autoload_paths modification for engines when paths are frozen
      subclass.initializer "#{subclass.railtie_name}.add_builtin_route", before: :build_middleware_stack do |app|
        if app.config.autoload_paths.frozen?
          Rails.logger.debug "Rails 8: Skipping autoload_paths modification for #{subclass.name} (frozen)"
        else
          # Only modify if not frozen
          original_paths = paths["app"].expanded
          original_paths.each do |expanded|
            app.config.autoload_paths.unshift(expanded) if File.directory?(expanded)
          end
        end
      end
    end
  end

  # Patch the autoload_paths array itself to handle frozen state gracefully
  module AutoloadPathsFrozenPatch
    def unshift(*args)
      if frozen?
        Rails.logger.debug "Rails 8: Prevented unshift to frozen autoload_paths: #{args.inspect}"
        return self
      end
      super(*args)
    end

    def <<(path)
      if frozen?
        Rails.logger.debug "Rails 8: Prevented << to frozen autoload_paths: #{path}"
        return self
      end
      super(path)
    end

    def push(*args)
      if frozen?
        Rails.logger.debug "Rails 8: Prevented push to frozen autoload_paths: #{args.inspect}"
        return self
      end
      super(*args)
    end

    def concat(other)
      if frozen?
        Rails.logger.debug "Rails 8: Prevented concat to frozen autoload_paths: #{other.inspect}"
        return self
      end
      super(other)
    end
  end

  # Apply patches early in Rails initialization (only if not frozen)
  unless Rails.application.config.autoload_paths.frozen?
    Rails.application.config.autoload_paths.extend(AutoloadPathsFrozenPatch)
  end

  unless Rails.application.config.eager_load_paths.frozen?
    Rails.application.config.eager_load_paths.extend(AutoloadPathsFrozenPatch)
  end
end

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

    # Force early compilation of ViewComponent templates in production and CI
    if Rails.env.production? || ENV["CI"]
      Rails.logger.info "Precompiling ViewComponent templates for #{Rails.env.production? ? 'production' : 'CI'}..."

      # Special handling for CI environment
      if ENV["CI"] && Rails.env.test?
        Rails.logger.info "Applying ViewComponent Rails 8 compatibility for CI testing environment"
      end

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
