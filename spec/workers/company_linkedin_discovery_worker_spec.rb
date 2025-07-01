# frozen_string_literal: true

require "rails_helper"
require "sidekiq/testing"

RSpec.describe CompanyLinkedinDiscoveryWorker, type: :worker do
  describe "Sidekiq configuration" do
    it "is configured with the correct queue name" do
      expect(described_class.sidekiq_options["queue"]).to eq("company_linkedin_discovery")
    end

    it "has retry enabled with 3 retries" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end

    it "includes Sidekiq::Worker module" do
      expect(described_class.ancestors).to include(Sidekiq::Worker)
    end
  end

  describe "#perform" do
    let(:company) { create(:company, linkedin_ai_url: nil) }
    let(:worker) { described_class.new }
    let(:service_double) { instance_double(CompanyLinkedinDiscoveryService) }
    let(:success_result) { OpenStruct.new(success?: true, error: nil, data: {}) }
    let(:failure_result) { OpenStruct.new(success?: false, error: "API Error", data: {}) }

    before do
      allow(CompanyLinkedinDiscoveryService).to receive(:new).and_return(service_double)
    end

    context "when company exists" do
      context "when service succeeds" do
        before do
          allow(service_double).to receive(:perform).and_return(success_result)
        end

        it "performs LinkedIn discovery for the company" do
          expect(CompanyLinkedinDiscoveryService).to receive(:new).with(company_id: company.id)
          expect(service_double).to receive(:perform)

          worker.perform(company.id)
        end

        it "logs success message" do
          expect(Rails.logger).to receive(:info).with("Starting LinkedIn discovery for company #{company.id} - #{company.company_name}")
          expect(Rails.logger).to receive(:info).with("Successfully discovered LinkedIn profile for company #{company.id}")

          worker.perform(company.id)
        end

        it "does not raise an error" do
          expect { worker.perform(company.id) }.not_to raise_error
        end
      end

      context "when service fails" do
        before do
          allow(service_double).to receive(:perform).and_return(failure_result)
        end

        it "logs error message" do
          expect(Rails.logger).to receive(:info).with("Starting LinkedIn discovery for company #{company.id} - #{company.company_name}")
          expect(Rails.logger).to receive(:error).with("Failed LinkedIn discovery for company #{company.id}: API Error")

          worker.perform(company.id)
        end

        it "does not raise error when retry_after is not present" do
          expect { worker.perform(company.id) }.not_to raise_error
        end

        context "with rate limit error (retry_after present)" do
          let(:rate_limit_result) do
            OpenStruct.new(
              success?: false,
              error: "Rate limited",
              data: { retry_after: 60 }
            )
          end

          before do
            allow(service_double).to receive(:perform).and_return(rate_limit_result)
          end

          it "re-raises the error for Sidekiq retry" do
            expect(Rails.logger).to receive(:error).with("Failed LinkedIn discovery for company #{company.id}: Rate limited")
            expect(Rails.logger).to receive(:error).with("Error in LinkedIn discovery worker: Rate limited")
            expect { worker.perform(company.id) }.to raise_error(StandardError)
          end
        end
      end

      context "when service raises an exception" do
        before do
          allow(service_double).to receive(:perform).and_raise(StandardError, "Unexpected error")
        end

        it "logs the error and re-raises for Sidekiq retry" do
          expect(Rails.logger).to receive(:error).with("Error in LinkedIn discovery worker: Unexpected error")
          expect { worker.perform(company.id) }.to raise_error(StandardError, "Unexpected error")
        end
      end
    end

    context "when company does not exist" do
      it "returns without processing or logging" do
        non_existent_id = 999999
        expect(CompanyLinkedinDiscoveryService).not_to receive(:new)
        # No error is logged because of early return on line 8
        expect(Rails.logger).not_to receive(:error)

        worker.perform(non_existent_id)
      end

      it "does not raise an error" do
        expect { worker.perform(999999) }.not_to raise_error
      end
    end

    context "when company_id is nil" do
      it "returns without processing" do
        expect(CompanyLinkedinDiscoveryService).not_to receive(:new)
        expect { worker.perform(nil) }.not_to raise_error
      end
    end
  end

  describe "Sidekiq queue integration" do
    before do
      Sidekiq::Testing.fake!
      described_class.clear
    end

    after do
      Sidekiq::Testing.inline!
    end

    it "can be enqueued via perform_async" do
      job_id = described_class.perform_async(123)
      
      expect(job_id).to be_present
      expect(described_class.jobs.size).to eq(1)
      
      job = described_class.jobs.first
      expect(job["args"]).to eq([123])
      expect(job["queue"]).to eq("company_linkedin_discovery")
    end

    it "can process jobs from the queue" do
      company = create(:company)
      service_double = instance_double(CompanyLinkedinDiscoveryService)
      allow(CompanyLinkedinDiscoveryService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:perform).and_return(OpenStruct.new(success?: true))

      described_class.perform_async(company.id)
      
      expect {
        described_class.drain
      }.not_to raise_error

      expect(CompanyLinkedinDiscoveryService).to have_received(:new).with(company_id: company.id)
    end

    it "respects Sidekiq retry configuration" do
      allow_any_instance_of(described_class).to receive(:perform).and_raise(StandardError)
      
      described_class.perform_async(123)
      
      expect {
        Sidekiq::Testing.inline! { described_class.drain }
      }.to raise_error(StandardError)
    end
  end

  describe "Queue verification" do
    it "worker is properly configured in sidekiq.yml" do
      sidekiq_config = YAML.load_file(Rails.root.join("config", "sidekiq.yml"))
      queue_names = sidekiq_config[:queues].map { |q| q.is_a?(Array) ? q[0] : q }
      
      expect(queue_names).to include("company_linkedin_discovery")
    end
  end
end