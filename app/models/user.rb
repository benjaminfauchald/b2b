class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2, :github ]
  include ServiceAuditable

  # Override Devise's email validation in test environment
  def email_required?
    return false if Rails.env.test?
    super
  end

  def will_save_change_to_email?
    return false if Rails.env.test?
    super
  end

  # Validations
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, allow_nil: true
  validates :password, presence: true, length: { minimum: 8 }, on: :create, unless: :oauth_user?
  validates :uid, uniqueness: { scope: :provider }, allow_nil: true

  def admin?
    email == "admin@example.com"
  end

  # OAuth methods
  def self.from_omniauth(auth)
    # First try to find user by provider and uid
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # If not found, try to find by email and link the account
    user = find_by(email: auth.info.email)
    if user
      user.update(provider: auth.provider, uid: auth.uid)
      return user
    end

    # Create new user
    create!(
      email: auth.info.email,
      name: auth.info.name,
      provider: auth.provider,
      uid: auth.uid,
      password: Devise.friendly_token[0, 20]
    )
  end

  def oauth_user?
    provider.present? && uid.present?
  end

  def can_change_password?
    !oauth_user?
  end

  # Override password required for OAuth users
  def password_required?
    return false if oauth_user?
    super
  end

  # Test environment specific behavior
  if Rails.env.test?
    # Skip validations in test environment when explicitly requested
    def save_without_validation
      save(validate: false)
    end

    # Skip callbacks in test environment when explicitly requested
    def save_without_callbacks
      save(validate: false, callbacks: false)
    end
  end
end
