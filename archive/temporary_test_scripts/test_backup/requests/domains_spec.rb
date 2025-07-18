require 'rails_helper'

# This spec was generated by rspec-rails when you ran the scaffold generator.
# It demonstrates how one might use RSpec to test the controller code that
# was generated by Rails when you ran the scaffold generator.
#
# It assumes that the implementation code is generated by the rails scaffold
# generator. If you are using any extension libraries to generate different
# controller code, this generated spec may or may not pass.
#
# It only uses APIs available in rails and/or rspec-rails. There are a number
# of tools you can use to make these specs even more expressive, but we're
# sticking to rails and rspec-rails APIs to keep things simple and stable.

RSpec.describe "/domains", type: :request do
  # This should return the minimal set of attributes required to create a valid
  # Domain. As you add validations to Domain, be sure to
  # adjust the attributes here as well.
  let(:valid_attributes) {
    skip("Add a hash of attributes valid for your model")
  }

  let(:invalid_attributes) {
    skip("Add a hash of attributes invalid for your model")
  }

  describe "GET /index" do
    it "renders a successful response" do
      Domain.create! valid_attributes
      get domains_url
      expect(response).to be_successful
    end
  end

  describe "GET /show" do
    it "renders a successful response" do
      domain = Domain.create! valid_attributes
      get domain_url(domain)
      expect(response).to be_successful
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_domain_url
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      domain = Domain.create! valid_attributes
      get edit_domain_url(domain)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new Domain" do
        expect {
          post domains_url, params: { domain: valid_attributes }
        }.to change(Domain, :count).by(1)
      end

      it "redirects to the created domain" do
        post domains_url, params: { domain: valid_attributes }
        expect(response).to redirect_to(domain_url(Domain.last))
      end
    end

    context "with invalid parameters" do
      it "does not create a new Domain" do
        expect {
          post domains_url, params: { domain: invalid_attributes }
        }.to change(Domain, :count).by(0)
      end


      it "renders a response with 422 status (i.e. to display the 'new' template)" do
        post domains_url, params: { domain: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      let(:new_attributes) {
        skip("Add a hash of attributes valid for your model")
      }

      it "updates the requested domain" do
        domain = Domain.create! valid_attributes
        patch domain_url(domain), params: { domain: new_attributes }
        domain.reload
        skip("Add assertions for updated state")
      end

      it "redirects to the domain" do
        domain = Domain.create! valid_attributes
        patch domain_url(domain), params: { domain: new_attributes }
        domain.reload
        expect(response).to redirect_to(domain_url(domain))
      end
    end

    context "with invalid parameters" do
      it "renders a response with 422 status (i.e. to display the 'edit' template)" do
        domain = Domain.create! valid_attributes
        patch domain_url(domain), params: { domain: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested domain" do
      domain = Domain.create! valid_attributes
      expect {
        delete domain_url(domain)
      }.to change(Domain, :count).by(-1)
    end

    it "redirects to the domains list" do
      domain = Domain.create! valid_attributes
      delete domain_url(domain)
      expect(response).to redirect_to(domains_url)
    end
  end
end
