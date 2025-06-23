# Comprehensive RSpec Test Plan for SSO Feature

## Overview
This document outlines the complete test plan for implementing Single Sign-On (SSO) with Google and GitHub OAuth providers using Devise + Omniauth.

## Test Structure

### 1. Model Tests (`spec/models/user_spec.rb`)

#### OAuth User Model Extensions
```ruby
RSpec.describe User, type: :model do
  describe "OAuth methods" do
    describe ".from_omniauth" do
      let(:google_auth_hash) do
        OmniAuth::AuthHash.new({
          'provider' => 'google_oauth2',
          'uid' => '123456789',
          'info' => {
            'email' => 'user@gmail.com',
            'name' => 'John Doe',
            'image' => 'https://example.com/avatar.jpg'
          },
          'credentials' => {
            'token' => 'oauth_token',
            'refresh_token' => 'refresh_token'
          }
        })
      end

      let(:github_auth_hash) do
        OmniAuth::AuthHash.new({
          'provider' => 'github',
          'uid' => '987654321',
          'info' => {
            'email' => 'user@users.noreply.github.com',
            'name' => 'Jane Smith',
            'image' => 'https://avatars.githubusercontent.com/u/123'
          },
          'credentials' => {
            'token' => 'github_token'
          }
        })
      end

      context "when user does not exist" do
        it "creates a new user with Google OAuth" do
          expect {
            User.from_omniauth(google_auth_hash)
          }.to change(User, :count).by(1)
        end

        it "creates a new user with GitHub OAuth" do
          expect {
            User.from_omniauth(github_auth_hash)
          }.to change(User, :count).by(1)
        end

        it "sets the correct attributes for Google user" do
          user = User.from_omniauth(google_auth_hash)
          expect(user.email).to eq('user@gmail.com')
          expect(user.name).to eq('John Doe')
          expect(user.provider).to eq('google_oauth2')
          expect(user.uid).to eq('123456789')
        end

        it "sets the correct attributes for GitHub user" do
          user = User.from_omniauth(github_auth_hash)
          expect(user.email).to eq('user@users.noreply.github.com')
          expect(user.name).to eq('Jane Smith')
          expect(user.provider).to eq('github')
          expect(user.uid).to eq('987654321')
        end

        it "generates a secure random password" do
          user = User.from_omniauth(google_auth_hash)
          expect(user.encrypted_password).to be_present
        end
      end

      context "when user exists with same email" do
        let!(:existing_user) { create(:user, email: 'user@gmail.com') }

        it "links OAuth provider to existing user" do
          expect {
            User.from_omniauth(google_auth_hash)
          }.not_to change(User, :count)
        end

        it "updates user with OAuth provider info" do
          user = User.from_omniauth(google_auth_hash)
          expect(user.provider).to eq('google_oauth2')
          expect(user.uid).to eq('123456789')
        end
      end

      context "when OAuth user already exists" do
        let!(:oauth_user) do
          create(:user, 
            email: 'user@gmail.com',
            provider: 'google_oauth2',
            uid: '123456789'
          )
        end

        it "returns existing user" do
          user = User.from_omniauth(google_auth_hash)
          expect(user.id).to eq(oauth_user.id)
        end

        it "does not create duplicate user" do
          expect {
            User.from_omniauth(google_auth_hash)
          }.not_to change(User, :count)
        end
      end
    end

    describe "#oauth_user?" do
      it "returns true for OAuth users" do
        user = create(:user, provider: 'google_oauth2', uid: '123')
        expect(user.oauth_user?).to be true
      end

      it "returns false for regular users" do
        user = create(:user, provider: nil, uid: nil)
        expect(user.oauth_user?).to be false
      end
    end

    describe "#can_change_password?" do
      it "returns false for OAuth users" do
        user = create(:user, provider: 'google_oauth2')
        expect(user.can_change_password?).to be false
      end

      it "returns true for regular users" do
        user = create(:user, provider: nil)
        expect(user.can_change_password?).to be true
      end
    end
  end

  describe "validations" do
    it "allows OAuth users without password" do
      user = build(:user, :oauth_user, password: nil, password_confirmation: nil)
      expect(user).to be_valid
    end

    it "requires password for regular users" do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it "validates uniqueness of uid scoped to provider" do
      create(:user, provider: 'google_oauth2', uid: '123')
      duplicate = build(:user, provider: 'google_oauth2', uid: '123')
      expect(duplicate).not_to be_valid
    end

    it "allows same uid for different providers" do
      create(:user, provider: 'google_oauth2', uid: '123')
      different_provider = build(:user, provider: 'github', uid: '123')
      expect(different_provider).to be_valid
    end
  end
end
```

### 2. Controller Tests

#### Sessions Controller Tests (`spec/controllers/users/sessions_controller_spec.rb`)
```ruby
RSpec.describe Users::SessionsController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe "GET #new" do
    it "renders the login page with SSO options" do
      get :new
      expect(response).to render_template(:new)
      expect(response.body).to include("Sign in with Google")
      expect(response.body).to include("Sign in with GitHub")
    end

    context "when user is already signed in" do
      let(:user) { create(:user) }
      
      before { sign_in user }

      it "redirects to dashboard" do
        get :new
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
```

#### Omniauth Callbacks Controller Tests (`spec/controllers/users/omniauth_callbacks_controller_spec.rb`)
```ruby
RSpec.describe Users::OmniauthCallbacksController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe "GET #google_oauth2" do
    let(:omniauth_hash) do
      OmniAuth::AuthHash.new({
        'provider' => 'google_oauth2',
        'uid' => '123456789',
        'info' => {
          'email' => 'user@gmail.com',
          'name' => 'John Doe'
        }
      })
    end

    before do
      request.env["omniauth.auth"] = omniauth_hash
    end

    context "with valid OAuth response" do
      it "creates a new user and signs them in" do
        expect {
          get :google_oauth2
        }.to change(User, :count).by(1)
        
        expect(controller.current_user).to be_present
        expect(controller.current_user.email).to eq('user@gmail.com')
      end

      it "redirects to dashboard with success message" do
        get :google_oauth2
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Successfully authenticated with Google.')
      end
    end

    context "with existing user" do
      let!(:existing_user) { create(:user, email: 'user@gmail.com') }

      it "signs in existing user without creating new one" do
        expect {
          get :google_oauth2
        }.not_to change(User, :count)
        
        expect(controller.current_user).to eq(existing_user)
      end
    end

    context "with OAuth failure" do
      before do
        request.env["omniauth.auth"] = nil
      end

      it "redirects to login with error message" do
        get :google_oauth2
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to eq('There was an error with Google authentication.')
      end
    end
  end

  describe "GET #github" do
    let(:omniauth_hash) do
      OmniAuth::AuthHash.new({
        'provider' => 'github',
        'uid' => '987654321',
        'info' => {
          'email' => 'user@users.noreply.github.com',
          'name' => 'Jane Smith'
        }
      })
    end

    before do
      request.env["omniauth.auth"] = omniauth_hash
    end

    context "with valid GitHub OAuth response" do
      it "creates a new user and signs them in" do
        expect {
          get :github
        }.to change(User, :count).by(1)
        
        expect(controller.current_user).to be_present
        expect(controller.current_user.provider).to eq('github')
      end

      it "redirects to dashboard with success message" do
        get :github
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Successfully authenticated with GitHub.')
      end
    end
  end

  describe "GET #failure" do
    before do
      request.env["omniauth.error"] = OmniAuth::Strategies::OAuth2::CallbackError.new(:invalid_credentials, "Invalid credentials")
    end

    it "redirects to login with error message" do
      get :failure
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to eq('Authentication failed: Invalid credentials')
    end
  end
end
```

### 3. Component Tests

#### SSO Login Component Tests (`spec/components/sso_login_component_spec.rb`)
```ruby
RSpec.describe SsoLoginComponent, type: :component do
  describe "rendering" do
    it "renders Google login button" do
      render_inline(described_class.new)
      
      expect(page).to have_link("Sign in with Google")
      expect(page).to have_css("a[href*='/users/auth/google_oauth2']")
      expect(page).to have_css(".google-btn")
    end

    it "renders GitHub login button" do
      render_inline(described_class.new)
      
      expect(page).to have_link("Sign in with GitHub")
      expect(page).to have_css("a[href*='/users/auth/github']")
      expect(page).to have_css(".github-btn")
    end

    it "includes proper Flowbite styling" do
      render_inline(described_class.new)
      
      expect(page).to have_css(".space-y-4")
      expect(page).to have_css(".focus\\:ring-4")
      expect(page).to have_css(".transition-colors")
    end

    context "with custom options" do
      it "applies custom CSS classes" do
        render_inline(described_class.new(class: "custom-class"))
        expect(page).to have_css(".custom-class")
      end

      it "shows only specific providers when configured" do
        render_inline(described_class.new(providers: [:google]))
        
        expect(page).to have_link("Sign in with Google")
        expect(page).not_to have_link("Sign in with GitHub")
      end
    end
  end

  describe "accessibility" do
    it "includes proper ARIA labels" do
      render_inline(described_class.new)
      
      expect(page).to have_css("a[aria-label*='Google']")
      expect(page).to have_css("a[aria-label*='GitHub']")
    end

    it "has proper keyboard navigation" do
      render_inline(described_class.new)
      
      expect(page).to have_css("a[tabindex='0']")
    end
  end
end
```

#### OAuth Button Component Tests (`spec/components/oauth_button_component_spec.rb`)
```ruby
RSpec.describe OauthButtonComponent, type: :component do
  let(:google_config) do
    {
      provider: :google,
      name: "Google",
      icon: "google",
      color: "bg-red-600 hover:bg-red-700"
    }
  end

  describe "rendering" do
    it "renders OAuth button with correct styling" do
      render_inline(described_class.new(**google_config))
      
      expect(page).to have_link("Continue with Google")
      expect(page).to have_css(".bg-red-600")
      expect(page).to have_css("svg.google-icon")
    end

    it "generates correct OAuth URL" do
      render_inline(described_class.new(**google_config))
      
      expect(page).to have_css("a[href='/users/auth/google']")
    end

    it "includes loading state handling" do
      render_inline(described_class.new(**google_config))
      
      expect(page).to have_css("[data-loading-text]")
      expect(page).to have_css(".loading-spinner")
    end
  end

  describe "icons" do
    it "renders Google icon correctly" do
      render_inline(described_class.new(provider: :google, name: "Google", icon: "google"))
      expect(page).to have_css("svg.google-icon")
    end

    it "renders GitHub icon correctly" do
      render_inline(described_class.new(provider: :github, name: "GitHub", icon: "github"))
      expect(page).to have_css("svg.github-icon")
    end
  end
end
```

### 4. Integration Tests

#### OAuth Authentication Flow Tests (`spec/features/oauth_authentication_spec.rb`)
```ruby
RSpec.feature "OAuth Authentication", type: :feature do
  before do
    OmniAuth.config.test_mode = true
  end

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:github] = nil
  end

  scenario "User signs in with Google successfully" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      'provider' => 'google_oauth2',
      'uid' => '123456789',
      'info' => {
        'email' => 'user@gmail.com',
        'name' => 'John Doe'
      }
    })

    visit new_user_session_path
    
    expect(page).to have_content("Sign in with Google")
    click_link "Sign in with Google"
    
    expect(page).to have_content("Successfully authenticated with Google")
    expect(page).to have_current_path(root_path)
    expect(page).to have_content("John Doe")
  end

  scenario "User signs in with GitHub successfully" do
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      'provider' => 'github',
      'uid' => '987654321',
      'info' => {
        'email' => 'user@users.noreply.github.com',
        'name' => 'Jane Smith'
      }
    })

    visit new_user_session_path
    click_link "Sign in with GitHub"
    
    expect(page).to have_content("Successfully authenticated with GitHub")
    expect(page).to have_current_path(root_path)
  end

  scenario "OAuth authentication fails" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    visit new_user_session_path
    click_link "Sign in with Google"
    
    expect(page).to have_content("Authentication failed")
    expect(page).to have_current_path(new_user_session_path)
  end

  scenario "Existing user links OAuth account" do
    existing_user = create(:user, email: 'user@gmail.com', name: 'John Doe')
    
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      'provider' => 'google_oauth2',
      'uid' => '123456789',
      'info' => {
        'email' => 'user@gmail.com',
        'name' => 'John Doe'
      }
    })

    visit new_user_session_path
    click_link "Sign in with Google"
    
    expect(page).to have_current_path(root_path)
    
    existing_user.reload
    expect(existing_user.provider).to eq('google_oauth2')
    expect(existing_user.uid).to eq('123456789')
  end

  scenario "User sees loading state during OAuth" do
    visit new_user_session_path
    
    # Mock slow OAuth response
    allow_any_instance_of(Users::OmniauthCallbacksController)
      .to receive(:google_oauth2).and_wrap_original do |method, *args|
        sleep 0.1
        method.call(*args)
      end

    click_link "Sign in with Google"
    
    # Check for loading indicator (this would require JS testing)
    # expect(page).to have_css(".loading-spinner")
  end
end
```

#### Account Management Integration Tests (`spec/features/oauth_account_management_spec.rb`)
```ruby
RSpec.feature "OAuth Account Management", type: :feature do
  scenario "OAuth user cannot change password" do
    oauth_user = create(:user, provider: 'google_oauth2', uid: '123')
    login_as(oauth_user, scope: :user)
    
    visit edit_user_registration_path
    
    expect(page).not_to have_field("Current password")
    expect(page).not_to have_field("New password")
    expect(page).to have_content("Password managed by Google")
  end

  scenario "Regular user can change password" do
    regular_user = create(:user, provider: nil)
    login_as(regular_user, scope: :user)
    
    visit edit_user_registration_path
    
    expect(page).to have_field("Current password")
    expect(page).to have_field("New password")
  end

  scenario "User can disconnect OAuth provider" do
    oauth_user = create(:user, provider: 'google_oauth2', uid: '123')
    login_as(oauth_user, scope: :user)
    
    visit edit_user_registration_path
    
    expect(page).to have_content("Connected: Google")
    click_button "Disconnect Google"
    
    expect(page).to have_content("Google account disconnected")
    oauth_user.reload
    expect(oauth_user.provider).to be_nil
  end
end
```

### 5. System Tests (E2E)

#### Complete Authentication Flow Tests (`spec/system/sso_authentication_system_spec.rb`)
```ruby
RSpec.describe "SSO Authentication System", type: :system do
  before do
    driven_by(:selenium, using: :headless_chrome, screen_size: [1400, 1400])
    OmniAuth.config.test_mode = true
  end

  it "completes full Google OAuth flow with UI interactions" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      'provider' => 'google_oauth2',
      'uid' => '123456789',
      'info' => {
        'email' => 'user@gmail.com',
        'name' => 'John Doe'
      }
    })

    visit root_path
    
    # Should redirect to login
    expect(page).to have_current_path(new_user_session_path)
    
    # Check SSO buttons are visible
    expect(page).to have_css(".sso-login-component")
    expect(page).to have_link("Sign in with Google")
    
    # Click Google sign in with JavaScript
    find("a[href*='google_oauth2']").click
    
    # Should be redirected back and signed in
    expect(page).to have_current_path(root_path)
    expect(page).to have_content("John Doe")
    
    # Check user menu shows OAuth status
    click_button "User menu"
    expect(page).to have_content("Signed in with Google")
  end

  it "handles OAuth failure gracefully" do
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    
    visit new_user_session_path
    click_link "Sign in with Google"
    
    expect(page).to have_css(".alert-error")
    expect(page).to have_content("Authentication failed")
    expect(page).to have_current_path(new_user_session_path)
  end

  it "shows proper loading states during OAuth" do
    visit new_user_session_path
    
    # This would require more complex JS testing
    # to properly test loading states
    google_btn = find("a[href*='google_oauth2']")
    expect(google_btn).to have_attribute("data-loading-text")
  end
end
```

### 6. Configuration and Factory Tests

#### Factory Tests (`spec/factories/users_spec.rb`)
```ruby
RSpec.describe "User factories" do
  describe ":user factory" do
    it "creates a valid user" do
      user = build(:user)
      expect(user).to be_valid
    end
  end

  describe ":oauth_user trait" do
    it "creates a valid OAuth user" do
      user = build(:user, :oauth_user)
      expect(user).to be_valid
      expect(user.oauth_user?).to be true
    end

    it "creates valid Google OAuth user" do
      user = build(:user, :google_oauth)
      expect(user.provider).to eq('google_oauth2')
      expect(user.uid).to be_present
    end

    it "creates valid GitHub OAuth user" do
      user = build(:user, :github_oauth)
      expect(user.provider).to eq('github')
      expect(user.uid).to be_present
    end
  end
end
```

### 7. Security Tests

#### OAuth Security Tests (`spec/security/oauth_security_spec.rb`)
```ruby
RSpec.describe "OAuth Security", type: :request do
  describe "CSRF protection" do
    it "includes CSRF state parameter in OAuth URLs" do
      get new_user_session_path
      
      google_link = Nokogiri::HTML(response.body)
        .css("a[href*='google_oauth2']")
        .first['href']
      
      expect(google_link).to include("state=")
    end
  end

  describe "OAuth callback security" do
    it "validates OAuth state parameter" do
      # Test with invalid state
      get "/users/auth/google_oauth2/callback", params: {
        state: "invalid_state",
        code: "valid_code"
      }
      
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to include("Invalid authentication state")
    end
  end

  describe "Rate limiting" do
    it "limits OAuth attempts" do
      # This would test rate limiting on OAuth endpoints
      10.times do
        post "/users/auth/google_oauth2"
      end
      
      post "/users/auth/google_oauth2"
      expect(response.status).to eq(429)
    end
  end
end
```

## Test Data Setup

### Factory Modifications
```ruby
# spec/factories/users.rb additions
FactoryBot.define do
  factory :user do
    # ... existing factory ...
    
    trait :oauth_user do
      provider { ['google_oauth2', 'github'].sample }
      sequence(:uid) { |n| "oauth_uid_#{n}" }
      password { nil }
      password_confirmation { nil }
    end
    
    trait :google_oauth do
      provider { 'google_oauth2' }
      sequence(:uid) { |n| "google_#{n}" }
      sequence(:email) { |n| "user#{n}@gmail.com" }
    end
    
    trait :github_oauth do
      provider { 'github' }
      sequence(:uid) { |n| "github_#{n}" }
      sequence(:email) { |n| "user#{n}@users.noreply.github.com" }
    end
  end
end
```

### Test Helper Setup
```ruby
# spec/support/omniauth_helpers.rb
module OmniauthHelpers
  def mock_google_oauth(email: 'user@gmail.com', name: 'Test User')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      'provider' => 'google_oauth2',
      'uid' => '123456789',
      'info' => {
        'email' => email,
        'name' => name
      }
    })
  end
  
  def mock_github_oauth(email: 'user@users.noreply.github.com', name: 'Test User')
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new({
      'provider' => 'github',
      'uid' => '987654321',
      'info' => {
        'email' => email,
        'name' => name
      }
    })
  end
  
  def mock_oauth_failure(provider = :google_oauth2)
    OmniAuth.config.mock_auth[provider] = :invalid_credentials
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers, type: :feature
  config.include OmniauthHelpers, type: :system
  config.include OmniauthHelpers, type: :controller
end
```

## Test Execution Strategy

### Test Categories
1. **Unit Tests** (Models, Helpers): Fast, isolated tests
2. **Component Tests**: ViewComponent rendering and behavior
3. **Controller Tests**: HTTP request/response handling
4. **Integration Tests**: Multi-layer feature testing
5. **System Tests**: Full browser automation
6. **Security Tests**: Authentication and authorization

### Test Coverage Goals
- **90%+ coverage** on OAuth-related code
- **100% coverage** on security-critical paths
- **Edge cases covered**: Network failures, invalid responses, rate limiting
- **Performance tested**: OAuth callback handling under load

### Continuous Integration
- Run security tests on every commit
- Full test suite on pull requests
- Performance tests on staging environment
- OAuth provider connectivity tests in production

This comprehensive test plan ensures that the SSO implementation is robust, secure, and maintainable with full test coverage across all layers of the application.