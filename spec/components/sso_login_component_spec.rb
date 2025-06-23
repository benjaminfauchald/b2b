require 'rails_helper'

RSpec.describe SsoLoginComponent, type: :component do
  describe "rendering" do
    it "renders Google login button" do
      render_inline(described_class.new)

      expect(page).to have_text("Continue with Google")
      expect(page).to have_css("a[href*='/users/auth/google_oauth2']")
      expect(page).to have_css(".google-icon")
    end

    it "renders GitHub login button" do
      render_inline(described_class.new)

      expect(page).to have_text("Continue with GitHub")
      expect(page).to have_css("a[href*='/users/auth/github']")
      expect(page).to have_css(".github-icon")
    end

    it "includes proper Flowbite styling" do
      render_inline(described_class.new)

      expect(page).to have_css(".space-y-4")
      expect(page).to have_css(".focus\\:ring-4")
      expect(page).to have_css(".transition-all")
    end

    context "with custom options" do
      it "applies custom CSS classes" do
        render_inline(described_class.new(class: "custom-class"))
        expect(page).to have_css(".custom-class")
      end

      it "shows only specific providers when configured" do
        render_inline(described_class.new(providers: [ :google_oauth2 ]))

        expect(page).to have_text("Continue with Google")
        expect(page).not_to have_text("Continue with GitHub")
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
