#!/usr/bin/env ruby

# karafka.rb - Boot file for Karafka 2.0+
require_relative 'config/environment'

class KarafkaApp < Karafka::App
  config_path = Rails.root.join('config', 'kafka.yml')
  kafka_config = File.exist?(config_path) ? YAML.load_file(config_path)[Rails.env] : nil
  bootstrap_servers = if kafka_config && kafka_config['kafka'] && kafka_config['kafka']['seed_brokers']
    kafka_config['kafka']['seed_brokers'].map { |broker| broker.gsub('kafka://', '') }.join(',')
  else
    nil
  end
  
  setup do |config|
    config.kafka = {
      'bootstrap.servers': bootstrap_servers
    }
    
    config.client_id = if kafka_config && kafka_config['consumer'] && kafka_config['consumer']['group_id']
      kafka_config['consumer']['group_id']
    else
      'test-client'
    end
  end
  
  routes.draw do
    group_id = if kafka_config && kafka_config['consumer'] && kafka_config['consumer']['group_id']
      kafka_config['consumer']['group_id']
    else
      'test-group'
    end
    consumer_group group_id do
      topic :domain_testing do
        consumer DomainTestingConsumer
      end
    end
  end
end 