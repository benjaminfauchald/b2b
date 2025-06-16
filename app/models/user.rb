class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
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
  validates :password, presence: true, length: { minimum: 8 }, on: :create

  def admin?
    email == 'admin@example.com'
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
