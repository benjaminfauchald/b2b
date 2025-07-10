class GeographicalTerm < ApplicationRecord
  VALID_TYPES = %w[
    country
    state
    county
    municipality
    city
    region
    sub_region
    post_place
    direction
    district
  ].freeze

  VALID_LANGUAGES = %w[NO EN].freeze

  validates :term, presence: true
  validates :term_type, presence: true, inclusion: { in: VALID_TYPES }
  validates :language, presence: true, inclusion: { in: VALID_LANGUAGES }
  validates :term, uniqueness: { scope: :language }

  scope :by_type, ->(type) { where(term_type: type) }
  scope :by_language, ->(language) { where(language: language) }
  scope :norwegian, -> { where(language: 'NO') }
  scope :english, -> { where(language: 'EN') }

  # Get all terms for a specific type and language
  def self.terms_for(type, language = 'NO')
    by_type(type).by_language(language).pluck(:term)
  end

  # Get all geographical terms for matching (excluding country and direction)
  def self.geographical_matching_terms(language = 'NO')
    where(language: language)
      .where.not(term_type: %w[country direction])
      .pluck(:term)
  end

  # Get all terms that indicate subsidiaries/branches
  def self.subsidiary_indicator_terms(language = 'NO')
    by_language(language).pluck(:term)
  end

  def self.direction_terms(language = 'NO')
    terms_for('direction', language)
  end

  def self.country_terms(language = 'NO')
    terms_for('country', language)
  end

  def self.district_terms(language = 'NO')
    terms_for('district', language)
  end
end