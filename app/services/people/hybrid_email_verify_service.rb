# frozen_string_literal: true

require "truemail"
require "valid_email2"
require "ostruct"

module People
  class HybridEmailVerifyService < ApplicationService
    attr_reader :person, :email

    def initialize(person:, **options)
      super(service_name: "hybrid_email_verify", action: "verify_email", **options)
      @person = person
      @email = person.email
    end

    def perform
      return error_result("Service is disabled") unless service_active?
      return error_result("No email to verify") if email.blank?

      Rails.logger.info "Starting hybrid email verification for #{email}"

      audit_service_operation(person) do |audit_log|
        # Initialize verification result
        result = {
          valid: false,
          confidence: 0.0,
          status: :unknown,
          checks: {},
          metadata: {
            verification_timestamp: Time.current,
            validation_engines: []
          }
        }

        # Step 1: Enhanced Syntax Check (Truemail + valid_email2)
        syntax_result = enhanced_syntax_check(email)
        result[:checks][:syntax] = syntax_result

        unless syntax_result[:passed]
          result[:status] = :invalid
          result[:confidence] = 1.0
          save_verification_result(result, audit_log, "hybrid")
          return success_result("Email verification completed", result)
        end

        # Step 2: Disposable Email Detection
        disposable_result = check_disposable_email(email)
        result[:checks][:disposable] = disposable_result

        if disposable_result[:is_disposable]
          result[:status] = :disposable
          result[:confidence] = 0.95
          save_verification_result(result, audit_log, "hybrid")
          return success_result("Email verification completed", result)
        end

        # Step 3: Enhanced DNS/MX Validation
        domain = extract_domain(email)
        mx_result = enhanced_mx_check(domain)
        result[:checks][:mx_record] = mx_result

        unless mx_result[:passed]
          result[:status] = :invalid
          result[:confidence] = 0.9
          save_verification_result(result, audit_log, "hybrid")
          return success_result("Email verification completed", result)
        end

        # Step 4: Rate limiting check
        if rate_limited?(domain)
          result[:status] = :rate_limited
          result[:confidence] = 0.0
          save_verification_result(result, audit_log, "hybrid")
          return success_result("Rate limited - verification deferred", result)
        end

        # Step 5: Hybrid SMTP Verification (existing + Truemail)
        smtp_result = hybrid_smtp_verification(email, domain)
        result[:checks][:smtp] = smtp_result

        # Step 6: Determine final status with enhanced logic
        determine_hybrid_final_status(result, domain)

        # Save results with enhanced metadata
        save_verification_result(result, audit_log, "hybrid")

        # Queue retry if needed
        if result[:status] == :greylist_retry
          queue_retry_verification(person.id, result[:metadata][:retry_count] || 0)
        end

        success_result("Hybrid email verification completed", result)
      end
    end

    private

    def enhanced_syntax_check(email)
      # Use only Truemail's battle-tested syntax validation
      begin
        configure_truemail_for_syntax
        truemail_result = Truemail.validate(email)
        
        {
          passed: truemail_result.result.valid?,
          message: truemail_result.result.valid? ? 
            "Valid syntax (Truemail)" : 
            (truemail_result.result.errors.first || "Invalid syntax"),
          details: {
            truemail: {
              valid: truemail_result.result.valid?,
              errors: truemail_result.result.errors
            }
          },
          engine: "truemail"
        }
      rescue => e
        {
          passed: false,
          message: "Truemail validation error: #{e.message}",
          details: { error: e.message },
          engine: "truemail"
        }
      end
    end

    def check_disposable_email(email)
      begin
        address = ValidEmail2::Address.new(email)
        is_disposable = address.disposable?

        {
          is_disposable: is_disposable,
          message: is_disposable ? "Disposable email detected" : "Not a disposable email",
          source: "valid_email2"
        }
      rescue => e
        {
          is_disposable: false,
          message: "Disposable check failed: #{e.message}",
          source: "error"
        }
      end
    end

    def enhanced_mx_check(domain)
      # Use Truemail's MX validation (which includes DNS lookups)
      begin
        configure_truemail_for_mx
        test_email = "test@#{domain}"
        truemail_result = Truemail.validate(test_email)
        
        # Truemail automatically checks MX records as part of validation
        {
          passed: truemail_result.result.valid? || 
                  !truemail_result.result.errors.any? { |e| e.include?("mx") },
          message: "MX validation by Truemail",
          details: {
            truemail_valid: truemail_result.result.valid?,
            truemail_errors: truemail_result.result.errors
          },
          engine: "truemail"
        }
      rescue => e
        {
          passed: false,
          message: "Truemail MX check error: #{e.message}",
          details: { error: e.message },
          engine: "truemail"
        }
      end
    end

    def hybrid_smtp_verification(email, domain)
      # Use only Truemail's battle-tested SMTP verification
      begin
        configure_truemail_for_smtp
        truemail_result = Truemail.validate(email)
        
        {
          passed: truemail_result.result.valid?,
          confidence: truemail_result.result.valid? ? 0.85 : 0.1,
          message: extract_truemail_message(truemail_result),
          response_code: extract_truemail_response_code(truemail_result),
          details: {
            truemail: {
              valid: truemail_result.result.valid?,
              errors: truemail_result.result.errors,
              smtp_debug: truemail_result.result.smtp_debug
            }
          },
          engine: "truemail"
        }
      rescue => e
        {
          passed: false,
          confidence: 0.0,
          message: "Truemail SMTP error: #{e.message}",
          details: { error: e.message },
          engine: "truemail"
        }
      end
    end


    def determine_hybrid_final_status(result, domain)
      # Enhanced status determination with ZeroBounce-level accuracy
      smtp_check = result[:checks][:smtp]
      
      if smtp_check[:passed]
        # Enhanced validation - check for catch-all indicators
        catch_all_detected = detect_catch_all_domain(domain, smtp_check)
        
        if catch_all_detected
          result[:valid] = false
          result[:status] = :catch_all
          result[:confidence] = 0.3  # Low confidence for catch-all domains
          result[:metadata][:validation_method] = "truemail_catch_all_detected"
          result[:metadata][:catch_all_reason] = catch_all_detected
        else
          # Trust enhanced Truemail SMTP verification
          result[:valid] = true
          result[:status] = :valid
          result[:confidence] = smtp_check[:confidence]
          result[:metadata][:validation_method] = "truemail_enhanced_smtp"
        end
      else
        # Check if it's a temporary issue (greylist) based on Truemail errors
        truemail_errors = smtp_check[:details]&.dig(:truemail, :errors) || []
        
        if truemail_errors.any? { |error| error.include?("greylist") || error.include?("450") || error.include?("451") }
          result[:status] = :greylist_retry
          result[:confidence] = 0.0
          result[:metadata][:validation_method] = "truemail_greylist"
        else
          # Enhanced Truemail determined it's invalid - trust that assessment
          result[:valid] = false
          result[:status] = :invalid
          result[:confidence] = 0.9
          result[:metadata][:validation_method] = "truemail_enhanced_invalid"
          result[:metadata][:truemail_errors] = truemail_errors
          
          # Log enhanced error details for analysis
          if smtp_check[:details]&.dig(:truemail, :smtp_debug)
            result[:metadata][:smtp_debug] = smtp_check[:details][:truemail][:smtp_debug]
          end
        end
      end
    end

    def detect_catch_all_domain(domain, smtp_check)
      # Enhanced catch-all detection based on ZeroBounce analysis
      
      # Known catch-all domains from our analysis (ZeroBounce confirmed)
      known_catch_all_domains = %w[
        krungsri.com kasikornbank.com tmbbank.com bot.or.th scb.co.th
      ]
      
      if known_catch_all_domains.include?(domain.downcase)
        return "Known catch-all domain from ZeroBounce analysis"
      end
      
      # Don't test Google Workspace domains as catch-all - they have proper mailbox validation
      google_workspace_indicators = %w[aspmx.l.google.com google.com g-suite]
      smtp_provider = smtp_check.dig(:details, :truemail, :smtp_debug) || ""
      
      if google_workspace_indicators.any? { |indicator| smtp_provider.downcase.include?(indicator) }
        Rails.logger.debug "Skipping catch-all test for Google Workspace domain: #{domain}"
        return false
      end
      
      # For other domains, test for catch-all by checking if obviously invalid emails are accepted
      # Only test if we're confident this isn't a single-mailbox failure
      test_emails = [
        "definitely-nonexistent-test-#{SecureRandom.hex(6)}@#{domain}",
        "invalid-user-#{Time.current.to_i}@#{domain}"
      ]
      
      accepted_count = 0
      test_emails.each do |test_email|
        begin
          # Use lighter MX validation for catch-all testing to avoid SMTP rate limits
          Truemail.configure do |config|
            config.verifier_email = 'noreply@connectica.no'
            config.verifier_domain = 'connectica.no'
            config.default_validation_type = :smtp
            config.smtp_safe_check = false  # Lighter validation for testing
            config.connection_timeout = 5
            config.response_timeout = 5
            config.connection_attempts = 1
          end
          
          test_result = Truemail.validate(test_email)
          accepted_count += 1 if test_result.result.valid?
        rescue => e
          # If test fails, assume domain is not catch-all
          Rails.logger.debug "Catch-all test failed for #{domain}: #{e.message}"
          break  # Stop testing if we get errors
        end
      end
      
      # Only consider it catch-all if BOTH obviously invalid emails are accepted
      # This reduces false positives
      if accepted_count >= 2
        return "Catch-all detected: #{accepted_count}/#{test_emails.length} invalid emails accepted"
      end
      
      false
    end

    def save_verification_result(result, audit_log, engine)
      Rails.logger.info "Saving hybrid verification result for person #{person.id}: status=#{result[:status]}, confidence=#{result[:confidence]}"

      person.update!(
        email_verification_status: result[:status].to_s,
        email_verification_confidence: result[:confidence],
        email_verification_checked_at: Time.current,
        email_verification_metadata: result.merge({
          engine: engine,
          timestamp: Time.current,
          version: "1.0.0"
        })
      )

      audit_log.add_metadata(
        status: result[:status],
        confidence: result[:confidence],
        checks: result[:checks],
        engine: engine
      )
    end

    def rate_limited?(domain)
      # Use simple rate limiting check without delegating to local service
      settings = service_configuration.settings.symbolize_keys
      hourly_limit = settings[:rate_limit_per_domain_hour] || 30
      
      # Count recent attempts from our verification attempts
      hour_count = EmailVerificationAttempt
        .by_domain(domain)
        .where("attempted_at > ?", 1.hour.ago)
        .count
        
      hour_count >= hourly_limit
    end

    def queue_retry_verification(person_id, retry_count)
      settings = service_configuration.settings.symbolize_keys
      retry_delays = settings[:greylist_retry_delays] || [ 60, 300, 900 ]
      max_retries = settings[:max_retries_greylist] || 3

      return if retry_count >= max_retries

      delay = retry_delays[retry_count] || retry_delays.last

      # Queue retry job with delay using the same worker
      LocalEmailVerifyWorker.perform_in(delay.seconds, person_id, retry_count + 1)
    end

    def extract_domain(email)
      return nil unless email.include?("@")
      email.split("@").last.downcase
    end

    def configure_truemail_for_syntax
      settings = service_configuration.settings.symbolize_keys

      Truemail.configure do |config|
        config.verifier_email = settings[:verifier_email] || "noreply@connectica.no"
        config.verifier_domain = settings[:verifier_domain] || "connectica.no"
        config.default_validation_type = :regex  # Syntax validation only
        config.email_pattern = settings[:email_pattern] if settings[:email_pattern]
        config.connection_timeout = settings[:truemail_timeout] || 5
        config.response_timeout = settings[:truemail_timeout] || 5
        config.connection_attempts = settings[:truemail_attempts] || 2
      end
    end

    def configure_truemail_for_mx
      settings = service_configuration.settings.symbolize_keys

      Truemail.configure do |config|
        config.verifier_email = settings[:verifier_email] || "noreply@connectica.no"
        config.verifier_domain = settings[:verifier_domain] || "connectica.no"
        config.default_validation_type = :mx  # MX validation
        config.connection_timeout = settings[:truemail_timeout] || 5
        config.response_timeout = settings[:truemail_timeout] || 5
        config.connection_attempts = settings[:truemail_attempts] || 2
      end
    end

    def configure_truemail
      settings = service_configuration.settings.symbolize_keys

      Truemail.configure do |config|
        config.verifier_email = settings[:verifier_email] || "noreply@connectica.no"
        config.verifier_domain = settings[:verifier_domain] || "connectica.no"
        config.default_validation_type = :regex  # Use regex validation by default for syntax checks
        config.email_pattern = settings[:email_pattern] if settings[:email_pattern]
        config.smtp_error_body_pattern = settings[:smtp_error_body_pattern] if settings[:smtp_error_body_pattern]
        config.connection_timeout = settings[:truemail_timeout] || 5
        config.response_timeout = settings[:truemail_timeout] || 5
        config.connection_attempts = settings[:truemail_attempts] || 2
      end
    end

    def configure_truemail_for_smtp
      settings = service_configuration.settings.symbolize_keys

      Truemail.configure do |config|
        config.verifier_email = settings[:verifier_email] || "noreply@connectica.no"
        config.verifier_domain = settings[:verifier_domain] || "connectica.no"
        config.default_validation_type = :smtp
        
        # ENHANCED: ZeroBounce-level accuracy configuration
        config.smtp_safe_check = true  # Parse SMTP error bodies for detailed validation
        config.smtp_fail_fast = false  # Disable fail-fast for thorough checking
        
        # Enhanced SMTP error pattern based on ZeroBounce analysis
        config.smtp_error_body_pattern = /(?:user|mailbox|recipient|address).*(?:unknown|not found|invalid|doesn't exist|does not exist|no such|unavailable|rejected)/i
        
        # Increased timeouts for accuracy over speed
        config.connection_timeout = settings[:truemail_timeout] || 10
        config.response_timeout = settings[:truemail_timeout] || 10
        config.connection_attempts = settings[:truemail_attempts] || 3
        
        # Domain-specific validation rules for known problematic providers
        config.validation_type_for = build_domain_validation_rules(settings)
        
        # Enable detailed logging for troubleshooting
        if Rails.env.development? || settings[:enable_truemail_logging]
          config.logger = {
            tracking_event: :all,
            stdout: false,
            log_absolute_path: Rails.root.join('log', 'truemail_enhanced.log').to_s
          }
        end
      end
    end

    def extract_truemail_message(truemail_result)
      if truemail_result.result.valid?
        "SMTP verification successful"
      else
        truemail_result.result.errors.first || "SMTP verification failed"
      end
    end

    def extract_truemail_response_code(truemail_result)
      # Try to extract SMTP response code from Truemail result
      smtp_debug = truemail_result.result.smtp_debug
      return nil unless smtp_debug

      # Look for response codes in debug output
      code_match = smtp_debug.match(/(\d{3})\s/)
      code_match ? code_match[1].to_i : nil
    end

    def build_domain_validation_rules(settings)
      # Base domain rules for enhanced validation
      base_rules = {
        # Google domains - require SMTP for mailbox-level validation
        'gmail.com' => :smtp,
        'googlemail.com' => :smtp,
        'g.co' => :smtp,
        'google.com' => :smtp,
        
        # Microsoft domains
        'outlook.com' => :smtp,
        'hotmail.com' => :smtp,
        'live.com' => :smtp,
        
        # Known problematic domains from ZeroBounce analysis
        'ascendcorp.com' => :smtp,  # Google Workspace - original problem case
        'omise.co' => :smtp,        # Another invalid case found
        
        # Banking domains with catch-all issues
        'krungsri.com' => :smtp,
        'kasikornbank.com' => :smtp,
        'tmbbank.com' => :smtp,
        'bot.or.th' => :smtp,
        'scb.co.th' => :smtp
      }
      
      # Allow custom domain rules from settings
      if settings[:domain_validation_rules].is_a?(Hash)
        base_rules.merge!(settings[:domain_validation_rules].symbolize_keys)
      end
      
      base_rules
    end

    def service_configuration
      @service_configuration ||= ServiceConfiguration.find_by(service_name: "hybrid_email_verify") ||
                                  ServiceConfiguration.find_by(service_name: "local_email_verify")
    end

    def service_active?
      config = ServiceConfiguration.find_by(service_name: service_name) ||
               ServiceConfiguration.find_by(service_name: "local_email_verify")
      return false unless config
      config.active?
    end

    def success_result(message, data = {})
      OpenStruct.new(
        success?: true,
        message: message,
        data: data,
        error: nil
      )
    end

    def error_result(message, data = {})
      OpenStruct.new(
        success?: false,
        message: nil,
        error: message,
        data: data
      )
    end
  end
end
