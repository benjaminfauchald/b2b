# -*- encoding: utf-8 -*-
# stub: karafka 2.5.0 ruby lib

Gem::Specification.new do |s|
  s.name = "karafka".freeze
  s.version = "2.5.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/karafka/karafka/issues", "changelog_uri" => "https://karafka.io/docs/Changelog-Karafka", "documentation_uri" => "https://karafka.io/docs", "funding_uri" => "https://karafka.io/#become-pro", "homepage_uri" => "https://karafka.io", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/karafka/karafka" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Maciej Mensfeld".freeze]
  s.date = "1980-01-02"
  s.description = "    Karafka is Ruby and Rails efficient Kafka processing framework.\n\n    Karafka allows you to capture everything that happens in your systems in large scale,\n    without having to focus on things that are not your business domain.\n".freeze
  s.email = ["contact@karafka.io".freeze]
  s.executables = ["karafka".freeze]
  s.files = ["bin/karafka".freeze]
  s.homepage = "https://karafka.io".freeze
  s.licenses = ["LGPL-3.0-only".freeze, "Commercial".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Karafka is Ruby and Rails efficient Kafka processing framework.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<base64>.freeze, ["~> 0.2".freeze])
  s.add_runtime_dependency(%q<karafka-core>.freeze, [">= 2.5.2".freeze, "< 2.6.0".freeze])
  s.add_runtime_dependency(%q<karafka-rdkafka>.freeze, [">= 0.19.5".freeze])
  s.add_runtime_dependency(%q<waterdrop>.freeze, [">= 2.8.3".freeze, "< 3.0.0".freeze])
  s.add_runtime_dependency(%q<zeitwerk>.freeze, ["~> 2.3".freeze])
end
