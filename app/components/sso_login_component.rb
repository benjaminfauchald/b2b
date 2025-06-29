class SsoLoginComponent < ViewComponent::Base
  def initialize(providers: [ :google_oauth2, :github ], action: "Sign in", **options)
    @providers = Array(providers)
    @action = action
    @options = options
  end

  private

  attr_reader :providers, :action, :options

  def container_classes
    base_classes = [
      "w-full"
    ]

    [ base_classes, options[:class] ].flatten.compact.join(" ")
  end

  def provider_configs
    {
      google_oauth2: {
        provider: :google_oauth2,
        name: "Google",
        icon: "google",
        color: "bg-red-600 hover:bg-red-700 focus:ring-red-300"
      },
      google: {
        provider: :google_oauth2,
        name: "Google",
        icon: "google",
        color: "bg-red-600 hover:bg-red-700 focus:ring-red-300"
      },
      github: {
        provider: :github,
        name: "GitHub",
        icon: "github",
        color: "bg-gray-800 hover:bg-gray-900 focus:ring-gray-300"
      }
    }
  end

  def enabled_providers
    providers.map do |provider|
      config = provider_configs[provider.to_sym]
      next unless config

      config.merge(button_text: "#{action} with #{config[:name]}")
    end.compact
  end

  def divider_text
    "Or continue with"
  end
end
