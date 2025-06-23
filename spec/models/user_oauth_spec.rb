require 'rails_helper'

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
        user = create(:user, :google_oauth)
        expect(user.oauth_user?).to be true
      end

      it "returns false for regular users" do
        user = create(:user, provider: nil, uid: nil)
        expect(user.oauth_user?).to be false
      end
    end

    describe "#can_change_password?" do
      it "returns false for OAuth users" do
        user = create(:user, :google_oauth)
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
      user = build(:user, :oauth_user)
      expect(user).to be_valid
    end

    it "requires password for regular users" do
      user = build(:user, password: nil, password_confirmation: nil)
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
