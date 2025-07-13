# frozen_string_literal: true

class PhantomBusterImportJob < ApplicationJob
  queue_as :imports
  
  # Batch size for processing records
  BATCH_SIZE = 100
  
  def perform(file_path, options = {})
    # Initialize service
    service = PhantomBusterImportService.new(file_path)
    
    # Validate file format
    unless service.detect_format
      notify_failure("Invalid file format", service.errors)
      return
    end
    
    # Process import
    success = service.import(options)
    
    if success
      notify_success(service.import_results)
    else
      notify_failure("Import failed", service.errors, service.import_results)
    end
    
    # Clean up temporary file if requested
    if options[:delete_after_import] && File.exist?(file_path)
      File.delete(file_path)
    end
  rescue StandardError => e
    notify_failure("Unexpected error: #{e.message}", [e.message])
    raise # Re-raise for Sidekiq retry
  end
  
  private
  
  def notify_success(results)
    # Log success
    Rails.logger.info "PhantomBusterImport completed: #{results}"
    
    # TODO: Send email notification or update UI via Turbo
    # For now, just log the results
    message = <<~MSG
      Phantom Buster Import Completed Successfully!
      
      Total Records: #{results[:total]}
      Successfully Imported: #{results[:successful]}
      Duplicates Skipped: #{results[:duplicates]}
      Failed: #{results[:failed]}
    MSG
    
    Rails.logger.info message
  end
  
  def notify_failure(reason, errors, partial_results = nil)
    Rails.logger.error "PhantomBusterImport failed: #{reason}"
    Rails.logger.error "Errors: #{errors.join(', ')}"
    
    if partial_results
      Rails.logger.error "Partial results: #{partial_results}"
    end
    
    # TODO: Send failure notification
  end
end