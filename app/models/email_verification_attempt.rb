# frozen_string_literal: true

class EmailVerificationAttempt < ApplicationRecord
  belongs_to :person

  validates :email, presence: true
  validates :domain, presence: true
  validates :status, presence: true
  validates :attempted_at, presence: true

  # Status enums
  STATUSES = {
    success: "success",
    invalid_syntax: "invalid_syntax",
    invalid_domain: "invalid_domain",
    invalid_mx: "invalid_mx",
    smtp_failure: "smtp_failure",
    mailbox_not_found: "mailbox_not_found",
    greylist_retry: "greylist_retry",
    rate_limited: "rate_limited",
    timeout: "timeout",
    unknown_error: "unknown_error"
  }.freeze

  scope :recent, -> { order(attempted_at: :desc) }
  scope :by_domain, ->(domain) { where(domain: domain) }
  scope :successful, -> { where(status: STATUSES[:success]) }
  scope :failed, -> { where.not(status: [ STATUSES[:success], STATUSES[:greylist_retry] ]) }
end
