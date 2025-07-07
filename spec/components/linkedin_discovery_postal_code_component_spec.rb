# frozen_string_literal: true

require "rails_helper"

RSpec.describe LinkedinDiscoveryPostalCodeComponent, type: :component do
  before do
    # Enable the LinkedIn discovery service
    ServiceConfiguration.create!(
      service_name: "company_linkedin_discovery",
      active: true
    )
  end

  describe "rendering" do
    it "renders the component when service is active" do
      render_inline(described_class.new)
      
      expect(rendered_content).to have_text("LinkedIn Discovery by Postal Code")
      expect(rendered_content).to have_selector("select[name='postal_code']")
      expect(rendered_content).to have_selector("select[name='batch_size']")
      expect(rendered_content).to have_selector("input[name='custom_postal_code']")
    end

    it "does not render when service is inactive" do
      ServiceConfiguration.find_by(service_name: "company_linkedin_discovery")&.update!(active: false)
      
      render_inline(described_class.new)
      
      expect(rendered_content).to be_empty
    end
  end

  describe "initialization" do
    it "uses default values when no parameters provided" do
      component = described_class.new
      
      expect(component.postal_code).to eq('2000')
      expect(component.batch_size).to eq(100)
    end

    it "uses provided values" do
      component = described_class.new(postal_code: '0150', batch_size: 50)
      
      expect(component.postal_code).to eq('0150')
      expect(component.batch_size).to eq(50)
    end
  end

  describe "company preview calculation" do
    let!(:companies_2000) do
      [
        create(:company, postal_code: '2000', operating_revenue: 1_000_000),
        create(:company, postal_code: '2000', operating_revenue: 500_000),
        create(:company, postal_code: '2000', operating_revenue: 100_000)
      ]
    end

    it "calculates preview for postal code with companies" do
      component = described_class.new(postal_code: '2000', batch_size: 2)
      preview = component.company_preview
      
      expect(preview[:count]).to eq(3)
      expect(preview[:revenue_range]).to be_present
      expect(preview[:revenue_range][:highest]).to eq(1_000_000)
      expect(preview[:revenue_range][:lowest]).to eq(500_000)
    end

    it "handles postal code with no companies" do
      component = described_class.new(postal_code: '9999', batch_size: 10)
      preview = component.company_preview
      
      expect(preview[:count]).to eq(0)
      expect(preview[:revenue_range]).to be_nil
    end

    it "handles blank postal code" do
      component = described_class.new(postal_code: '', batch_size: 10)
      preview = component.company_preview
      
      expect(preview[:count]).to eq(0)
      expect(preview[:revenue_range]).to be_nil
    end
  end

  describe "helper methods" do
    describe "#format_revenue" do
      let(:component) { described_class.new }

      it "formats large revenues correctly" do
        expect(component.send(:format_revenue, 1_500_000_000)).to eq("1.5B NOK")
        expect(component.send(:format_revenue, 2_500_000)).to eq("2.5M NOK")
        expect(component.send(:format_revenue, 150_000)).to eq("150K NOK")
        expect(component.send(:format_revenue, 500)).to eq("500 NOK")
      end

      it "handles nil values" do
        expect(component.send(:format_revenue, nil)).to eq("N/A")
      end
    end

    describe "#preview_text" do
      let!(:companies) do
        [
          create(:company, postal_code: '2000', operating_revenue: 1_000_000),
          create(:company, postal_code: '2000', operating_revenue: 500_000)
        ]
      end

      it "generates preview text for companies found" do
        component = described_class.new(postal_code: '2000', batch_size: 1)
        
        expect(component.preview_text).to include("2 companies found")
        expect(component.preview_text).to include("top 1")
        expect(component.preview_text).to include("revenue range")
      end

      it "generates preview text when processing all companies" do
        component = described_class.new(postal_code: '2000', batch_size: 5)
        
        expect(component.preview_text).to include("2 companies found")
        expect(component.preview_text).to include("all 2")
      end

      it "generates preview text for no companies" do
        component = described_class.new(postal_code: '9999', batch_size: 10)
        
        expect(component.preview_text).to eq("No companies found in postal code 9999")
      end
    end

    describe "#can_process?" do
      let!(:companies) do
        create_list(:company, 3, postal_code: '2000', operating_revenue: 100_000)
      end

      it "returns true when companies are available and batch size is valid" do
        component = described_class.new(postal_code: '2000', batch_size: 2)
        
        expect(component.can_process?).to be true
      end

      it "returns false when no companies are available" do
        component = described_class.new(postal_code: '9999', batch_size: 10)
        
        expect(component.can_process?).to be false
      end

      it "returns false when batch size exceeds available companies" do
        component = described_class.new(postal_code: '2000', batch_size: 10)
        
        expect(component.can_process?).to be false
      end
    end
  end

  describe "postal code options" do
    let!(:companies_with_revenue) do
      # Create companies in different postal codes with sufficient counts
      (1..15).map { |i| create(:company, postal_code: '2000', operating_revenue: 100_000) } +
      (1..12).map { |i| create(:company, postal_code: '0150', operating_revenue: 200_000) } +
      (1..8).map { |i| create(:company, postal_code: '1234', operating_revenue: 150_000) }
    end

    it "returns postal codes with sufficient companies" do
      component = described_class.new
      options = component.postal_code_options
      
      expect(options).to include('2000', '0150')
      expect(options.size).to be <= 20  # Limited to 20 options
    end
  end

  describe "batch size options" do
    it "returns predefined batch size options" do
      component = described_class.new
      options = component.batch_size_options
      
      expect(options).to eq([10, 25, 50, 100, 200, 500, 1000])
    end
  end

  describe "rendered form elements" do
    let!(:companies) do
      create_list(:company, 5, postal_code: '2000', operating_revenue: 100_000)
    end

    it "renders form with correct action" do
      render_inline(described_class.new)
      
      expect(rendered_content).to have_selector("form[action*='queue_linkedin_discovery_by_postal_code']")
      expect(rendered_content).to have_selector("form[method='post']")
    end

    it "renders postal code select with options" do
      render_inline(described_class.new)
      
      expect(rendered_content).to have_selector("select[name='postal_code']")
      expect(rendered_content).to include("Enter custom postal code...")
    end

    it "renders batch size select with options" do
      render_inline(described_class.new)
      
      expect(rendered_content).to have_selector("select[name='batch_size']")
      expect(rendered_content).to include("100")
      expect(rendered_content).to include("500")
    end

    it "renders submit button when processing is possible" do
      render_inline(described_class.new(postal_code: '2000', batch_size: 3))
      
      expect(rendered_content).to have_button("Queue LinkedIn Discovery")
    end

    it "renders disabled button when no companies found" do
      render_inline(described_class.new(postal_code: '9999', batch_size: 10))
      
      expect(rendered_content).to have_button("No Companies Found", disabled: true)
    end

    it "includes Stimulus controller data attributes" do
      render_inline(described_class.new)
      
      expect(rendered_content).to have_selector("[data-controller='postal-code-form']")
      expect(rendered_content).to have_selector("[data-action*='postal-code-form#updatePreview']")
    end
  end
end