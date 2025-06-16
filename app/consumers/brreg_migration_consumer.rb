class BrregMigrationConsumer < Karafka::BaseConsumer
  def consume(messages)
    messages.each do |message|
      begin
        data = JSON.parse(message.payload)
        BrregMigrationWorker.perform_async(data['organisasjonsnummer'])
      rescue => e
        Rails.logger.error "Error processing BRreg message: #{e.message}"
        # Removed mark_as_consumed as it is not needed
      end
    end
  end
end 