# frozen_string_literal: true

require 'rails_helper'

RSpec.describe People::LocalEmailVerifyService do
  let(:person) { create(:person, email: email) }
  let(:email) { 'test@example.com' }
  let(:service) { described_class.new(person: person) }

  let(:service_config) do
    ServiceConfiguration.create!(
      service_name: 'local_email_verify',
      active: true,
      settings: {
        smtp_timeout: 5,
        smtp_port: 25,
        helo_domain: 'test.com',
        mail_from: 'noreply@test.com',
        catch_all_domains: [ 'gmail.com' ],
        catch_all_confidence: 0.5,
        rate_limit_per_domain_hour: 50,
        rate_limit_per_domain_day: 500,
        random_delay_min: 0,
        random_delay_max: 0,
        greylist_retry_delays: [ 60, 300, 900 ],
        max_retries_greylist: 3
      }
    )
  end

  before do
    service_config
    allow_any_instance_of(described_class).to receive(:sleep_random_delay)
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

    context 'with invalid email syntax' do
      let(:email) { 'invalid.email' }

      it 'marks email as invalid with high confidence' do
        result = service.perform
        expect(result.success?).to be true

        person.reload
        expect(person.email_verification_status).to eq('invalid')
        expect(person.email_verification_confidence).to eq(1.0)

        data = result.data
        expect(data[:status]).to eq(:invalid)
        expect(data[:checks][:syntax][:passed]).to be false
      end
    end

    context 'with valid syntax but no MX records' do
      let(:email) { 'test@no-mx-domain.test' }

      before do
        allow(Resolv::DNS).to receive(:open).and_yield(dns_mock)
        allow(dns_mock).to receive(:getresources).and_return([])
      end

      let(:dns_mock) { instance_double(Resolv::DNS) }

      it 'marks email as invalid due to missing MX records' do
        result = service.perform
        expect(result.success?).to be true

        person.reload
        expect(person.email_verification_status).to eq('invalid')
        expect(person.email_verification_confidence).to eq(0.9)

        data = result.data
        expect(data[:checks][:mx_record][:passed]).to be false
      end
    end

    context 'with cached domain MX records' do
      let(:domain) { create(:domain, domain: 'example.com', mx: true) }

      before do
        domain # ensure it exists
      end

      it 'uses cached MX results' do
        expect(Resolv::DNS).not_to receive(:open)

        # Mock SMTP verification
        smtp_mock = instance_double(Net::SMTP)
        allow(Net::SMTP).to receive(:start).and_yield(smtp_mock)
        allow(smtp_mock).to receive(:mailfrom)
        allow(smtp_mock).to receive(:rcptto)

        result = service.perform
        expect(result.success?).to be true

        data = result.data
        expect(data[:checks][:mx_record][:source]).to eq('cached')
      end
    end

    context 'SMTP verification' do
      before do
        allow(Resolv::DNS).to receive(:open).and_yield(dns_mock)
        allow(dns_mock).to receive(:getresources).and_return([ mx_record ])
      end

      let(:dns_mock) { instance_double(Resolv::DNS) }
      let(:mx_record) { instance_double(Resolv::DNS::Resource::IN::MX, preference: 10, exchange: 'mail.example.com') }

      context 'successful verification (250 response)' do
        before do
          smtp_mock = instance_double(Net::SMTP)
          allow(Net::SMTP).to receive(:start).and_yield(smtp_mock)
          allow(smtp_mock).to receive(:mailfrom)
          allow(smtp_mock).to receive(:rcptto)
        end

        it 'marks email as valid' do
          result = service.perform
          expect(result.success?).to be true

          person.reload
          expect(person.email_verification_status).to eq('valid')
          expect(person.email_verification_confidence).to eq(0.95)

          data = result.data
          expect(data[:valid]).to be true
          expect(data[:status]).to eq(:valid)
          expect(data[:checks][:smtp][:passed]).to be true
          expect(data[:checks][:smtp][:response_code]).to eq(250)
        end

        it 'creates verification attempt record' do
          expect { service.perform }.to change { EmailVerificationAttempt.count }.by(1)

          attempt = EmailVerificationAttempt.last
          expect(attempt.person).to eq(person)
          expect(attempt.email).to eq(email)
          expect(attempt.domain).to eq('example.com')
          expect(attempt.status).to eq('success')
          expect(attempt.response_code).to eq(250)
        end
      end

      context 'mailbox not found (550 response)' do
        before do
          smtp_mock = instance_double(Net::SMTP)
          allow(Net::SMTP).to receive(:start).and_yield(smtp_mock)
          allow(smtp_mock).to receive(:mailfrom)
          allow(smtp_mock).to receive(:rcptto).and_raise(
            Net::SMTPFatalError.new('550 5.1.1 User unknown')
          )
        end

        it 'marks email as invalid' do
          result = service.perform
          expect(result.success?).to be true

          person.reload
          expect(person.email_verification_status).to eq('invalid')
          expect(person.email_verification_confidence).to eq(0.95)

          data = result.data
          expect(data[:valid]).to be false
          expect(data[:status]).to eq(:invalid)
        end
      end

      context 'greylisting (450 response)' do
        before do
          smtp_mock = instance_double(Net::SMTP)
          allow(Net::SMTP).to receive(:start).and_yield(smtp_mock)
          allow(smtp_mock).to receive(:mailfrom)
          allow(smtp_mock).to receive(:rcptto).and_raise(
            Net::SMTPServerBusy.new('450 4.7.1 Greylisted, please try again later')
          )

          allow(LocalEmailVerifyWorker).to receive(:perform_in)
        end

        it 'marks email for retry' do
          result = service.perform
          expect(result.success?).to be true

          person.reload
          expect(person.email_verification_status).to eq('greylist_retry')
          expect(person.email_verification_confidence).to eq(0.0)

          data = result.data
          expect(data[:status]).to eq(:greylist_retry)
          expect(data[:checks][:smtp][:greylist]).to be true
        end

        it 'queues retry job' do
          expect(LocalEmailVerifyWorker).to receive(:perform_in).with(60, person.id, 1)
          service.perform
        end
      end

      context 'SMTP timeout' do
        before do
          allow(Net::SMTP).to receive(:start).and_raise(Timeout::Error)
        end

        it 'handles timeout gracefully' do
          result = service.perform
          expect(result.success?).to be true

          person.reload
          expect(person.email_verification_status).to eq('timeout')

          data = result.data
          expect(data[:status]).to eq(:timeout)
          expect(data[:checks][:smtp][:timeout]).to be true
        end
      end
    end

    context 'catch-all domain detection' do
      let(:email) { 'test@gmail.com' }

      before do
        allow(Resolv::DNS).to receive(:open).and_yield(dns_mock)
        allow(dns_mock).to receive(:getresources).and_return([ mx_record ])

        smtp_mock = instance_double(Net::SMTP)
        allow(Net::SMTP).to receive(:start).and_yield(smtp_mock)
        allow(smtp_mock).to receive(:mailfrom)
        allow(smtp_mock).to receive(:rcptto)
      end

      let(:dns_mock) { instance_double(Resolv::DNS) }
      let(:mx_record) { instance_double(Resolv::DNS::Resource::IN::MX, preference: 10, exchange: 'gmail-smtp-in.l.google.com') }

      it 'reduces confidence for catch-all domains' do
        result = service.perform
        expect(result.success?).to be true

        person.reload
        expect(person.email_verification_status).to eq('valid')
        expect(person.email_verification_confidence).to eq(0.5)

        data = result.data
        expect(data[:metadata][:catch_all_suspected]).to be true
      end
    end

    context 'rate limiting' do
      let(:domain) { 'example.com' }

      before do
        # Create 50 recent attempts to trigger hourly limit
        50.times do
          EmailVerificationAttempt.create!(
            person: create(:person),
            email: "test#{rand(1000)}@#{domain}",
            domain: domain,
            status: 'success',
            response_code: 250,
            attempted_at: 30.minutes.ago
          )
        end
      end

      it 'respects rate limits' do
        result = service.perform
        expect(result.success?).to be true

        person.reload
        expect(person.email_verification_status).to eq('rate_limited')

        data = result.data
        expect(data[:status]).to eq(:rate_limited)
      end
    end

    context 'multiple MX hosts' do
      before do
        allow(Resolv::DNS).to receive(:open).and_yield(dns_mock)
        allow(dns_mock).to receive(:getresources).and_return([ mx_record1, mx_record2 ])
      end

      let(:dns_mock) { instance_double(Resolv::DNS) }
      let(:mx_record1) { instance_double(Resolv::DNS::Resource::IN::MX, preference: 10, exchange: 'mail1.example.com') }
      let(:mx_record2) { instance_double(Resolv::DNS::Resource::IN::MX, preference: 20, exchange: 'mail2.example.com') }

      it 'tries secondary MX if primary fails' do
        smtp_mock1 = instance_double(Net::SMTP)
        smtp_mock2 = instance_double(Net::SMTP)

        # First MX fails
        allow(Net::SMTP).to receive(:start).with('mail1.example.com', anything, anything).and_raise(StandardError)

        # Second MX succeeds
        allow(Net::SMTP).to receive(:start).with('mail2.example.com', anything, anything).and_yield(smtp_mock2)
        allow(smtp_mock2).to receive(:mailfrom)
        allow(smtp_mock2).to receive(:rcptto)

        result = service.perform
        expect(result.success?).to be true

        person.reload
        expect(person.email_verification_status).to eq('valid')
      end
    end
  end
end
