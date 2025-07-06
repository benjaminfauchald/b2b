# frozen_string_literal: true

# Rails 8 CI Compatibility - Must run very early
# Patch the Rails middleware configuration to handle frozen arrays
if ENV["CI"] || ENV["RAILS_ENV"] == "test"
  require 'rails/configuration' if defined?(Rails)
  
  # Patch the MiddlewareStackProxy to handle frozen arrays
  if defined?(Rails::Configuration::MiddlewareStackProxy)
    class Rails::Configuration::MiddlewareStackProxy
      alias_method :original_use, :use if method_defined?(:use)
      
      def use(*args, &block)
        # If we're in CI and the underlying array might be frozen,
        # we need to ensure it's not frozen before adding middleware
        if @operations.frozen?
          @operations = @operations.dup
        end
        original_use(*args, &block)
      rescue FrozenError => e
        Rails.logger.warn "Caught FrozenError in middleware.use: #{e.message}"
        # Create a new operations array
        @operations = (@operations || []).dup
        original_use(*args, &block)
      end

      def unshift(*args, &block)
        if @operations.frozen?
          @operations = @operations.dup
        end
        super
      rescue FrozenError => e
        Rails.logger.warn "Caught FrozenError in middleware.unshift: #{e.message}"
        @operations = (@operations || []).dup
        super
      end

      def insert(*args, &block)
        if @operations.frozen?
          @operations = @operations.dup
        end
        super
      rescue FrozenError => e
        Rails.logger.warn "Caught FrozenError in middleware.insert: #{e.message}"
        @operations = (@operations || []).dup
        super
      end

      def insert_before(*args, &block)
        if @operations.frozen?
          @operations = @operations.dup
        end
        super
      rescue FrozenError => e
        Rails.logger.warn "Caught FrozenError in middleware.insert_before: #{e.message}"
        @operations = (@operations || []).dup
        super
      end

      def insert_after(*args, &block)
        if @operations.frozen?
          @operations = @operations.dup
        end
        super
      rescue FrozenError => e
        Rails.logger.warn "Caught FrozenError in middleware.insert_after: #{e.message}"
        @operations = (@operations || []).dup
        super
      end
    end
  end

  # Also patch ActionDispatch::MiddlewareStack directly
  require 'action_dispatch' if defined?(Rails)
  
  if defined?(ActionDispatch::MiddlewareStack)
    class ActionDispatch::MiddlewareStack
      alias_method :original_build_middleware, :build if method_defined?(:build)
      
      def build(app = nil, &block)
        # Ensure middlewares array is not frozen
        if @middlewares&.frozen?
          @middlewares = @middlewares.dup
        end
        original_build_middleware(app, &block)
      end

      # Override the array accessor to prevent frozen errors
      def middlewares
        if @middlewares&.frozen?
          @middlewares = @middlewares.dup
        end
        @middlewares
      end
    end
  end
end