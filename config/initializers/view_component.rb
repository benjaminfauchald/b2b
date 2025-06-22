# ViewComponent configuration
# Use the new API with ViewComponent::Base.config
ViewComponent::Base.config.preview_controller = "ComponentPreviewController"
ViewComponent::Base.config.preview_route = "/rails/view_components"
ViewComponent::Base.config.preview_paths << Rails.root.join("spec/components/previews")
ViewComponent::Base.config.view_component_path = "app/components"
ViewComponent::Base.config.generate.preview = true
ViewComponent::Base.config.generate.sidecar = true
ViewComponent::Base.config.generate.stimulus = true
ViewComponent::Base.config.test_framework = :rspec

# Only enable previews in development
if Rails.env.development?
  # Add preview routes
  Rails.application.routes.prepend do
    mount ViewComponent::Engine, at: "/rails/view_components"
  end
end
