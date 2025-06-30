# ViewComponent configuration
# Ensure ViewComponent is properly loaded before configuring
if defined?(ViewComponent)
  Rails.application.config.after_initialize do
    ViewComponent::Base.config.view_component_path = Rails.root.join("app/components").to_s
    ViewComponent::Base.config.test_framework = :rspec
    
    # Only configure preview-related settings in development
    if Rails.env.development?
      ViewComponent::Base.config.preview_route = "/rails/view_components"
      ViewComponent::Base.config.preview_paths << Rails.root.join("spec/components/previews").to_s
      ViewComponent::Base.config.generate.preview = true
      ViewComponent::Base.config.generate.sidecar = true
      ViewComponent::Base.config.generate.stimulus = true
    end
  end

  # Only enable preview routes in development
  if Rails.env.development?
    Rails.application.routes.prepend do
      mount ViewComponent::Engine, at: "/rails/view_components"
    end
  end
end
