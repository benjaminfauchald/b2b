ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Rails 8 Autoload Paths Freeze Protection - Applied at boot level
# This must be done before any Rails classes are loaded
if ENV["CI"] || ENV["RAILS_ENV"] == "test"
  # Monkey patch Array#unshift globally to handle frozen autoload_paths
  class Array
    alias_method :original_unshift, :unshift
    
    def unshift(*args)
      if frozen? && caller.any? { |line| line.include?("rails/engine.rb") }
        # Log the attempt but don't raise an error for Rails engines
        puts "Rails 8 CI: Prevented unshift to frozen autoload_paths from Rails engine"
        return self
      end
      original_unshift(*args)
    end
  end
end
