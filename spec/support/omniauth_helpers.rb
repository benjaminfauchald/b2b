module OmniauthHelpers
  def mock_google_oauth(email: 'user@gmail.com', name: 'Test User', uid: '123456789')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      'provider' => 'google_oauth2',
      'uid' => uid,
      'info' => {
        'email' => email,
        'name' => name,
        'image' => 'https://example.com/avatar.jpg'
      },
      'credentials' => {
        'token' => 'oauth_token',
        'refresh_token' => 'refresh_token'
      }
    })
  end

  def mock_github_oauth(email: 'user@users.noreply.github.com', name: 'Test User', uid: '987654321')
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      'provider' => 'github',
      'uid' => uid,
      'info' => {
        'email' => email,
        'name' => name,
        'image' => 'https://avatars.githubusercontent.com/u/123'
      },
      'credentials' => {
        'token' => 'github_token'
      }
    })
  end

  def mock_oauth_failure(provider = :google_oauth2)
    OmniAuth.config.mock_auth[provider] = :invalid_credentials
  end

  def clear_oauth_mocks
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:github] = nil
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :feature
  config.include OmniauthHelpers, type: :system
  config.include OmniauthHelpers, type: :controller
  config.include OmniauthHelpers, type: :request

  config.before(:each) do
    OmniAuth.config.test_mode = true
  end

  config.after(:each) do
    clear_oauth_mocks if respond_to?(:clear_oauth_mocks)
  end
end
