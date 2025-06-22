class ComponentPreviewController < ViewComponent::Preview::BaseController
  # Custom controller for component previews
  # This allows you to add authentication, custom layouts, etc.
  
  layout "component_preview"
  
  private
  
  def default_preview_layout
    "component_preview"
  end
end