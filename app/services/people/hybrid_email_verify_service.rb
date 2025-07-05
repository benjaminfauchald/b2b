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
      results = {}

      # Check 1: Truemail syntax validation
      begin
        configure_truemail
        truemail_result = Truemail.validate(email)
        results[:truemail] = {
          valid: truemail_result.result.valid?,
          message: truemail_result.result.errors.any? ? truemail_result.result.errors.first : "Valid syntax"
        }
      rescue => e
        results[:truemail] = { valid: false, message: "Truemail error: #{e.message}" }
      end

      # Check 2: valid_email2 syntax validation
      begin
        address = ValidEmail2::Address.new(email)
        results[:valid_email2] = {
          valid: address.valid?,
          message: address.valid? ? "Valid syntax" : "Invalid syntax"
        }
      rescue => e
        results[:valid_email2] = { valid: false, message: "ValidEmail2 error: #{e.message}" }
      end

      # Check 3: Existing RFC validation as fallback
      email_regex = /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z/
      results[:rfc] = {
        valid: email.match?(email_regex),
        message: email.match?(email_regex) ? "Valid RFC syntax" : "Invalid RFC syntax"
      }

      # Consensus logic: majority (2 out of 3) must pass for syntax to be valid
      valid_count = results.values.count { |r| r[:valid] }
      majority_valid = valid_count >= 2

      {
        passed: majority_valid,
        message: majority_valid ? "Valid syntax (#{valid_count}/3 engines)" : "Invalid syntax detected (#{valid_count}/3 engines)",
        details: results,
        consensus_score: valid_count
      }
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
      # Use existing MX check but also cross-validate with valid_email2
      existing_result = check_domain_mx(domain)

      # Add valid_email2 MX validation
      begin
        address = ValidEmail2::Address.new("test@#{domain}")
        valid_email2_mx = address.valid_mx?

        existing_result[:valid_email2_mx] = valid_email2_mx
        existing_result[:consensus] = existing_result[:passed] && valid_email2_mx
      rescue => e
        existing_result[:valid_email2_mx] = false
        existing_result[:valid_email2_error] = e.message
        existing_result[:consensus] = existing_result[:passed]
      end

      existing_result
    end

    def hybrid_smtp_verification(email, domain)
      settings = service_configuration.settings.symbolize_keys

      results = {}

      # Try Truemail SMTP verification first
      begin
        configure_truemail_for_smtp
        truemail_result = Truemail.validate(email)
        results[:truemail] = {
          valid: truemail_result.result.valid?,
          confidence: truemail_result.result.valid? ? 0.8 : 0.1,
          message: extract_truemail_message(truemail_result),
          response_code: extract_truemail_response_code(truemail_result)
        }
      rescue => e
        results[:truemail] = {
          valid: false,
          confidence: 0.0,
          message: "Truemail SMTP error: #{e.message}",
          error: true
        }
      end

      # Fall back to existing SMTP verification for comparison
      existing_result = verify_smtp_existing(email, domain)
      results[:existing] = existing_result

      # Determine consensus
      determine_smtp_consensus(results)
    end

    def determine_smtp_consensus(results)
      truemail = results[:truemail]
      existing = results[:existing]

      # If both agree, use the result
      if truemail[:valid] == existing[:passed]
        return {
          passed: truemail[:valid],
          confidence: [ truemail[:confidence], 0.7 ].max,
          message: truemail[:valid] ? "SMTP verification passed (consensus)" : "SMTP verification failed (consensus)",
          consensus: true,
          details: results
        }
      end

      # If they disagree, trust Truemail (more sophisticated engine) but lower confidence
      if truemail[:valid] && !existing[:passed]
        {
          passed: true,
          confidence: [ truemail[:confidence] * 0.8, 0.6 ].min, # Reduce confidence but still pass
          message: "SMTP verification passed (Truemail trusted over local)",
          consensus: false,
          details: results,
          trusted_engine: "truemail"
        }
      elsif !truemail[:valid] && existing[:passed]
        {
          passed: false,
          confidence: 0.2,
          message: "SMTP verification failed (Truemail overrides local)",
          consensus: false,
          details: results,
          trusted_engine: "truemail"
        }
      else
        # Both failed - definite invalid
        {
          passed: false,
          confidence: 0.9,
          message: "SMTP verification failed (both engines)",
          consensus: true,
          details: results
        }
      end
    end

    def determine_hybrid_final_status(result, domain)
      settings = service_configuration.settings.symbolize_keys
      catch_all_domains = settings[:catch_all_domains] || []
      confidence_thresholds = settings[:confidence_thresholds] || {
        "valid" => 0.7,      # Lowered from 0.8 to be less strict
        "suspect" => 0.4,
        "invalid" => 0.2
      }

      smtp_check = result[:checks][:smtp]

      if smtp_check[:passed]
        # Check for catch-all domains - but be less aggressive
        if catch_all_domains.include?(domain)
          # Known problematic catch-all domains
          result[:valid] = false
          result[:status] = :catch_all
          result[:confidence] = settings[:catch_all_confidence] || 0.3
          result[:metadata][:catch_all_suspected] = true
          result[:metadata][:catch_all_reason] = "Known catch-all domain"
        elsif detect_catch_all_domain?(domain, domain) && is_suspicious_domain?(domain)
          # Only mark as catch-all if both catch-all AND suspicious
          result[:valid] = false
          result[:status] = :catch_all
          result[:confidence] = 0.3
          result[:metadata][:catch_all_suspected] = true
          result[:metadata][:catch_all_reason] = "Suspicious catch-all detected"
        else
          # Legitimate SMTP success - trust it even if catch-all
          result[:valid] = true
          result[:status] = :valid
          # Use consensus confidence but be more lenient
          result[:confidence] = [ smtp_check[:confidence], 0.8 ].min

          # Add note if catch-all but still valid
          if detect_catch_all_domain?(domain, domain)
            result[:metadata][:catch_all_noted] = true
            result[:metadata][:note] = "Catch-all domain but SMTP verified"
          end
        end
      elsif smtp_check[:details]&.[](:existing)&.[](:greylist)
        result[:status] = :greylist_retry
        result[:confidence] = 0.0
      elsif smtp_check[:details]&.[](:existing)&.[](:response_code) == 550
        result[:valid] = false
        result[:status] = :invalid
        result[:confidence] = 0.95
      else
        # Be less conservative - mark as valid with lower confidence if syntax passed
        if result[:checks][:syntax][:passed] && result[:checks][:mx_record][:passed]
          result[:valid] = true
          result[:status] = :valid
          result[:confidence] = 0.4  # Low but still valid
          result[:metadata][:reason] = "Syntax and MX valid, SMTP inconclusive"
        else
          result[:status] = :unknown
          result[:confidence] = 0.0
        end
      end
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

    # Delegate methods to existing service
    def check_domain_mx(domain)
      existing_service = People::LocalEmailVerifyService.new(person: person)
      existing_service.send(:check_domain_mx, domain)
    end

    def verify_smtp_existing(email, domain)
      existing_service = People::LocalEmailVerifyService.new(person: person)
      # Get MX hosts first
      mx_result = check_domain_mx(domain)
      return { passed: false, message: "No MX records" } unless mx_result[:passed]

      existing_service.send(:verify_smtp, email, domain, mx_result[:mx_hosts] || [])
    end

    def rate_limited?(domain)
      existing_service = People::LocalEmailVerifyService.new(person: person)
      existing_service.send(:rate_limited?, domain)
    end

    def detect_catch_all_domain?(domain, mx_host)
      existing_service = People::LocalEmailVerifyService.new(person: person)
      existing_service.send(:detect_catch_all_domain?, domain, mx_host)
    end

    def queue_retry_verification(person_id, retry_count)
      existing_service = People::LocalEmailVerifyService.new(person: person)
      existing_service.send(:queue_retry_verification, person_id, retry_count)
    end

    def extract_domain(email)
      return nil unless email.include?("@")
      email.split("@").last.downcase
    end

    def is_suspicious_domain?(domain)
      # Consider domains suspicious if they appear to be temporary or spam-friendly
      suspicious_patterns = [
        /^\d+\.\d+\.\d+\.\d+$/, # IP addresses
        /^.{1,3}\.(com|net|org)$/, # Very short domains
        /temp|disposable|fake|test|spam/i, # Obviously temporary
        /^[a-z]{1,3}[0-9]+\./i # Short random domains like abc123.com
      ]

      suspicious_patterns.any? { |pattern| domain.match?(pattern) }
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
        config.default_validation_type = :smtp  # Use SMTP validation for email verification
        config.email_pattern = settings[:email_pattern] if settings[:email_pattern]
        config.smtp_error_body_pattern = settings[:smtp_error_body_pattern] if settings[:smtp_error_body_pattern]
        config.connection_timeout = settings[:truemail_timeout] || 5
        config.response_timeout = settings[:truemail_timeout] || 5
        config.connection_attempts = settings[:truemail_attempts] || 2
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
