class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Global authentication - can be overridden in specific controllers
  before_action :authenticate_user!, unless: :public_action?

  def version
    version_info = {
      version: git_version,
      commit: git_commit,
      deployed_at: deployment_time,
      environment: Rails.env
    }

    render json: version_info
  end

  private

  def git_version
    `git describe --tags --always 2>/dev/null`.strip.presence || "unknown"
  end
  helper_method :git_version

  def git_commit
    `git rev-parse HEAD 2>/dev/null`.strip.presence || "unknown"
  end

  def deployment_time
    # Check when the app was last restarted (tmp/restart.txt timestamp)
    restart_file = Rails.root.join("tmp", "restart.txt")
    if File.exist?(restart_file)
      File.mtime(restart_file).iso8601
    else
      "unknown"
    end
  end

  def public_action?
    action_name == "version" # Allow version endpoint without auth
  end
end
