# frozen_string_literal: true

class PersonImportJob < ApplicationJob
  queue_as :default

  def perform(temp_file_path, user_id, original_filename, import_id)
    Rails.logger.info "🚀 PersonImportJob started: #{import_id}"
    Rails.logger.info "  - File: #{temp_file_path}"
    Rails.logger.info "  - User ID: #{user_id}"
    Rails.logger.info "  - Original filename: #{original_filename}"

    begin
      user = User.find(user_id)

      # Create a file-like object for the service
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(temp_file_path),
        filename: original_filename,
        type: "text/csv"
      )

      # Run the import service
      service = PersonImportService.new(
        file: file,
        user: user
      )

      result = service.perform

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
