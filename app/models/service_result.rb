# frozen_string_literal: true

class ServiceResult
  attr_reader :data, :error_message

  def initialize(success:, data: nil, error_message: nil)
    @success = success
    @data = data || {}
    @error_message = error_message
  end

  def success?
    @success
  end

  def error?
    !@success
  end

  def self.success(data = {})
    new(success: true, data: data)
  end

  def self.error(message)
    new(success: false, error_message: message)
  end
end