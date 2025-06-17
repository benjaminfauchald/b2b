# -*- encoding: utf-8 -*-
# stub: karafka-rdkafka 0.19.5 ruby lib
# stub: ext/Rakefile

Gem::Specification.new do |s|
  s.name = "karafka-rdkafka".freeze
  s.version = "0.19.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/karafka/karafka-rdkafka/issues", "changelog_uri" => "https://karafka.io/docs/Changelog-Karafka-Rdkafka/", "documentation_uri" => "https://karafka.io/docs", "funding_uri" => "https://karafka.io/#become-pro", "homepage_uri" => "https://karafka.io", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/karafka/karafka-rdkafka" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Thijs Cadier".freeze, "Maciej Mensfeld".freeze]
  s.date = "1980-01-02"
  s.description = "Modern Kafka client library for Ruby based on librdkafka".freeze
  s.email = ["contact@karafka.io".freeze]
  s.extensions = ["ext/Rakefile".freeze]
  s.files = ["ext/Rakefile".freeze]
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "The rdkafka gem is a modern Kafka client library for Ruby based on librdkafka. It wraps the production-ready C client using the ffi gem and targets Kafka 1.0+ and Ruby 2.7+.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<ffi>.freeze, ["~> 1.15".freeze])
  s.add_runtime_dependency(%q<mini_portile2>.freeze, ["~> 2.6".freeze])
  s.add_runtime_dependency(%q<rake>.freeze, ["> 12".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.5".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<guard>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<guard-rspec>.freeze, [">= 0".freeze])
end
