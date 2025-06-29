require "rails_helper"

RSpec.describe CountrySelectorComponent, type: :component do
  let(:available_countries) { [ "NO", "SE", "DK" ] }
  let(:selected_country) { "NO" }
  let(:component) { described_class.new(available_countries: available_countries, selected_country: selected_country) }

  context "with multiple countries" do
    it "renders a select dropdown" do
      render_inline(component)

      expect(page).to have_css("select[name='country']")
      expect(page).to have_css("option", count: 3)
    end

    it "shows country names with flags" do
      render_inline(component)

      expect(page).to have_content("🇳🇴 Norway")
      expect(page).to have_content("🇸🇪 Sweden")
      expect(page).to have_content("🇩🇰 Denmark")
    end

    it "selects the current country" do
      render_inline(component)

      expect(page).to have_css("option[value='NO'][selected]")
    end

    it "submits form on change" do
      render_inline(component)

      form = page.find("form")
      expect(form["action"]).to eq("/companies/set_country")
      expect(form["method"]).to eq("post")

      select = page.find("select")
      expect(select["onchange"]).to eq("this.form.requestSubmit()")
    end
  end

  context "with single country" do
    let(:available_countries) { [ "NO" ] }

    it "renders as text instead of dropdown" do
      render_inline(component)

      expect(page).not_to have_css("select")
      expect(page).to have_content("🇳🇴 Norway")
    end
  end

  context "dark mode support" do
    it "applies dark mode classes" do
      render_inline(component)

      expect(page).to have_css("select.dark\\:bg-gray-700.dark\\:text-white.dark\\:border-gray-600")
    end
  end

  describe "country name mapping" do
    it "maps country codes to names correctly" do
      expect(component.country_name("NO")).to eq("Norway")
      expect(component.country_name("SE")).to eq("Sweden")
      expect(component.country_name("DK")).to eq("Denmark")
      expect(component.country_name("FI")).to eq("Finland")
      expect(component.country_name("IS")).to eq("Iceland")
      expect(component.country_name("XX")).to eq("XX") # Unknown code
    end
  end

  describe "country flag mapping" do
    it "maps country codes to flag emojis" do
      expect(component.country_flag("NO")).to eq("🇳🇴")
      expect(component.country_flag("SE")).to eq("🇸🇪")
      expect(component.country_flag("DK")).to eq("🇩🇰")
      expect(component.country_flag("FI")).to eq("🇫🇮")
      expect(component.country_flag("IS")).to eq("🇮🇸")
      expect(component.country_flag("XX")).to eq("🏳️") # Unknown code
    end
  end
end
