namespace :kafka do
  desc "Generate Kafka topics documentation"
  task generate_docs: :environment do
    require 'yaml'
    require 'json'

    kafka_yml = YAML.load_file(Rails.root.join('config', 'kafka.yml'))
    env = Rails.env
    topics = kafka_yml[env]['topics'] || {}
    schema_dir = Rails.root.join('docs', 'event_schemas')
    schemas = Dir.glob("#{schema_dir}/*.json").map { |f| File.basename(f, '.json') }

    puts "# Kafka Topics & Service Integration Documentation\n"
    puts "| Topic Name | Schema | DLQ |"
    puts "|------------|--------|-----|"

    topics.each do |topic, config|
      schema = schemas.include?(topic) ? "event_schemas/#{topic}.json" : ""
      dlq = config['dlq'] || (topic.to_s + '_dlq' if schemas.include?(topic)) || ""
      puts "| #{topic} | #{schema} | #{dlq} |"
    end

    puts "\n## Example Messages"
    schemas.each do |topic|
      schema_path = schema_dir.join("#{topic}.json")
      schema_json = JSON.parse(File.read(schema_path))
      if schema_json['example']
        puts "### #{topic}\n```json\n#{JSON.pretty_generate(schema_json['example'])}\n```\n"
      end
    end
  end
end 