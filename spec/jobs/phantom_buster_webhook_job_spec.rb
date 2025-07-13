require 'rails_helper'

RSpec.describe PhantomBusterWebhookJob, type: :job do
  let(:audit_log) do
    ServiceAuditLog.create!(
      service_name: 'phantom_buster_webhook',
      operation_type: 'process_webhook',
      status: :pending,
      table_name: 'phantom_buster_webhooks',
      record_id: SecureRandom.uuid,
      columns_affected: ['payload'],
      metadata: {}
    )
  end

  let(:container_id) { 'test-container-123' }

  describe '#perform' do
    context 'with finished status' do
      let(:webhook_payload) do
        {
          'containerId' => container_id,
          'status' => 'finished',
          'progress' => 100,
          'resultUrl' => 'https://phantombuster.s3.amazonaws.com/result.csv',
          'startedAt' => '2024-01-01T10:00:00Z',
          'finishedAt' => '2024-01-01T10:30:00Z',
          'duration' => 1800
        }
      end

      let(:phantom_audit_log) do
        ServiceAuditLog.create!(
          service_name: 'phantom_buster_profile_extraction',
          operation_type: 'extract_profiles',
          status: :pending,
          table_name: 'service_audit_logs',
          record_id: SecureRandom.uuid,
          columns_affected: ['status'],
          metadata: { 'phantom_container_id' => container_id }
        )
      end

      before do
        phantom_audit_log # Create the associated audit log
      end

      it 'processes job completion successfully' do
        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.not_to raise_error

        # Check that the audit log was updated
        reloaded_audit_log = audit_log.reload
        expect(reloaded_audit_log.status).to eq('success')
        expect(reloaded_audit_log.context['webhook_processed_at']).to be_present
        expect(reloaded_audit_log.context['final_status']).to eq('finished')
      end

      it 'updates the phantom job audit log' do
        described_class.new.perform(webhook_payload, audit_log.id)

        reloaded_phantom_log = phantom_audit_log.reload
        expect(reloaded_phantom_log.status).to eq('success')
        expect(reloaded_phantom_log.context['webhook_received_at']).to be_present
        expect(reloaded_phantom_log.context['result_url']).to eq('https://phantombuster.s3.amazonaws.com/result.csv')
        expect(reloaded_phantom_log.context['duration']).to eq(1800)
        expect(reloaded_phantom_log.context['finished_at']).to eq('2024-01-01T10:30:00Z')
      end

      it 'logs completion message' do
        expect(Rails.logger).to receive(:info).with("Processing PhantomBuster webhook: container_id=#{container_id}, status=finished")
        expect(Rails.logger).to receive(:info).with("PhantomBuster job completed: #{container_id}")

        described_class.new.perform(webhook_payload, audit_log.id)
      end

      context 'when phantom audit log is not found' do
        let(:webhook_payload) do
          {
            'containerId' => 'unknown-container',
            'status' => 'finished',
            'resultUrl' => 'https://phantombuster.s3.amazonaws.com/result.csv'
          }
        end

        it 'logs warning and continues processing' do
          expect(Rails.logger).to receive(:warn).with("Could not find audit log for container: unknown-container")

          expect {
            described_class.new.perform(webhook_payload, audit_log.id)
          }.not_to raise_error

          reloaded_audit_log = audit_log.reload
          expect(reloaded_audit_log.status).to eq('success')
        end
      end
    end

    context 'with error status' do
      let(:webhook_payload) do
        {
          'containerId' => container_id,
          'status' => 'error',
          'error' => 'PhantomBuster execution failed',
          'finishedAt' => '2024-01-01T10:15:00Z'
        }
      end

      let(:phantom_audit_log) do
        ServiceAuditLog.create!(
          service_name: 'phantom_buster_profile_extraction',
          operation_type: 'extract_profiles',
          status: :pending,
          table_name: 'service_audit_logs',
          record_id: SecureRandom.uuid,
          columns_affected: ['status'],
          metadata: { 'phantom_container_id' => container_id }
        )
      end

      before do
        phantom_audit_log # Create the associated audit log
      end

      it 'processes job error successfully' do
        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.not_to raise_error

        # Check that the audit log was updated
        reloaded_audit_log = audit_log.reload
        expect(reloaded_audit_log.status).to eq('success')
        expect(reloaded_audit_log.context['final_status']).to eq('error')
      end

      it 'updates the phantom job audit log with error' do
        described_class.new.perform(webhook_payload, audit_log.id)

        reloaded_phantom_log = phantom_audit_log.reload
        expect(reloaded_phantom_log.status).to eq('failed')
        expect(reloaded_phantom_log.error_message).to eq('PhantomBuster execution failed')
        expect(reloaded_phantom_log.context['phantom_error']).to eq('PhantomBuster execution failed')
        expect(reloaded_phantom_log.context['finished_at']).to eq('2024-01-01T10:15:00Z')
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:error).with("PhantomBuster job failed: #{container_id} - PhantomBuster execution failed")

        described_class.new.perform(webhook_payload, audit_log.id)
      end
    end

    context 'with running status' do
      let(:webhook_payload) do
        {
          'containerId' => container_id,
          'status' => 'running',
          'progress' => 50
        }
      end

      let(:phantom_audit_log) do
        ServiceAuditLog.create!(
          service_name: 'phantom_buster_profile_extraction',
          operation_type: 'extract_profiles',
          status: :pending,
          table_name: 'service_audit_logs',
          record_id: SecureRandom.uuid,
          columns_affected: ['status'],
          metadata: { 'phantom_container_id' => container_id }
        )
      end

      before do
        phantom_audit_log # Create the associated audit log
      end

      it 'processes progress update successfully' do
        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.not_to raise_error

        # Check that the audit log was updated
        reloaded_audit_log = audit_log.reload
        expect(reloaded_audit_log.status).to eq('success')
        expect(reloaded_audit_log.context['final_status']).to eq('running')
      end

      it 'updates the phantom job audit log with progress' do
        described_class.new.perform(webhook_payload, audit_log.id)

        reloaded_phantom_log = phantom_audit_log.reload
        expect(reloaded_phantom_log.context['progress']).to eq(50)
        expect(reloaded_phantom_log.context['last_progress_update']).to be_present
      end

      it 'logs progress update' do
        expect(Rails.logger).to receive(:info).with("PhantomBuster progress update: #{container_id} - 50%")

        described_class.new.perform(webhook_payload, audit_log.id)
      end
    end

    context 'when processing fails' do
      let(:webhook_payload) do
        {
          'containerId' => container_id,
          'status' => 'finished'
        }
      end

      before do
        # Mock a failure in the processing
        allow_any_instance_of(described_class).to receive(:handle_job_completion).and_raise(StandardError, 'Processing failed')
      end

      it 'updates audit log with error and re-raises' do
        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.to raise_error(StandardError, 'Processing failed')

        reloaded_audit_log = audit_log.reload
        expect(reloaded_audit_log.status).to eq('failed')
        expect(reloaded_audit_log.error_message).to eq('Processing failed')
      end

      it 'logs error details' do
        expect(Rails.logger).to receive(:error).with('Failed to process PhantomBuster webhook: Processing failed')
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.to raise_error(StandardError)
      end
    end

    context 'with unknown status' do
      let(:webhook_payload) do
        {
          'containerId' => container_id,
          'status' => 'unknown_status'
        }
      end

      it 'logs warning and processes successfully' do
        expect(Rails.logger).to receive(:warn).with('Unknown PhantomBuster status: unknown_status')

        expect {
          described_class.new.perform(webhook_payload, audit_log.id)
        }.not_to raise_error

        reloaded_audit_log = audit_log.reload
        expect(reloaded_audit_log.status).to eq('success')
        expect(reloaded_audit_log.context['final_status']).to eq('unknown_status')
      end
    end
  end

  describe 'job configuration' do
    it 'is queued on phantom_webhooks queue' do
      expect(described_class.queue_name).to eq('phantom_webhooks')
    end

    it 'has retry configuration' do
      expect(described_class.retry_on_exception_filter).to be_present
    end
  end
end