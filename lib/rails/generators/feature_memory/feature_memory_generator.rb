# frozen_string_literal: true

require "rails/generators"

module Rails
  module Generators
    module FeatureMemory
      class FeatureMemoryGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :description, type: :string, default: "", banner: "description"

          def create_feature_memory_file
        template "feature_memory.rb.tt", "app/services/feature_memories/#{file_name}.rb"
      end

          def add_to_git
        git add: "app/services/feature_memories/#{file_name}.rb"
      end

          def output_next_steps
        say ""
        say "Feature Memory created successfully!", :green
        say ""
        say "Next steps:"
        say "1. Fill in the requirements section with specific details"
        say "2. Update test_data with actual test values"
        say "3. Add tasks to implementation_plan before starting work"
        say "4. Use ApplicationFeatureMemory.find('#{file_name}') to access this memory"
        say "5. Update task status and implementation_log as you progress"
        say ""
        say "To view status: rails feature_memory:status #{file_name}"
        say "To export markdown: rails feature_memory:export #{file_name}"
      end

      private

          def feature_class_name
        class_name
      end

          def feature_description
        description.presence || "TODO: Add description"
      end

          def current_date
        Date.current.to_s
      end

          def current_user
        ENV["USER"] || "unknown"
      end
    end
    end
  end
end