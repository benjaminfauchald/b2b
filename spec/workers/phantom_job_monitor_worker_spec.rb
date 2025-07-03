# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhantomJobMonitorWorker, type: :worker do
  describe '#perform' do
    let(:company) { create(:company, company_name: 'Test Company') }

    context 'when there are stuck phantom jobs' do
      let!(:stuck_job) do
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'person_profile_extraction_async',
          operation_type: 'extract',
          status: 'pending',
          table_name: 'companies',
          record_id: company.id.to_s,
          started_at: 15.minutes.ago,
          columns_affected: [ 'profiles' ],
          metadata: {
            'container_id' => 'test-container-123',
            'phantom_id' => 'phantom-456',
            'status' => 'phantom_launched'
          }
        )
      end

      let!(:recent_job) do
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'person_profile_extraction_async',
          operation_type: 'extract',
          status: 'pending',
          table_name: 'companies',
          record_id: company.id.to_s,
          started_at: 5.minutes.ago,
          columns_affected: [ 'profiles' ],
          metadata: {
            'container_id' => 'test-container-789',
            'phantom_id' => 'phantom-456',
            'status' => 'phantom_launched'
          }
        )
      end

      let!(:completed_job) do
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'person_profile_extraction_async',
          operation_type: 'extract',
          status: 'success',
          table_name: 'companies',
          record_id: company.id.to_s,
          started_at: 20.minutes.ago,
          completed_at: 15.minutes.ago,
          columns_affected: [ 'profiles' ],
          metadata: { 'status' => 'completed' }
        )
      end

      it 'times out stuck jobs older than 10 minutes' do
        expect { subject.perform }.to change { stuck_job.reload.status }.from('pending').to('failed')
      end

      it 'does not timeout recent jobs' do
        expect { subject.perform }.not_to change { recent_job.reload.status }
      end

      it 'does not affect completed jobs' do
        expect { subject.perform }.not_to change { completed_job.reload.status }
      end

      it 'sets appropriate error message' do
        subject.perform
        stuck_job.reload
        expect(stuck_job.error_message).to eq('PhantomBuster job timed out after 10 minutes')
      end

      it 'updates metadata with timeout information' do
        subject.perform
        stuck_job.reload
        expect(stuck_job.metadata['error']).to eq('PhantomBuster job timed out after 10 minutes')
        expect(stuck_job.metadata['timeout_reason']).to eq('No status updates received within timeout period')
        expect(stuck_job.metadata['monitor_timeout']).to be true
        expect(stuck_job.metadata['timeout_at']).to be_present
      end

      it 'sets completed_at timestamp' do
        subject.perform
        stuck_job.reload
        expect(stuck_job.completed_at).to be_present
        expect(stuck_job.completed_at).to be > stuck_job.started_at
      end

      it 'calculates execution time' do
        subject.perform
        stuck_job.reload
        expect(stuck_job.execution_time_ms).to be > 0
      end
    end

    context 'when there are no stuck jobs' do
      it 'completes without errors' do
        expect { subject.perform }.not_to raise_error
      end
    end

    context 'when timeout operation fails' do
      let!(:stuck_job) do
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'person_profile_extraction_async',
          operation_type: 'extract',
          status: 'pending',
          table_name: 'companies',
          record_id: company.id.to_s,
          started_at: 15.minutes.ago,
          columns_affected: [ 'profiles' ],
        metadata: { 'container_id' => 'test-container-123' }
        )
      end

      before do
        allow_any_instance_of(ServiceAuditLog).to receive(:update!).and_raise(StandardError, 'Update failed')
      end

      it 'logs the error and continues' do
        expect(Rails.logger).to receive(:error).with(/Error timing out job/)
        expect { subject.perform }.not_to raise_error
      end
    end

    context 'with jobs missing container_id' do
      let!(:job_without_container) do
        ServiceAuditLog.create!(
          auditable: company,
          service_name: 'person_profile_extraction_async',
          operation_type: 'extract',
          status: 'pending',
          table_name: 'companies',
          record_id: company.id.to_s,
          started_at: 15.minutes.ago,
          columns_affected: [ 'profiles' ],
          metadata: {
            'status' => 'initializing',
            'error' => 'Failed to launch phantom'
          }
        )
      end

      it 'still times out the job' do
        expect { subject.perform }.to change { job_without_container.reload.status }.from('pending').to('failed')
      end

      it 'logs that container_id is missing' do
        expect(Rails.logger).to receive(:error).with(/Container: $/)
        subject.perform
      end
    end
  end
end
