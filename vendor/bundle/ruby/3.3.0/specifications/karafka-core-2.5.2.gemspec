# -*- encoding: utf-8 -*-
# stub: karafka-core 2.5.2 ruby lib

Gem::Specification.new do |s|
  s.name = "karafka-core".freeze
  s.version = "2.5.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/karafka/karafka-core/issues", "changelog_uri" => "https://karafka.io/docs/Changelog-Karafka-Core", "documentation_uri" => "https://karafka.io/docs", "funding_uri" => "https://karafka.io/#become-pro", "homepage_uri" => "https://karafka.io", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/karafka/karafka-core" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Maciej Mensfeld".freeze]
  s.date = "1980-01-02"
  s.description = "A toolset of small support modules used throughout the Karafka ecosystem".freeze
  s.email = ["contact@karafka.io".freeze]
  s.homepage = "https://karafka.io".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1.0".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Karafka ecosystem core modules".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<karafka-rdkafka>.freeze, [">= 0.19.2".freeze, "< 0.21.0".freeze])
  s.add_runtime_dependency(%q<logger>.freeze, [">= 1.6.0".freeze])
end
