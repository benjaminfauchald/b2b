class DomainMXTestingConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      process_message(message)
    end
  end

  private

  def process_message(message)
    domain_id = message.payload["domain_id"]
    return unless domain_id

    DomainMXTestingWorker.perform_async(domain_id)
  rescue StandardError => e
    Rails.logger.error("Error processing MX testing message: #{e.message}")
    raise
  end
end
