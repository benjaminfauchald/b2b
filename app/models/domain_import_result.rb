# frozen_string_literal: true

class DomainImportResult
  attr_reader :imported_count, :failed_count, :imported_domains, :failed_domains,
              :error_message, :processing_time, :csv_errors

  def initialize
    @imported_count = 0
    @failed_count = 0
    @imported_domains = []
    @failed_domains = []
    @error_message = nil
    @processing_time = nil
    @csv_errors = []
    @start_time = Time.current
  end

  def add_imported_domain(domain, row_number)
    @imported_domains << {
      domain: domain.domain,
      row: row_number,
      created_at: domain.created_at
    }
    @imported_count += 1
  end

  def add_failed_domain(domain_name, row_number, errors)
    @failed_domains << {
      domain: domain_name,
      row: row_number,
      errors: errors
    }
    @failed_count += 1
  end

  def add_csv_error(error_message)
    @csv_errors << error_message
  end

  def set_error_message(message)
    @error_message = message
  end

  def success?
    @failed_count == 0 && @csv_errors.empty? && @imported_count > 0
  end

  def total_count
    @imported_count + @failed_count
  end

  def has_csv_errors?
    @csv_errors.any?
  end

  def finalize!
    @processing_time = (Time.current - @start_time).round(2)
  end

  def summary_message
    if has_csv_errors?
      return "CSV parsing errors occurred"
    end

    case
    when success?
      pluralize(@imported_count, "domain") + " imported successfully"
    when @imported_count > 0 && @failed_count > 0
      "#{@imported_count} of #{total_count} domains imported successfully, #{@failed_count} failed"
    else
      "#{@imported_count} domains imported, #{@failed_count} failed"
    end
  end

  def domains_per_second
    return 0.0 if @processing_time.nil? || @processing_time == 0.0

    (total_count.to_f / @processing_time).round(2)
  end

  def to_h
    {
      success: success?,
      imported_count: @imported_count,
      failed_count: @failed_count,
      total_count: total_count,
      imported_domains: @imported_domains,
      failed_domains: @failed_domains,
      error_message: @error_message,
      processing_time: @processing_time,
      csv_errors: @csv_errors,
      summary_message: summary_message,
      domains_per_second: domains_per_second
    }
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  private

  def pluralize(count, singular, plural = nil)
    plural ||= "#{singular}s"
    "#{count} #{count == 1 ? singular : plural}"
  end
end
