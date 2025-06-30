require 'rails_helper'

RSpec.describe "People", type: :request do
  let(:user) { create(:user) }
  
  before do
    sign_in user
  end
  describe "GET /index" do
    it "returns http success" do
      get "/people"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      person = create(:person)
      get "/people/#{person.id}"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get "/people/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      person = create(:person)
      get "/people/#{person.id}/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /create" do
    it "returns http success" do
      post "/people", params: { person: { name: "Test Person" } }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /update" do
    it "returns http success" do
      person = create(:person)
      patch "/people/#{person.id}", params: { person: { name: "Updated Name" } }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "DELETE /destroy" do
    it "returns http success" do
      person = create(:person)
      delete "/people/#{person.id}"
      expect(response).to have_http_status(:redirect)
    end
  end
end
