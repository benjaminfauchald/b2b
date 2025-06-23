require 'rails_helper'

RSpec.describe OauthButtonComponent, type: :component do
  let(:google_config) do
    {
      provider: :google_oauth2,
      name: "Google",
      icon: "google",
      color: "bg-red-600 hover:bg-red-700"
    }
  end

  describe "rendering" do
    it "renders OAuth button with correct styling" do
      render_inline(described_class.new(**google_config))

      expect(page).to have_text("Continue with Google")
      expect(page).to have_css(".bg-red-600")
      expect(page).to have_css("svg.google-icon")
    end

    it "generates correct OAuth URL" do
      render_inline(described_class.new(**google_config))

      expect(page).to have_css("a[href='/users/auth/google_oauth2']")
    end

    it "includes loading state handling" do
      render_inline(described_class.new(**google_config))

      expect(page).to have_css("[data-loading-text]")
      expect(page).to have_css(".loading-spinner")
    end
  end

  describe "icons" do
    it "renders Google icon correctly" do
      render_inline(described_class.new(provider: :google_oauth2, name: "Google", icon: "google"))
      expect(page).to have_css("svg.google-icon")
    end

    it "renders GitHub icon correctly" do
      render_inline(described_class.new(provider: :github, name: "GitHub", icon: "github"))
      expect(page).to have_css("svg.github-icon")
    end
  end
end
