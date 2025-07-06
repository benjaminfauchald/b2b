# frozen_string_literal: true

module FeatureMemories
  # Exports feature memory to markdown format for human readability
  class FeatureMemoryMarkdownExporter
  def initialize(memory_class)
    @memory_class = memory_class
    @data = memory_class.feature_data
  end

  def export
    markdown = []
    
    markdown << "# Feature Memory: #{@memory_class.feature_id}"
    markdown << ""
    
    export_spec(markdown)
    export_implementation_plan(markdown)
    export_implementation_log(markdown)
    export_troubleshooting(markdown)
    export_performance_metrics(markdown)
    
    markdown.join("\n")
  end

  private

  def export_spec(markdown)
    spec = @data[:spec]
    return unless spec

    markdown << "## Feature Specification"
    markdown << ""
    markdown << "**Description**: #{spec[:description]}" if spec[:description]
    markdown << "**Requested By**: #{spec[:requested_by]}" if spec[:requested_by]
    markdown << "**Created At**: #{spec[:created_at]}" if spec[:created_at]
    markdown << ""

    if spec[:requirements]
      markdown << "### Requirements"
      req = spec[:requirements]
      
      if req[:input_fields]
        markdown << "**Input Fields**:"
        req[:input_fields].each do |field, value|
          markdown << "- `#{field}`: #{value}"
        end
      end
      
      markdown << "**Output**: #{req[:output]}" if req[:output]
      markdown << "**Queue System**: #{req[:queue_system]}" if req[:queue_system]
      markdown << "**UI Location**: #{req[:ui_location]}" if req[:ui_location]
      
      if req[:dependencies]
        markdown << "**Dependencies**:"
        req[:dependencies].each do |dep|
          markdown << "- #{dep}"
        end
      end
      markdown << ""
    end

    if spec[:test_data]
      markdown << "### Test Data"
      spec[:test_data].each do |key, value|
        markdown << "- **#{key.to_s.humanize}**: #{value}"
      end
      markdown << ""
    end
  end

  def export_implementation_plan(markdown)
    plan = @data[:implementation_plan]
    return unless plan&.any?

    markdown << "## Implementation Plan"
    markdown << ""

    # Calculate stats
    total = plan.size
    completed = plan.count { |t| t[:status] == :completed }
    in_progress = plan.count { |t| t[:status] == :in_progress }
    pending = plan.count { |t| t[:status] == :pending }
    percentage = total > 0 ? (completed.to_f / total * 100).round(1) : 0

    markdown << "**Progress**: #{percentage}% Complete (#{completed}/#{total} tasks)"
    markdown << "- Completed: #{completed}"
    markdown << "- In Progress: #{in_progress}"
    markdown << "- Pending: #{pending}"
    markdown << ""

    markdown << "### Tasks"
    markdown << ""

    plan.each_with_index do |task, index|
      status_icon = case task[:status]
                    when :completed then "✓"
                    when :in_progress then "▶"
                    when :pending then "○"
                    when :blocked then "⊗"
                    when :cancelled then "×"
                    else "?"
                    end

      markdown << "#{index + 1}. **[#{status_icon}] #{task[:description]}**"
      markdown << "   - Status: `#{task[:status]}`"
      markdown << "   - Priority: #{task[:priority]}" if task[:priority]
      markdown << "   - Estimated Time: #{task[:estimated_time]}" if task[:estimated_time]
      markdown << "   - Assignee: #{task[:assignee]}" if task[:assignee]
      markdown << "   - Due Date: #{task[:due_date]}" if task[:due_date]
      markdown << "   - Tags: #{task[:tags].join(', ')}" if task[:tags]
      markdown << "   - Dependencies: #{task[:dependencies].join(', ')}" if task[:dependencies]
      markdown << "   - Notes: #{task[:notes]}" if task[:notes]
      markdown << "   - Created: #{task[:created_at]}" if task[:created_at]
      markdown << "   - Updated: #{task[:updated_at]}" if task[:updated_at]
      markdown << ""
    end
  end

  def export_implementation_log(markdown)
    log = @data[:implementation_log]
    return unless log&.any?

    markdown << "## Implementation Log"
    markdown << ""

    log.each do |step|
      markdown << "### #{step[:timestamp]}"
      markdown << "**Action**: #{step[:action]}" if step[:action]
      markdown << "**Status**: `#{step[:status]}`" if step[:status]
      markdown << "**Decision**: #{step[:decision]}" if step[:decision]
      markdown << "**Challenge**: #{step[:challenge]}" if step[:challenge]
      markdown << "**Solution**: #{step[:solution]}" if step[:solution]
      markdown << "**Code Reference**: `#{step[:code_ref]}`" if step[:code_ref]
      markdown << "**Test Reference**: `#{step[:test_ref]}`" if step[:test_ref]
      markdown << "**Notes**: #{step[:notes]}" if step[:notes]
      markdown << ""
    end
  end

  def export_troubleshooting(markdown)
    troubleshooting = @data[:troubleshooting]
    return unless troubleshooting&.any?

    markdown << "## Troubleshooting Guide"
    markdown << ""

    troubleshooting.each do |issue|
      markdown << "### Issue: #{issue[:description]}"
      markdown << "**Cause**: #{issue[:cause]}" if issue[:cause]
      markdown << "**Solution**: #{issue[:solution]}" if issue[:solution]
      
      if issue[:code_example]
        markdown << "**Code Example**:"
        markdown << "```ruby"
        markdown << issue[:code_example]
        markdown << "```"
      end
      
      markdown << "**Prevention**: #{issue[:prevention]}" if issue[:prevention]
      markdown << ""
    end
  end

  def export_performance_metrics(markdown)
    metrics = @data[:performance_metrics]
    return unless metrics&.any?

    markdown << "## Performance Metrics"
    markdown << ""

    metrics.each do |key, value|
      markdown << "- **#{key.to_s.humanize}**: #{value}"
    end
    markdown << ""
  end
end
end
