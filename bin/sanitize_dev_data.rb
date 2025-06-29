#!/usr/bin/env ruby

# Data Sanitization Script for Development Environment
# This script sanitizes sensitive data after syncing from production
# Run automatically by sync_production_data.sh

require 'securerandom'
require 'digest'

class DevDataSanitizer
  def initialize
    @log_file = Rails.root.join('log', 'sync', "sanitize_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    @log_file.dirname.mkpath
    @logger = Logger.new(@log_file)
    @logger.info "Starting data sanitization..."
  end

  def sanitize!
    ActiveRecord::Base.transaction do
      sanitize_users
      sanitize_api_keys
      sanitize_personal_data
      sanitize_communications
      update_environment_urls
      clear_sensitive_logs
    end
    
    @logger.info "Data sanitization completed successfully!"
  rescue => e
    @logger.error "Sanitization failed: #{e.message}"
    @logger.error e.backtrace.join("\n")
    raise
  end

  private

  def sanitize_users
    @logger.info "Sanitizing user data..."
    
    # Get test users from CLAUDE.local.md
    test_users = {
      'test@test.no' => 'CodemyFTW2',
      'admin@example.com' => 'CodemyFTW2'
    }
    
    # Generate a known password hash for development
    # This is the bcrypt hash for 'development123'
    dev_password_hash = '$2a$12$K2xPQbGQhXVLWszpQeGJ6.Gt8nFwKqYZcbMx8IG4u9O7hQxXyqFCa'
    
    User.find_each do |user|
      unless test_users.key?(user.email)
        # Set all non-test users to a known development password
        user.update_column(:encrypted_password, dev_password_hash)
        
        # Anonymize email but keep format
        username = "user#{user.id}"
        domain = user.email.split('@').last
        user.update_column(:email, "#{username}@#{domain}")
        
        # Clear OAuth tokens
        user.update_columns(
          provider: nil,
          uid: nil
        ) if user.oauth_user?
      end
      
      # Clear sensitive tracking data
      user.update_columns(
        current_sign_in_ip: nil,
        last_sign_in_ip: nil,
        reset_password_token: nil,
        reset_password_sent_at: nil
      )
    end
    
    @logger.info "Sanitized #{User.count} users"
  end

  def sanitize_api_keys
    @logger.info "Sanitizing API keys and tokens..."
    
    # Clear any API keys in service configurations
    ServiceConfiguration.find_each do |config|
      if config.settings.is_a?(Hash)
        sanitized_settings = config.settings.deep_dup
        
        # Remove any keys that look like API credentials
        %w[api_key api_token secret_key client_secret password token].each do |key|
          sanitized_settings.delete(key)
          sanitized_settings.delete(key.upcase)
          sanitized_settings.delete(key.downcase)
        end
        
        config.update_column(:settings, sanitized_settings)
      end
    end
    
    @logger.info "Sanitized service configurations"
  end

  def sanitize_personal_data
    @logger.info "Sanitizing personal data..."
    
    # Anonymize person records (keep structure but remove PII)
    Person.find_each.with_index do |person, index|
      person.update_columns(
        email: person.email.present? ? "person#{person.id}@example.com" : nil,
        phone: person.phone.present? ? "+1555000#{index.to_s.rjust(4, '0')}" : nil,
        profile_picture_url: nil,
        bio: person.bio.present? ? "Sample bio for testing purposes." : nil
      )
      
      # Clear sensitive data from JSON fields
      if person.linkedin_data.present?
        sanitized_data = person.linkedin_data.except('email', 'phone', 'personalEmail')
        person.update_column(:linkedin_data, sanitized_data)
      end
      
      if person.email_data.present?
        person.update_column(:email_data, { status: 'sanitized' })
      end
    end
    
    @logger.info "Sanitized #{Person.count} person records"
  end

  def sanitize_communications
    @logger.info "Sanitizing communications data..."
    
    # Anonymize email addresses in communications
    Communication.find_each do |comm|
      comm.update_columns(
        lead_email: comm.lead_email.present? ? "lead#{comm.id}@example.com" : nil,
        email_account: comm.email_account.present? ? "account#{comm.id}@example.com" : nil,
        phone: comm.phone.present? ? "+1555#{comm.id.to_s.rjust(7, '0')}" : nil
      )
    end
    
    @logger.info "Sanitized #{Communication.count} communication records"
  end

  def update_environment_urls
    @logger.info "Updating environment-specific URLs..."
    
    # Update any production URLs to development URLs
    Company.where("website LIKE ?", "%connectica.no%").find_each do |company|
      dev_url = company.website.gsub('connectica.no', 'local.connectica.no')
      company.update_column(:website, dev_url)
    end
    
    # Clear production webhook URLs
    Domain.where.not(web_content_data: nil).find_each do |domain|
      if domain.web_content_data.is_a?(Hash) && domain.web_content_data['webhook_url']
        sanitized_data = domain.web_content_data.except('webhook_url', 'api_endpoint')
        domain.update_column(:web_content_data, sanitized_data)
      end
    end
    
    @logger.info "Updated environment URLs"
  end

  def clear_sensitive_logs
    @logger.info "Clearing sensitive audit logs..."
    
    # Remove any audit logs with sensitive error messages
    ServiceAuditLog.where("error_message LIKE '%password%' OR error_message LIKE '%token%'").update_all(
      error_message: 'Error sanitized for development'
    )
    
    # Clear sensitive metadata
    ServiceAuditLog.where.not(metadata: nil).find_each do |log|
      if log.metadata.is_a?(Hash)
        sanitized_metadata = log.metadata.except('password', 'token', 'api_key', 'secret')
        log.update_column(:metadata, sanitized_metadata) if sanitized_metadata != log.metadata
      end
    end
    
    @logger.info "Cleared sensitive logs"
  end
end

# Run sanitization if called directly
if __FILE__ == $0
  puts "Running development data sanitization..."
  sanitizer = DevDataSanitizer.new
  sanitizer.sanitize!
  puts "Sanitization completed!"
end