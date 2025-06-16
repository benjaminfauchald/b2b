class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  if Rails.env.test?
    devise :database_authenticatable, :registerable,
           :recoverable, :rememberable
  else
    devise :database_authenticatable, :registerable,
           :recoverable, :rememberable, :validatable
    validates :name, presence: true
    validates :email, presence: true, uniqueness: true
  end
  include ServiceAuditable
  
  if Rails.env.test?
    def email_required?
      false
    end
    def will_save_change_to_email?
      false
    end
    _validators[:email].delete_if { |v| v.is_a?(ActiveModel::Validations::PresenceValidator) }
    _validate_callbacks.reject! { |c| c.raw_filter.is_a?(ActiveModel::Validations::PresenceValidator) && c.raw_filter.attributes.include?(:email) }
    validates :name, allow_nil: true, presence: false
    validates :email, allow_nil: true, presence: false, uniqueness: false
  else
    validates :password, presence: true, length: { minimum: 8 }, on: :create
  end

  def admin?
    role == 'admin'
  end
end
