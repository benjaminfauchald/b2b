require 'rails_helper'
require 'fileutils'
require 'tempfile'

RSpec.describe 'Feature Memory System', :skip => "Legacy feature memory system not implemented - using IDM instead" do
  let(:features_dir) { Rails.root.join('docs', 'features') }
  let(:template_file) { features_dir.join('templates', 'feature_template.md') }
  let(:test_feature_name) { 'test_feature' }
  let(:test_feature_file) { features_dir.join("#{test_feature_name}.md") }

  before(:all) do
    # Ensure test directories exist
    FileUtils.mkdir_p(Rails.root.join('docs', 'features', 'templates'))
  end

  after(:each) do
    # Clean up test files but not for existing feature memory files
    FileUtils.rm_f(test_feature_file) if File.exist?(test_feature_file) && test_feature_name == 'test_feature'
  end

  describe 'Directory Structure' do
    it 'has the correct directory structure' do
      expect(Dir.exist?(features_dir)).to be true
      expect(Dir.exist?(features_dir.join('templates'))).to be true
    end

    it 'has the feature template file' do
      expect(File.exist?(template_file)).to be true
    end

    it 'has the feature memory rules file' do
      expect(File.exist?(Rails.root.join('docs', 'FEATURE_MEMORY_RULES.md'))).to be true
    end
  end

  describe 'Feature Template' do
    let(:template_content) { File.read(template_file) }

    it 'contains all required sections' do
      required_sections = [
        '## Feature Information',
        '## Overview',
        '## Requirements',
        '## Technical Plan',
        '## Current Progress',
        '## Technical Decisions',
        '## Code References',
        '## Test Plan',
        '## Conversation Context',
        '## Blockers & Issues',
        '## Notes'
      ]

      required_sections.each do |section|
        expect(template_content).to include(section)
      end
    end

    it 'contains placeholders for dynamic content' do
      placeholders = [
        '[Feature Name]',
        '[Date]',
        '[planning|in_progress|completed|failed|paused]'
      ]

      placeholders.each do |placeholder|
        expect(template_content).to include(placeholder)
      end
    end
  end

  describe 'Feature Memory CLI Script' do
    let(:script_path) { Rails.root.join('bin', 'feature-memory') }

    it 'exists and is executable' do
      expect(File.exist?(script_path)).to be true
      expect(File.executable?(script_path)).to be true
    end

    it 'can create a new feature memory file' do
      expect(File.exist?(test_feature_file)).to be false

      result = system("#{script_path} create #{test_feature_name}")
      expect(result).to be true
      expect(File.exist?(test_feature_file)).to be true
    end

    it 'creates feature files with correct content' do
      result = system("#{script_path} create #{test_feature_name}")
      expect(result).to be true

      expect(File.exist?(test_feature_file)).to be true
      content = File.read(test_feature_file)
      expect(content).to include('Test Feature')
      expect(content).to include('planning')
      expect(content).to include(Date.today.to_s)
    end

    it 'prevents duplicate feature creation' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")

      # Try to create again
      output = `#{script_path} create #{test_feature_name} 2>&1`
      expect(output).to include('already exists')
    end

    it 'can list feature memory files' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")

      output = `#{script_path} list`
      expect(output).to include('Feature Memory Files:')
      expect(output).to include('Test Feature')
    end

    it 'can show status summary' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")

      output = `#{script_path} status`
      expect(output).to include('Feature Memory Status Summary:')
      expect(output).to include('Total:')
    end

    it 'can update feature memory files' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")

      # Update the file
      system("#{script_path} update #{test_feature_name}")

      content = File.read(test_feature_file)
      expect(content).to include(Date.today.to_s)
    end

    it 'can mark features as completed' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")

      # Mark as completed
      system("#{script_path} complete #{test_feature_name}")

      content = File.read(test_feature_file)
      expect(content).to include('completed')
    end
  end

  describe 'Rails Tasks' do
    it 'has feature memory rake tasks' do
      tasks = `rake -T feature_memory`

      expect(tasks).to include('feature_memory:create')
      expect(tasks).to include('feature_memory:list')
      expect(tasks).to include('feature_memory:status')
      expect(tasks).to include('feature_memory:update')
      expect(tasks).to include('feature_memory:complete')
      expect(tasks).to include('feature_memory:validate')
      expect(tasks).to include('feature_memory:report')
    end

    it 'can create features via rake task' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      expect(File.exist?(test_feature_file)).to be false

      system("rake feature_memory:create[#{test_feature_name}]")

      expect(File.exist?(test_feature_file)).to be true
    end

    it 'can validate feature memory files' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("rake feature_memory:create[#{test_feature_name}]")

      output = `rake feature_memory:validate 2>&1`
      expect(output).to include('Valid')
      expect($?.success?).to be true
    end

    it 'can generate feature memory report' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("rake feature_memory:create[#{test_feature_name}]")

      output = `rake feature_memory:report`
      expect(output).to include('Feature Memory Report')
      expect(output).to include('Total:')
    end
  end

  describe 'Integration with Development Workflow' do
    let(:script_path) { Rails.root.join('bin', 'feature-memory') }

    it 'follows existing documentation patterns' do
      # Check that feature memory follows similar patterns to existing docs
      existing_docs = Dir.glob(Rails.root.join('docs', '*.md'))
      expect(existing_docs).not_to be_empty

      # Template should follow similar structure
      template_content = File.read(template_file)
      expect(template_content).to start_with('# ')
      expect(template_content).to include('## ')
    end

    it 'integrates with git workflow' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      # Create a feature and check git status
      system("#{script_path} create #{test_feature_name}")

      git_status = `git status --porcelain`
      # Check that the feature file is in untracked files (should contain docs/features/)
      expect(git_status).to include('docs/features/')
      expect(File.exist?(test_feature_file)).to be true
    end
  end

  describe 'Error Handling' do
    let(:script_path) { Rails.root.join('bin', 'feature-memory') }

    it 'handles missing feature names gracefully' do
      output = `#{script_path} create 2>&1`
      expect(output).to include('Error: Feature name is required')
    end

    it 'handles invalid commands gracefully' do
      output = `#{script_path} invalid_command 2>&1`
      expect(output).to include('Unknown command')
    end

    it 'handles missing template file' do
      # Temporarily move template file
      temp_template = template_file.to_s + '.bak'
      FileUtils.mv(template_file, temp_template) if File.exist?(template_file)

      output = `#{script_path} create #{test_feature_name} 2>&1`
      expect(output).to include('Template file not found')

      # Restore template file
      FileUtils.mv(temp_template, template_file) if File.exist?(temp_template)
    end
  end

  describe 'Content Validation' do
    let(:script_path) { Rails.root.join('bin', 'feature-memory') }

    before do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      system("#{script_path} create #{test_feature_name}")
    end

    it 'creates files with valid markdown structure' do
      content = File.read(test_feature_file)

      # Check for valid markdown headers
      headers = content.scan(/^#+\s+.+/).size
      expect(headers).to be > 5

      # Check for checkbox lists
      expect(content).to include('- [ ]')

      # Check for bold text
      expect(content).to include('**')
    end

    it 'includes proper status tracking' do
      content = File.read(test_feature_file)

      expect(content).to include('**Status**:')
      expect(content).to include('**Started**:')
      expect(content).to include('**Last Updated**:')
      expect(content).to include('**Current Step**:')
      expect(content).to include('**Next Action**:')
    end

    it 'includes context preservation sections' do
      content = File.read(test_feature_file)

      expect(content).to include('## Conversation Context')
      expect(content).to include('## Technical Decisions')
      expect(content).to include('## Code References')
      expect(content).to include('Full Conversation Log')
    end
  end

  describe 'Crash Recovery Simulation' do
    let(:script_path) { Rails.root.join('bin', 'feature-memory') }

    it 'preserves enough context for agent recovery' do
      FileUtils.rm_f(test_feature_file) # Ensure clean start
      # Create a feature with some progress
      system("#{script_path} create #{test_feature_name}")

      # Simulate adding context
      content = File.read(test_feature_file)
      enhanced_content = content.gsub(
        '**Next Action**: [Description of next action]',
        '**Next Action**: Implement user authentication controller'
      )
      enhanced_content = enhanced_content.gsub(
        '1. [ ] Step 1 - Description',
        '1. [x] Step 1 - Create user model'
      )
      enhanced_content = enhanced_content.gsub(
        '[Full conversation history will be preserved here]',
        "User: Create user authentication system\nAgent: I'll implement a comprehensive user authentication system..."
      )

      File.write(test_feature_file, enhanced_content)

      # Verify recovery information is present
      recovery_content = File.read(test_feature_file)
      expect(recovery_content).to include('Implement user authentication controller')
      expect(recovery_content).to include('[x] Step 1 - Create user model')
      expect(recovery_content).to include('User: Create user authentication system')
    end
  end
end
