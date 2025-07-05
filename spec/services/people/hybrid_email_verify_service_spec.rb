# frozen_string_literal: true

require 'rails_helper'

RSpec.describe People::HybridEmailVerifyService do
  let(:person) { create(:person, email: email) }
  let(:email) { 'test@example.com' }
  let(:service) { described_class.new(person: person) }

  let(:service_config) do
    ServiceConfiguration.create!(
      service_name: 'hybrid_email_verify',
      active: true,
      settings: {
        validation_engine: "hybrid",
        validation_strictness: "high",
        enable_secondary_validation: true,
        enable_disposable_check: true,
        confidence_thresholds: {
          "valid" => 0.8,
          "suspect" => 0.4,
          "invalid" => 0.2
        },
        catch_all_treatment: "suspect",
        catch_all_confidence: 0.2,
        catch_all_domains: [ 'catchall.com' ],
        smtp_success_confidence: 0.7,
        smtp_timeout: 5,
        smtp_port: 25,
        helo_domain: 'test.com',
        mail_from: 'noreply@test.com',
        verifier_email: 'noreply@test.com',
        verifier_domain: 'test.com',
        truemail_timeout: 5,
        truemail_attempts: 2,
        rate_limit_per_domain_hour: 30,
        rate_limit_per_domain_day: 300,
        random_delay_min: 0,
        random_delay_max: 0,
        greylist_retry_delays: [ 60, 300, 900 ],
        max_retries_greylist: 3
      }
    )
  end

  before do
    service_config

    # Mock Truemail configuration
    allow(Truemail).to receive(:configure)
  end

  describe '#perform' do
    context 'when service is disabled' do
      before { service_config.update!(active: false) }

      it 'returns error result' do
        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to eq('Service is disabled')
      end
    end

    context 'when email is blank' do
      let(:email) { nil }

      it 'returns error result' do
        result = service.perform
        expect(result.success?).to be false
        expect(result.error).to eq('No email to verify')
      end
    end

    context 'with valid syntax checks' do
      let(:email) { 'valid@example.com' }

      before do
        # Mock successful syntax validation
        mock_truemail_result = double(
          result: double(
            valid?: true,
            errors: []
          )
        )
        allow(Truemail).to receive(:validate).with(email, validation_type: :regex).and_return(mock_truemail_result)

        # Mock valid_email2
        mock_address = double(valid?: true, disposable?: false, valid_mx?: true)
        allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)
      end

      context 'when email passes all syntax checks' do
        it 'proceeds to MX validation' do
          # Mock MX records
          allow_any_instance_of(described_class).to receive(:check_domain_mx).and_return({
            passed: true,
            mx_hosts: [ 'mx.example.com' ],
            source: 'fresh'
          })

          # Mock SMTP verification
          allow_any_instance_of(described_class).to receive(:verify_smtp_existing).and_return({
            passed: true,
            response_code: 250,
            message: 'OK'
          })

          # Mock Truemail SMTP
          mock_smtp_result = double(
            result: double(
              valid?: true,
              errors: [],
              smtp_debug: "250 OK"
            )
          )
          allow(Truemail).to receive(:validate).with(email, validation_type: :smtp).and_return(mock_smtp_result)

          # Mock rate limiting
          allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(false)
          allow_any_instance_of(described_class).to receive(:detect_catch_all_domain?).and_return(false)

          result = service.perform

          expect(result.success?).to be true
          expect(result.data[:status]).to eq(:valid)
          expect(result.data[:confidence]).to be > 0.6
          expect(result.data[:checks]).to have_key(:syntax)
          expect(result.data[:checks]).to have_key(:disposable)
          expect(result.data[:checks]).to have_key(:mx_record)
          expect(result.data[:checks]).to have_key(:smtp)
        end
      end

      context 'when disposable email is detected' do
        before do
          mock_address = double(valid?: true, disposable?: true)
          allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)
        end

        it 'marks email as disposable' do
          result = service.perform

          expect(result.success?).to be true
          expect(result.data[:status]).to eq(:disposable)
          expect(result.data[:confidence]).to eq(0.95)
          expect(result.data[:checks][:disposable][:is_disposable]).to be true
        end
      end

      context 'when catch-all domain is detected' do
        let(:email) { 'test@catchall.com' }

        before do
          # Mock MX records
          allow_any_instance_of(described_class).to receive(:check_domain_mx).and_return({
            passed: true,
            mx_hosts: [ 'mx.catchall.com' ],
            source: 'fresh'
          })

          # Mock SMTP success (but it's catch-all)
          allow_any_instance_of(described_class).to receive(:verify_smtp_existing).and_return({
            passed: true,
            response_code: 250,
            message: 'OK'
          })

          mock_smtp_result = double(
            result: double(
              valid?: true,
              errors: [],
              smtp_debug: "250 OK"
            )
          )
          allow(Truemail).to receive(:validate).with(email, validation_type: :smtp).and_return(mock_smtp_result)

          allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(false)
        end

        it 'marks email as catch-all with low confidence' do
          result = service.perform

          expect(result.success?).to be true
          expect(result.data[:status]).to eq(:catch_all)
          expect(result.data[:confidence]).to eq(0.2)
          expect(result.data[:metadata][:catch_all_suspected]).to be true
        end
      end

      context 'when engines disagree on SMTP validation' do
        before do
          # Mock MX records
          allow_any_instance_of(described_class).to receive(:check_domain_mx).and_return({
            passed: true,
            mx_hosts: [ 'mx.example.com' ],
            source: 'fresh'
          })

          # Mock disagreement: Truemail says valid, existing says invalid
          allow_any_instance_of(described_class).to receive(:verify_smtp_existing).and_return({
            passed: false,
            response_code: 550,
            message: 'Mailbox not found'
          })

          mock_smtp_result = double(
            result: double(
              valid?: true,
              errors: [],
              smtp_debug: "250 OK"
            )
          )
          allow(Truemail).to receive(:validate).with(email, validation_type: :smtp).and_return(mock_smtp_result)

          allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(false)
          allow_any_instance_of(described_class).to receive(:detect_catch_all_domain?).and_return(false)
        end

        it 'marks email as invalid due to disagreement' do
          result = service.perform

          expect(result.success?).to be true
          expect(result.data[:status]).to eq(:invalid)
          expect(result.data[:confidence]).to be > 0.3
        end
      end
    end

    context 'with invalid syntax' do
      let(:email) { 'invalid-email' }

      before do
        # Mock failed syntax validation
        mock_truemail_result = double(
          result: double(
            valid?: false,
            errors: [ 'Invalid email format' ]
          )
        )
        allow(Truemail).to receive(:validate).with(email, validation_type: :regex).and_return(mock_truemail_result)

        mock_address = double(valid?: false)
        allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)
      end

      it 'marks email as invalid with high confidence' do
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:status]).to eq(:invalid)
        expect(result.data[:confidence]).to eq(1.0)
        expect(result.data[:checks][:syntax][:passed]).to be false
      end
    end

    context 'when rate limited' do
      let(:email) { 'test@ratelimited.com' }

      before do
        # Mock successful syntax and disposable checks
        mock_truemail_result = double(
          result: double(
            valid?: true,
            errors: []
          )
        )
        allow(Truemail).to receive(:validate).with(email, validation_type: :regex).and_return(mock_truemail_result)

        mock_address = double(valid?: true, disposable?: false, valid_mx?: true)
        allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)

        # Mock MX records
        allow_any_instance_of(described_class).to receive(:check_domain_mx).and_return({
          passed: true,
          mx_hosts: [ 'mx.ratelimited.com' ],
          source: 'fresh'
        })

        # Mock rate limiting
        allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(true)
      end

      it 'defers verification due to rate limiting' do
        result = service.perform

        expect(result.success?).to be true
        expect(result.data[:status]).to eq(:rate_limited)
        expect(result.data[:confidence]).to eq(0.0)
      end
    end
  end

  describe '#enhanced_syntax_check' do
    let(:email) { 'test@example.com' }

    it 'validates with multiple engines' do
      # Mock Truemail
      mock_truemail_result = double(
        result: double(
          valid?: true,
          errors: [],
          smtp_debug: "250 OK"
        )
      )
      allow(Truemail).to receive(:validate).with(email, validation_type: :regex).and_return(mock_truemail_result)

      # Mock valid_email2
      mock_address = double(valid?: true)
      allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)

      result = service.send(:enhanced_syntax_check, email)

      expect(result[:passed]).to be true
      expect(result[:details]).to have_key(:truemail)
      expect(result[:details]).to have_key(:valid_email2)
      expect(result[:details]).to have_key(:rfc)
    end
  end

  describe '#check_disposable_email' do
    let(:email) { 'test@disposable.com' }

    it 'detects disposable emails' do
      mock_address = double(disposable?: true)
      allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)

      result = service.send(:check_disposable_email, email)

      expect(result[:is_disposable]).to be true
      expect(result[:source]).to eq('valid_email2')
    end
  end

  describe 'person model updates' do
    let(:email) { 'test@example.com' }

    before do
      # Mock all validations to pass
      mock_truemail_result = double(
        result: double(
          valid?: true,
          errors: [],
          smtp_debug: "250 OK"
        )
      )
      allow(Truemail).to receive(:validate).and_return(mock_truemail_result)

      mock_address = double(valid?: true, disposable?: false, valid_mx?: true)
      allow(ValidEmail2::Address).to receive(:new).and_return(mock_address)

      allow_any_instance_of(described_class).to receive(:check_domain_mx).and_return({
        passed: true,
        mx_hosts: [ 'mx.example.com' ],
        source: 'fresh'
      })

      allow_any_instance_of(described_class).to receive(:verify_smtp_existing).and_return({
        passed: true,
        response_code: 250,
        message: 'OK'
      })

      allow_any_instance_of(described_class).to receive(:rate_limited?).and_return(false)
      allow_any_instance_of(described_class).to receive(:detect_catch_all_domain?).and_return(false)
    end

    it 'updates person with hybrid validation results' do
      service.perform

      person.reload
      expect(person.email_verification_status).to eq('valid')
      expect(person.email_verification_confidence).to be > 0.5
      expect(person.email_verification_metadata).to have_key('engine')
      expect(person.email_verification_metadata['engine']).to eq('hybrid')
    end
  end
end
