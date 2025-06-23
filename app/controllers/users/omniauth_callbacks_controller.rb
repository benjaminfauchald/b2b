# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :google_oauth2

  def google_oauth2
    handle_oauth("Google")
  end

  def github
    handle_oauth("GitHub")
  end

  def failure
    error_msg = request.env["omniauth.error"]&.message || "Unknown authentication error"
    redirect_to new_user_session_path, alert: "Authentication failed: #{error_msg}"
  end

  private

  def handle_oauth(provider_name)
    auth = request.env["omniauth.auth"]

    if auth.present?
      @user = User.from_omniauth(auth)

      if @user.persisted?
        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: provider_name) if is_navigational_format?
      else
        session["devise.#{auth.provider}_data"] = auth.except("extra")
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
      end
    else
      redirect_to new_user_session_path, alert: "There was an error with #{provider_name} authentication."
    end
  end
end
