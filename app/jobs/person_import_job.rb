# frozen_string_literal: true

class PersonImportJob < ApplicationJob
  queue_as :default

  def perform(temp_file_path, user_id, original_filename, import_id, validate_emails = false)
    Rails.logger.info "🚀 PersonImportJob started: #{import_id}"
    Rails.logger.info "  - File: #{temp_file_path}"
    Rails.logger.info "  - User ID: #{user_id}"
    Rails.logger.info "  - Original filename: #{original_filename}"

    begin
      user = User.find(user_id)
      Rails.logger.info "  - User found: #{user.email}"

      # Initialize progress tracking immediately
      progress_key = "person_import_progress_#{user_id}"
      progress_data = {
        current: 0,
        total: 100,
        percent: 0,
        message: "Import job starting...",
        updated_at: Time.current.iso8601
      }
      Rails.cache.write(progress_key, progress_data, expires_in: 10.minutes)
      Rails.logger.info "  - Initial progress set in cache: #{progress_key}"

      # Create a file-like object for the service
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(temp_file_path),
        filename: original_filename,
        type: "text/csv"
      )

      # Run the import service
      service = PersonImportService.new(
        file: file,
        user: user,
        validate_emails: validate_emails
      )

      Rails.logger.info "  - PersonImportService created, starting import..."
      result = service.perform

      # Ensure final progress is set
      final_progress_data = {
        current: 100,
        total: 100,
        percent: 100,
        message: "Import completed successfully!",
        updated_at: Time.current.iso8601
      }
      Rails.cache.write(progress_key, final_progress_data, expires_in: 10.minutes)
      Rails.logger.info "  - Final progress set: 100%"

      # Save the result to a temporary file for the controller to read
      result_file_path = Rails.root.join("tmp", "person_import_result_#{import_id}.json")
      File.write(result_file_path, result.data[:result].to_h.to_json)

      Rails.logger.info "✅ PersonImportJob completed: #{import_id}"
      Rails.logger.info "  - Success: #{result.success?}"
      Rails.logger.info "  - Imported: #{result.data[:imported]}"
      Rails.logger.info "  - Updated: #{result.data[:updated]}"
      Rails.logger.info "  - Failed: #{result.data[:failed]}"
      Rails.logger.info "  - Duplicates: #{result.data[:duplicates]}"

    rescue StandardError => e
      Rails.logger.error "❌ PersonImportJob failed: #{import_id}"
      Rails.logger.error "  - Error: #{e.message}"
      Rails.logger.error "  - Backtrace: #{e.backtrace.join("\n")}"

      # Save error result
      error_result = {
        success: false,
        error_message: e.message,
        imported_count: 0,
        updated_count: 0,
        failed_count: 0,
        duplicate_count: 0,
        total_count: 0,
        csv_errors: [ e.message ]
      }

      result_file_path = Rails.root.join("tmp", "person_import_result_#{import_id}.json")
      File.write(result_file_path, error_result.to_json)

      raise # Re-raise to trigger Sidekiq retry logic
    ensure
      # Clean up the temporary file
      File.delete(temp_file_path) if File.exist?(temp_file_path)
    end
  end
end
