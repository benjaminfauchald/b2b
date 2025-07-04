# frozen_string_literal: true

require "net/smtp"
require "resolv"
require "timeout"
require "ostruct"

module People
  class LocalEmailVerifyService < ApplicationService
    attr_reader :person, :email

    def initialize(person:, **options)
      super(service_name: "local_email_verify", action: "verify_email", **options)
      @person = person
      @email = person.email
    end

    def perform
      return error_result("Service is disabled") unless service_active?
      return error_result("No email to verify") if email.blank?

      Rails.logger.info "Starting email verification for #{email}"

      # For invalid email format without domain
      domain = extract_domain(email)
      unless domain
        result = {
          valid: false,
          confidence: 1.0,
          status: :invalid,
          checks: {
            syntax: { passed: false, message: "Invalid email format - no domain" }
          },
          metadata: {
            catch_all_suspected: false,
            retry_count: 0,
            verification_timestamp: Time.current
          }
        }

        person.update!(
          email_verification_status: "invalid",
          email_verification_confidence: 1.0,
          email_verification_checked_at: Time.current,
          email_verification_metadata: result
        )

        return success_result("Email verification completed", result)
      end

      audit_service_operation(person) do |audit_log|
        # Initialize verification result
        result = {
          valid: false,
          confidence: 0.0,
          status: :unknown,
          checks: {},
          metadata: {
            catch_all_suspected: false,
            retry_count: 0,
            verification_timestamp: Time.current
          }
        }

        # Step 1: RFC Syntax Check
        syntax_result = check_syntax(email)
        result[:checks][:syntax] = syntax_result

        unless syntax_result[:passed]
          result[:status] = :invalid
          result[:confidence] = 1.0
          save_verification_result(result, audit_log)
          return success_result("Email verification completed", result)
        end

        # Step 2: Domain and MX Record Check
        domain_result = check_domain_mx(domain)
        result[:checks][:mx_record] = domain_result

        unless domain_result[:passed]
          result[:status] = :invalid
          result[:confidence] = 0.9
          save_verification_result(result, audit_log)
          return success_result("Email verification completed", result)
        end

        # Check rate limits before SMTP verification
        if rate_limited?(domain)
          result[:status] = :rate_limited
          result[:confidence] = 0.0
          save_verification_result(result, audit_log)
          return success_result("Rate limited - verification deferred", result)
        end

        # Add random delay to avoid detection
        sleep_random_delay

        # Step 3: SMTP Verification
        smtp_result = verify_smtp(email, domain, domain_result[:mx_hosts])
        result[:checks][:smtp] = smtp_result

        # Determine final status and confidence
        determine_final_status(result, domain)

        # Save results
        save_verification_result(result, audit_log)

        # Queue retry if greylisted
        if result[:status] == :greylist_retry
          queue_retry_verification(person.id, result[:metadata][:retry_count])
        end

        success_result("Email verification completed", result)
      end
    end

    private

    def check_syntax(email)
      # RFC 5322 compliant email regex
      email_regex = /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z/

      if email.match?(email_regex)
        { passed: true, message: "Valid RFC syntax" }
      else
        { passed: false, message: "Invalid email syntax" }
      end
    end

    def check_domain_mx(domain)
      # First check if domain exists in our database
      domain_record = Domain.find_by(domain: domain)

      if domain_record && !domain_record.mx.nil?
        # Use cached MX results
        if domain_record.mx
          mx_hosts = extract_mx_hosts_from_metadata(domain_record)
          return { passed: true, mx_hosts: mx_hosts, source: "cached" }
        else
          return { passed: false, message: "No MX records found (cached)", source: "cached" }
        end
      end

      # Perform fresh MX lookup
      begin
        mx_records = Resolv::DNS.open do |dns|
          dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
        end

        if mx_records.any?
          mx_hosts = mx_records.sort_by(&:preference).map { |mx| mx.exchange.to_s }

          # Queue domain tests to cache results
          queue_domain_tests(domain)

          { passed: true, mx_hosts: mx_hosts, source: "fresh" }
        else
          { passed: false, message: "No MX records found", source: "fresh" }
        end
      rescue StandardError => e
        { passed: false, message: "DNS lookup failed: #{e.message}", source: "error" }
      end
    end

    def verify_smtp(email, domain, mx_hosts)
      settings = service_configuration.settings.symbolize_keys
      smtp_timeout = settings[:smtp_timeout] || 10
      smtp_port = settings[:smtp_port] || 25
      helo_domain = settings[:helo_domain] || "connectica.no"
      mail_from = settings[:mail_from] || "noreply@connectica.no"

      mx_hosts.each_with_index do |mx_host, index|
        begin
          response_code = nil
          response_message = nil

          Timeout.timeout(smtp_timeout) do
            Net::SMTP.start(mx_host, smtp_port, helo_domain) do |smtp|
              # Send MAIL FROM
              smtp.mailfrom(mail_from)

              # Send RCPT TO and capture response
              begin
                smtp.rcptto(email)
                response_code = 250
                response_message = "OK"
              rescue Net::SMTPFatalError => e
                response_code = e.response&.code&.to_i || 550
                response_message = e.response&.message || e.message
              rescue Net::SMTPServerBusy => e
                response_code = e.response&.code&.to_i || 450
                response_message = e.response&.message || e.message
              end
            end
          end

          # Log attempt
          log_verification_attempt(email, domain, response_code, response_message)

          # Interpret response
          case response_code
          when 250
            return { passed: true, response_code: response_code, message: response_message, mx_host: mx_host }
          when 450, 451, 452
            return { passed: false, response_code: response_code, message: "Greylisted: #{response_message}", greylist: true, mx_host: mx_host }
          when 550, 551, 553
            return { passed: false, response_code: response_code, message: "Mailbox not found: #{response_message}", mx_host: mx_host }
          else
            # Try next MX host
            next if index < mx_hosts.length - 1
            return { passed: false, response_code: response_code, message: response_message, mx_host: mx_host }
          end

        rescue Timeout::Error
          next if index < mx_hosts.length - 1
          return { passed: false, message: "SMTP timeout", timeout: true, mx_host: mx_host }
        rescue StandardError => e
          Rails.logger.error "SMTP verification error for #{mx_host}: #{e.message}"
          next if index < mx_hosts.length - 1
          return { passed: false, message: "SMTP error: #{e.message}", error: true, mx_host: mx_host }
        end
      end

      { passed: false, message: "All MX hosts failed" }
    end

    def determine_final_status(result, domain)
      settings = service_configuration.settings.symbolize_keys
      catch_all_domains = settings[:catch_all_domains] || []

      smtp_check = result[:checks][:smtp]

      if smtp_check[:passed]
        # Check if it's a known catch-all domain or if we should test it
        if catch_all_domains.include?(domain)
          result[:valid] = false
          result[:status] = :catch_all
          result[:confidence] = settings[:catch_all_confidence] || 0.2
          result[:metadata][:catch_all_suspected] = true
          result[:metadata][:catch_all_reason] = "Known catch-all domain"
        elsif detect_catch_all_domain?(domain, smtp_check[:mx_host])
          # Detected as catch-all, add to configuration
          add_to_catch_all_domains(domain)
          result[:valid] = false
          result[:status] = :catch_all
          result[:confidence] = settings[:catch_all_confidence] || 0.2
          result[:metadata][:catch_all_suspected] = true
          result[:metadata][:catch_all_detected] = true
          result[:metadata][:catch_all_reason] = "Dynamically detected catch-all domain"
        else
          # Legitimate SMTP success
          result[:valid] = true
          result[:status] = :valid
          result[:confidence] = settings[:smtp_success_confidence] || 0.7  # Lowered from 0.95
        end
      elsif smtp_check[:greylist]
        result[:status] = :greylist_retry
        result[:confidence] = 0.0
      elsif smtp_check[:response_code] == 550
        result[:valid] = false
        result[:status] = :invalid
        result[:confidence] = 0.95
      elsif smtp_check[:timeout]
        result[:status] = :timeout
        result[:confidence] = 0.0
      else
        result[:status] = :unknown
        result[:confidence] = 0.0
      end
    end

    def save_verification_result(result, audit_log)
      Rails.logger.info "Saving verification result for person #{person.id}: status=#{result[:status]}, confidence=#{result[:confidence]}"

      person.update!(
        email_verification_status: result[:status].to_s,
        email_verification_confidence: result[:confidence],
        email_verification_checked_at: Time.current,
        email_verification_metadata: result
      )

      Rails.logger.info "Person #{person.id} updated successfully. New status: #{person.reload.email_verification_status}"

      audit_log.add_metadata(
        status: result[:status],
        confidence: result[:confidence],
        checks: result[:checks]
      )
    end

    def log_verification_attempt(email, domain, response_code, response_message)
      EmailVerificationAttempt.create!(
        person: person,
        email: email,
        domain: domain,
        status: determine_attempt_status(response_code),
        response_code: response_code,
        response_message: response_message,
        attempted_at: Time.current
      )
    end

    def determine_attempt_status(response_code)
      case response_code
      when 250
        EmailVerificationAttempt::STATUSES[:success]
      when 450, 451, 452
        EmailVerificationAttempt::STATUSES[:greylist_retry]
      when 550, 551, 553
        EmailVerificationAttempt::STATUSES[:mailbox_not_found]
      else
        EmailVerificationAttempt::STATUSES[:smtp_failure]
      end
    end

    def extract_domain(email)
      return nil unless email.include?("@")
      email.split("@").last.downcase
    end

    def extract_mx_hosts_from_metadata(domain_record)
      # This would need to be implemented based on how MX records are stored
      # For now, return empty array
      []
    end

    def queue_domain_tests(domain)
      # Find or create domain record
      domain_record = Domain.find_or_create_by(domain: domain)

      if domain_record.needs_testing?
        DomainDnsTestingWorker.perform_async(domain_record.id)
      end
    end

    def rate_limited?(domain)
      settings = service_configuration.settings.symbolize_keys
      hourly_limit = settings[:rate_limit_per_domain_hour] || 50
      daily_limit = settings[:rate_limit_per_domain_day] || 500

      # Count recent attempts
      hour_count = EmailVerificationAttempt
        .by_domain(domain)
        .where("attempted_at > ?", 1.hour.ago)
        .count

      day_count = EmailVerificationAttempt
        .by_domain(domain)
        .where("attempted_at > ?", 1.day.ago)
        .count

      hour_count >= hourly_limit || day_count >= daily_limit
    end

    def sleep_random_delay
      settings = service_configuration.settings.symbolize_keys
      min_delay = settings[:random_delay_min] || 1
      max_delay = settings[:random_delay_max] || 5

      sleep(rand(min_delay..max_delay))
    end

    def queue_retry_verification(person_id, retry_count)
      settings = service_configuration.settings.symbolize_keys
      retry_delays = settings[:greylist_retry_delays] || [ 60, 300, 900 ]
      max_retries = settings[:max_retries_greylist] || 3

      return if retry_count >= max_retries

      delay = retry_delays[retry_count] || retry_delays.last

      # Queue retry job with delay
      LocalEmailVerifyWorker.perform_in(delay.seconds, person_id, retry_count + 1)
    end

    def service_configuration
      @service_configuration ||= ServiceConfiguration.find_by(service_name: "local_email_verify")
    end

    def service_active?
      config = ServiceConfiguration.find_by(service_name: service_name)
      return false unless config
      config.active?
    end

    def detect_catch_all_domain?(domain, mx_host)
      settings = service_configuration.settings.symbolize_keys

      # Skip detection for already known catch-all domains
      return false if (settings[:catch_all_domains] || []).include?(domain)

      # Generate a random test email
      test_email = "test_#{SecureRandom.hex(8)}_#{Time.now.to_i}@#{domain}"

      begin
        Timeout.timeout(5) do
          Net::SMTP.start(mx_host, 25, settings[:helo_domain] || "connectica.no") do |smtp|
            smtp.mailfrom(settings[:mail_from] || "noreply@connectica.no")

            begin
              smtp.rcptto(test_email)
              # If random email is accepted, it's a catch-all
              Rails.logger.info "Detected catch-all domain: #{domain} (accepted #{test_email})"
              return true
            rescue Net::SMTPFatalError => e
              # If random email is rejected, it's not a catch-all
              return false
            end
          end
        end
      rescue => e
        Rails.logger.warn "Catch-all detection failed for #{domain}: #{e.message}"
        # If detection fails, assume not catch-all
        false
      end
    end

    def add_to_catch_all_domains(domain)
      config = service_configuration
      settings = config.settings
      catch_all_domains = settings["catch_all_domains"] || []

      unless catch_all_domains.include?(domain)
        catch_all_domains << domain
        settings["catch_all_domains"] = catch_all_domains
        config.update!(settings: settings)
        Rails.logger.info "Added #{domain} to catch-all domains list"
      end
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
