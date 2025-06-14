#!/usr/bin/env ruby

# karafka.rb - Boot file for Karafka 2.0+
require_relative 'config/environment'

class KarafkaApp < Karafka::App
  kafka_config = YAML.load_file(Rails.root.join('config', 'kafka.yml'))[Rails.env]
  
  setup do |config|
    bootstrap_servers = kafka_config['kafka']['seed_brokers'].map { |broker| broker.gsub('kafka://', '') }.join(',')
    
    config.kafka = {
      'bootstrap.servers': bootstrap_servers
    }
    
    config.client_id = kafka_config['consumer']['group_id']
  end
  
  routes.draw do
    consumer_group kafka_config['consumer']['group_id'] do
      topic :domain_testing do
        consumer DomainTestingConsumer
      end
    end
  end
end 