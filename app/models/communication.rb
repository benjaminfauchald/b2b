class Communication < ApplicationRecord
  validates :timestamp, :event_type, :service, :connection_attempt_type, presence: true
end
