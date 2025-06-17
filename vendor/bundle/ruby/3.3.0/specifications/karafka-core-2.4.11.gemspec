# -*- encoding: utf-8 -*-
# stub: karafka-core 2.4.11 ruby lib

Gem::Specification.new do |s|
  s.name = "karafka-core".freeze
  s.version = "2.4.11".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/karafka/karafka-core/issues", "changelog_uri" => "https://karafka.io/docs/Changelog-Karafka-Core", "documentation_uri" => "https://karafka.io/docs", "funding_uri" => "https://karafka.io/#become-pro", "homepage_uri" => "https://karafka.io", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/karafka/karafka-core" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Maciej Mensfeld".freeze]
  s.cert_chain = ["-----BEGIN CERTIFICATE-----\nMIIEcDCCAtigAwIBAgIBATANBgkqhkiG9w0BAQsFADA/MRAwDgYDVQQDDAdjb250\nYWN0MRcwFQYKCZImiZPyLGQBGRYHa2FyYWZrYTESMBAGCgmSJomT8ixkARkWAmlv\nMB4XDTI0MDgyMzEwMTkyMFoXDTQ5MDgxNzEwMTkyMFowPzEQMA4GA1UEAwwHY29u\ndGFjdDEXMBUGCgmSJomT8ixkARkWB2thcmFma2ExEjAQBgoJkiaJk/IsZAEZFgJp\nbzCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAKjLhLjQqUlNayxkXnO+\nPsmCDs/KFIzhrsYMfLZRZNaWmzV3ujljMOdDjd4snM2X06C41iVdQPWjpe3j8vVe\nZXEWR/twSbOP6Eeg8WVH2wCOo0x5i7yhVn4UBLH4JpfEMCbemVcWQ9ry9OMg4WpH\nUu4dRwxFV7hzCz3p0QfNLRI4miAxnGWcnlD98IJRjBAksTuR1Llj0vbOrDGsL9ZT\nJeXP2gdRLd8SqzAFJEWrbeTBCBU7gfSh3oMg5SVDLjaqf7Kz5wC/8bDZydzanOxB\nT6CDXPsCnllmvTNx2ei2T5rGYJOzJeNTmJLLK6hJWUlAvaQSvCwZRvFJ0tVGLEoS\nflqSr6uGyyl1eMUsNmsH4BqPEYcAV6P2PKTv2vUR8AP0raDvZ3xL1TKvfRb8xRpo\nvPopCGlY5XBWEc6QERHfVLTIVsjnls2/Ujj4h8/TSfqqYnaHKefIMLbuD/tquMjD\niWQsW2qStBV0T+U7FijKxVfrfqZP7GxQmDAc9o1iiyAa3QIDAQABo3cwdTAJBgNV\nHRMEAjAAMAsGA1UdDwQEAwIEsDAdBgNVHQ4EFgQU3O4dTXmvE7YpAkszGzR9DdL9\nsbEwHQYDVR0RBBYwFIESY29udGFjdEBrYXJhZmthLmlvMB0GA1UdEgQWMBSBEmNv\nbnRhY3RAa2FyYWZrYS5pbzANBgkqhkiG9w0BAQsFAAOCAYEAVKTfoLXn7mqdSxIR\neqxcR6Huudg1jes81s1+X0uiRTR3hxxKZ3Y82cPsee9zYWyBrN8TA4KA0WILTru7\nYgxvzha0SRPsSiaKLmgOJ+61ebI4+bOORzIJLpD6GxCxu1r7MI4+0r1u1xe0EWi8\nagkVo1k4Vi8cKMLm6Gl9b3wG9zQBw6fcgKwmpjKiNnOLP+OytzUANrIUJjoq6oal\nTC+f/Uc0TLaRqUaW/bejxzDWWHoM3SU6aoLPuerglzp9zZVzihXwx3jPLUVKDFpF\nRl2lcBDxlpYGueGo0/oNzGJAAy6js8jhtHC9+19PD53vk7wHtFTZ/0ugDQYnwQ+x\noml2fAAuVWpTBCgOVFe6XCQpMKopzoxQ1PjKztW2KYxgJdIBX87SnL3aWuBQmhRd\ni9zWxov0mr44TWegTVeypcWGd/0nxu1+QHVNHJrpqlPBRvwQsUm7fwmRInGpcaB8\nap8wNYvryYzrzvzUxIVFBVM5PacgkFqRmolCa8I7tdKQN+R1\n-----END CERTIFICATE-----\n".freeze]
  s.date = "2025-03-20"
  s.description = "A toolset of small support modules used throughout the Karafka ecosystem".freeze
  s.email = ["contact@karafka.io".freeze]
  s.homepage = "https://karafka.io".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1.0".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Karafka ecosystem core modules".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<karafka-rdkafka>.freeze, [">= 0.17.6".freeze, "< 0.20.0".freeze])
  s.add_runtime_dependency(%q<logger>.freeze, [">= 1.6.0".freeze])
end
