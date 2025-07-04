# frozen_string_literal: true

class PersonImportResult
  attr_reader :imported_count, :failed_count, :duplicate_count, :imported_people, :failed_people,
              :duplicate_people, :error_message, :processing_time, :csv_errors, :updated_count, :updated_people,
              :import_tag, :email_verification_stats

  def initialize(import_tag: nil)
    @imported_count = 0
    @failed_count = 0
    @duplicate_count = 0
    @updated_count = 0
    @imported_people = []
    @failed_people = []
    @duplicate_people = []
    @updated_people = []
    @error_message = nil
    @processing_time = nil
    @csv_errors = []
    @start_time = Time.current
    @import_tag = import_tag
    @email_verification_stats = {
      total_verified: 0,
      passed: 0,
      failed: 0,
      pending: 0,
      skipped: 0
    }
  end

  def add_imported_person(person, row_number)
    @imported_people << {
      name: person.name,
      email: person.email,
      company_name: person.company_name,
      row: row_number,
      created_at: person.created_at
    }
    @imported_count += 1
  end

  def add_updated_person(person, row_number, changes)
    @updated_people << {
      name: person.name,
      email: person.email,
      company_name: person.company_name,
      row: row_number,
      changes: changes,
      updated_at: person.updated_at
    }
    @updated_count += 1
  end

  def add_failed_person(person_data, row_number, errors)
    @failed_people << {
      name: person_data[:name] || "#{person_data[:first_name]} #{person_data[:last_name]}".strip,
      email: person_data[:email],
      company_name: person_data[:company_name],
      row: row_number,
      errors: errors
    }
    @failed_count += 1
  end

  def add_duplicate_person(person_data, row_number)
    @duplicate_people << {
      name: person_data[:name] || "#{person_data[:first_name]} #{person_data[:last_name]}".strip,
      email: person_data[:email],
      company_name: person_data[:company_name],
      row: row_number
    }
    @duplicate_count += 1
  end

  def add_csv_error(error_message)
    @csv_errors << error_message
  end

  def set_error_message(message)
    @error_message = message
  end

  def track_email_verification(person, verification_attempted = false)
    return unless person && person.email.present?
    
    if verification_attempted
      @email_verification_stats[:total_verified] += 1
      
      case person.email_verification_status
      when 'valid'
        @email_verification_stats[:passed] += 1
      when 'invalid'
        @email_verification_stats[:failed] += 1
      else
        @email_verification_stats[:pending] += 1
      end
    else
      @email_verification_stats[:skipped] += 1
    end
  end

  def email_verification_summary
    stats = @email_verification_stats
    return "No email verification performed" if stats[:total_verified] == 0 && stats[:skipped] == 0
    
    parts = []
    parts << "#{stats[:passed]} passed" if stats[:passed] > 0
    parts << "#{stats[:failed]} failed" if stats[:failed] > 0
    parts << "#{stats[:pending]} pending" if stats[:pending] > 0
    parts << "#{stats[:skipped]} skipped" if stats[:skipped] > 0
    
    return "Email verification: " + (parts.empty? ? "none" : parts.join(", "))
  end

  def success?
    @failed_count == 0 && @csv_errors.empty? && (@imported_count > 0 || @updated_count > 0)
  end

  def total_count
    @imported_count + @failed_count + @duplicate_count + @updated_count
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

    parts = []
    parts << "#{@imported_count} imported" if @imported_count > 0
    parts << "#{@updated_count} updated" if @updated_count > 0
    parts << "#{@failed_count} failed" if @failed_count > 0
    parts << "#{@duplicate_count} skipped (duplicates)" if @duplicate_count > 0

    return "No people processed" if parts.empty?

    parts.join(", ")
  end

  def people_per_second
    return 0.0 if @processing_time.nil? || @processing_time == 0.0

    (total_count.to_f / @processing_time).round(2)
  end

  def to_h
    {
      success: success?,
      imported_count: @imported_count,
      updated_count: @updated_count,
      failed_count: @failed_count,
      duplicate_count: @duplicate_count,
      total_count: total_count,
      imported_people: @imported_people,
      updated_people: @updated_people,
      failed_people: @failed_people,
      duplicate_people: @duplicate_people,
      error_message: @error_message,
      processing_time: @processing_time,
      csv_errors: @csv_errors,
      summary_message: summary_message,
      people_per_second: people_per_second,
      email_verification_stats: @email_verification_stats,
      email_verification_summary: email_verification_summary
    }
  end

  def to_json(*args)
    to_h.to_json(*args)
  end
end
