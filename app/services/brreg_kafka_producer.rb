class BrregKafkaProducer
  def self.produce_batch(batch)
    batch.each do |brreg|
      Karafka.producer.produce_async(
        topic: "brreg_migration",
        payload: {
          organisasjonsnummer: brreg.organisasjonsnummer,
          timestamp: Time.current.to_i
        }.to_json
      )
    end
  end
end
