# -*- encoding: utf-8 -*-
# stub: sidekiq 8.0.4 ruby lib

Gem::Specification.new do |s|
  s.name = "sidekiq".freeze
  s.version = "8.0.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/sidekiq/sidekiq/issues", "changelog_uri" => "https://github.com/sidekiq/sidekiq/blob/main/Changes.md", "documentation_uri" => "https://github.com/sidekiq/sidekiq/wiki", "homepage_uri" => "https://sidekiq.org", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/sidekiq/sidekiq" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Mike Perham".freeze]
  s.date = "2025-05-28"
  s.description = "Simple, efficient background processing for Ruby.".freeze
  s.email = ["info@contribsys.com".freeze]
  s.executables = ["sidekiq".freeze, "sidekiqmon".freeze]
  s.files = ["bin/sidekiq".freeze, "bin/sidekiqmon".freeze]
  s.homepage = "https://sidekiq.org".freeze
  s.licenses = ["LGPL-3.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2.0".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Simple, efficient background processing for Ruby".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<redis-client>.freeze, [">= 0.23.2".freeze])
  s.add_runtime_dependency(%q<connection_pool>.freeze, [">= 2.5.0".freeze])
  s.add_runtime_dependency(%q<rack>.freeze, [">= 3.1.0".freeze])
  s.add_runtime_dependency(%q<json>.freeze, [">= 2.9.0".freeze])
  s.add_runtime_dependency(%q<logger>.freeze, [">= 1.6.2".freeze])
end
