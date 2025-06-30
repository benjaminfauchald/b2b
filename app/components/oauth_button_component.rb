class OauthButtonComponent < ViewComponent::Base
  def initialize(provider:, name:, icon:, color: nil, button_text: nil, **options)
    @provider = provider
    @name = name
    @icon = icon
    @color = color || default_color
    @button_text = button_text || "Continue with #{name}"
    @options = options
  end

  private

  attr_reader :provider, :name, :icon, :color, :button_text, :options

  def oauth_url
    "/users/auth/#{provider}"
  end

  def button_classes
    base_classes = [
      "w-full",
      "flex",
      "items-center",
      "justify-center",
      "px-5",
      "py-2.5",
      "text-sm",
      "font-medium",
      "text-white",
      "rounded-lg",
      "transition-all",
      "duration-200",
      "focus:ring-4",
      "focus:outline-none",
      "disabled:opacity-50",
      "disabled:cursor-not-allowed"
    ]

    color_classes = color.split(" ")

    (base_classes + color_classes + [ options[:class] ]).compact.join(" ")
  end

  def loading_text
    "Connecting to #{name}..."
  end

  def default_color
    case provider.to_s
    when "google_oauth2", "google"
      "bg-red-600 hover:bg-red-700 focus:ring-red-300 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900"
    when "github"
      "bg-gray-800 hover:bg-gray-900 focus:ring-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 dark:focus:ring-gray-600"
    else
      "bg-blue-700 hover:bg-blue-800 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
    end
  end

  def icon_svg
    case icon.to_s
    when "google"
      google_icon_svg
    when "github"
      github_icon_svg
    else
      default_icon_svg
    end
  end

  def google_icon_svg
    content_tag :svg, class: "w-5 h-5 mr-3 google-icon", viewBox: "0 0 24 24", fill: "currentColor" do
      content_tag(:path, "", d: "M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z") +
      content_tag(:path, "", d: "M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z") +
      content_tag(:path, "", d: "M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z") +
      content_tag(:path, "", d: "M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z")
    end
  end

  def github_icon_svg
    content_tag :svg, class: "w-5 h-5 mr-3 github-icon", viewBox: "0 0 24 24", fill: "currentColor" do
      content_tag :path, "", d: "M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
    end
  end

  def default_icon_svg
    content_tag :svg, class: "w-5 h-5 mr-3", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
      content_tag :path, "", stroke_linecap: "round", stroke_linejoin: "round", stroke_width: "2", d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
    end
  end
end
