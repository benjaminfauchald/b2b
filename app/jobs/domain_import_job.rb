class DomainImportJob < ApplicationJob
  queue_as :default

  def perform(file_path, user_id, original_filename, import_id)
    Rails.logger.info "🚀 BACKGROUND JOB: Starting domain import"
    Rails.logger.info "  - File path: #{file_path}"
    Rails.logger.info "  - User ID: #{user_id}"
    Rails.logger.info "  - Original filename: #{original_filename}"
    Rails.logger.info "  - Import ID: #{import_id}"

    user = User.find(user_id)

    # Create a file object for the service
    file = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(file_path),
      filename: original_filename,
      type: "text/csv"
    )

    # Store import status in cache
    Rails.cache.write("import_status_#{import_id}", {
      status: "processing",
      message: "Import started",
      started_at: Time.current
    }, expires_in: 1.hour)

    begin
      import_service = DomainImportService.new(
        file: file,
        user: user,
        import_id: import_id
      )

      result = import_service.perform

      # Store the result in cache for retrieval
      Rails.cache.write("import_result_#{import_id}", {
        status: "completed",
        success: result.success?,
        result: result,
        completed_at: Time.current
      }, expires_in: 1.hour)

      Rails.logger.info "🎉 BACKGROUND JOB: Import completed successfully"

    rescue => e
      Rails.logger.error "❌ BACKGROUND JOB: Import failed - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      Rails.cache.write("import_result_#{import_id}", {
        status: "failed",
        success: false,
        error: e.message,
        completed_at: Time.current
      }, expires_in: 1.hour)

      raise e
    ensure
      # Clean up the temporary file
      File.delete(file_path) if File.exist?(file_path)
    end
  end
end
