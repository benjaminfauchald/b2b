OmniAuth.config.logger = Rails.logger

# Handle CSRF protection
OmniAuth.config.allowed_request_methods = [ :post, :get ]

# Fix for ngrok
OmniAuth.config.request_validation_phase = nil
OmniAuth.config.silence_get_warning = true
