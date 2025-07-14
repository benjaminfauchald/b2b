class LinkedinCompanyLookup < ApplicationRecord
  belongs_to :company
  
  validates :linkedin_company_id, presence: true, uniqueness: true
  validates :confidence_score, inclusion: { in: 0..100 }
  
  scope :high_confidence, -> { where('confidence_score >= ?', 80) }
  scope :needs_refresh, -> { where('last_verified_at < ?', 7.days.ago) }
  scope :by_slug, ->(slug) { where(linkedin_slug: slug) }
  scope :recent, -> { where('created_at > ?', 24.hours.ago) }
  
  def self.find_company_by_linkedin_id(linkedin_company_id)
    find_by(linkedin_company_id: linkedin_company_id)&.company
  end
  
  def self.find_company_by_slug(slug)
    find_by(linkedin_slug: slug)&.company
  end
  
  def stale?
    last_verified_at.nil? || last_verified_at < 7.days.ago
  end
  
  def mark_verified!
    update!(last_verified_at: Time.current)
  end
end