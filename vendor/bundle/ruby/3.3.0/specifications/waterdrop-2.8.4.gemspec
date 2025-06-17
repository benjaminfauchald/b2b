# -*- encoding: utf-8 -*-
# stub: waterdrop 2.8.4 ruby lib

Gem::Specification.new do |s|
  s.name = "waterdrop".freeze
  s.version = "2.8.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/karafka/waterdrop/issues", "changelog_uri" => "https://karafka.io/docs/Changelog-WaterDrop", "documentation_uri" => "https://karafka.io/docs/#waterdrop", "funding_uri" => "https://karafka.io/#become-pro", "homepage_uri" => "https://karafka.io", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/karafka/waterdrop" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Maciej Mensfeld".freeze]
  s.date = "1980-01-02"
  s.description = "Kafka messaging made easy!".freeze
  s.email = ["contact@karafka.io".freeze]
  s.homepage = "https://karafka.io".freeze
  s.licenses = ["LGPL-3.0-only".freeze, "Commercial".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1.0".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Kafka messaging made easy!".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<karafka-core>.freeze, [">= 2.4.9".freeze, "< 3.0.0".freeze])
  s.add_runtime_dependency(%q<karafka-rdkafka>.freeze, [">= 0.19.2".freeze])
  s.add_runtime_dependency(%q<zeitwerk>.freeze, ["~> 2.3".freeze])
end
