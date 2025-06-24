require 'rails_helper'

RSpec.describe CompaniesController, type: :controller do
  let(:user) { create(:user) }
  let(:admin_user) { create(:user, role: 'admin') }
  let(:company) { create(:company) }

  before do
    sign_in user
  end

  describe 'enhancement service actions' do
    describe 'POST #queue_financial_data' do
      context 'when service is active' do
        before do
          create(:service_configuration, 
            service_name: 'company_financial_data',
            active: true
          )
        end

        it 'queues eligible companies for financial data processing' do
          companies = create_list(:company, 5)
          allow(Company).to receive(:needs_service).with('company_financial_data').and_return(Company.where(id: companies.map(&:id)))

          expect {
            post :queue_financial_data, params: { count: 5 }
          }.to change { CompanyFinancialDataWorker.jobs.size }.by(5)

          expect(response).to have_http_status(:success)
          json = JSON.parse(response.body)
          expect(json['success']).to be true
          expect(json['queued_count']).to eq(5)
        end

        it 'respects count parameter' do
          create_list(:company, 10)
          
          post :queue_financial_data, params: { count: 3 }
          
          json = JSON.parse(response.body)
          expect(json['queued_count']).to eq(3)
        end

        it 'returns queue statistics' do
          post :queue_financial_data, params: { count: 1 }
          
          json = JSON.parse(response.body)
          expect(json).to have_key('queue_stats')
          expect(json['queue_stats']).to have_key('company_financial_data')
        end

        it 'requires authentication' do
          sign_out user
          
          post :queue_financial_data
          
          expect(response).to redirect_to(new_user_session_path)
        end
      end

      context 'when service is inactive' do
        before do
          create(:service_configuration, 
            service_name: 'company_financial_data',
            active: false
          )
        end

        it 'returns error message' do
          post :queue_financial_data
          
          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['success']).to be false
          expect(json['message']).to include('Financial data service is disabled')
        end
      end
    end

    describe 'POST #queue_single_financial_data' do
      before do
        create(:service_configuration, 
          service_name: 'company_financial_data',
          active: true
        )
      end

      it 'queues individual company for processing' do
        expect {
          post :queue_single_financial_data, params: { id: company.id }
        }.to change { CompanyFinancialDataWorker.jobs.size }.by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['company_id']).to eq(company.id)
      end

      it 'creates audit log for manual queue action' do
        expect {
          post :queue_single_financial_data, params: { id: company.id }
        }.to change { ServiceAuditLog.count }.by(1)

        audit_log = ServiceAuditLog.last
        expect(audit_log.auditable).to eq(company)
        expect(audit_log.service_name).to eq('company_financial_data')
        expect(audit_log.operation_type).to eq('queue_individual')
        expect(audit_log.metadata['action']).to eq('manual_queue')
      end

      it 'returns job details' do
        post :queue_single_financial_data, params: { id: company.id }
        
        json = JSON.parse(response.body)
        expect(json).to have_key('job_id')
        expect(json).to have_key('worker')
        expect(json['worker']).to eq('CompanyFinancialDataWorker')
      end

      it 'handles non-existent company' do
        post :queue_single_financial_data, params: { id: 999999 }
        
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    describe 'POST #queue_web_discovery' do
      before do
        create(:service_configuration, 
          service_name: 'company_web_discovery',
          active: true
        )
      end

      it 'queues companies for web discovery' do
        companies = create_list(:company, 3)
        
        expect {
          post :queue_web_discovery, params: { count: 3 }
        }.to change { CompanyWebDiscoveryWorker.jobs.size }.by(3)

        expect(response).to have_http_status(:success)
      end
    end

    describe 'POST #queue_linkedin_discovery' do
      before do
        create(:service_configuration, 
          service_name: 'company_linkedin_discovery',
          active: true
        )
      end

      it 'queues companies for LinkedIn discovery' do
        companies = create_list(:company, 2, linkedin_processed: false)
        
        expect {
          post :queue_linkedin_discovery, params: { count: 2 }
        }.to change { CompanyLinkedinDiscoveryWorker.jobs.size }.by(2)

        expect(response).to have_http_status(:success)
      end
    end

    describe 'POST #queue_employee_discovery' do
      before do
        create(:service_configuration, 
          service_name: 'company_employee_discovery',
          active: true
        )
      end

      it 'queues companies for employee discovery' do
        companies = create_list(:company, 4)
        
        expect {
          post :queue_employee_discovery, params: { count: 4 }
        }.to change { CompanyEmployeeDiscoveryWorker.jobs.size }.by(4)

        expect(response).to have_http_status(:success)
      end
    end

    describe 'GET #enhancement_queue_status' do
      it 'returns queue statistics for all services' do
        get :enhancement_queue_status
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['queue_stats']).to have_key('company_financial_data')
        expect(json['queue_stats']).to have_key('company_web_discovery')
        expect(json['queue_stats']).to have_key('company_linkedin_discovery')
        expect(json['queue_stats']).to have_key('company_employee_discovery')
      end

      it 'includes service configurations' do
        create(:service_configuration, service_name: 'company_financial_data', active: true)
        create(:service_configuration, service_name: 'company_web_discovery', active: false)
        
        get :enhancement_queue_status
        
        json = JSON.parse(response.body)
        expect(json['service_configs']['company_financial_data']['active']).to be true
        expect(json['service_configs']['company_web_discovery']['active']).to be false
      end
    end

    describe 'authorization' do
      context 'for bulk queue actions' do
        it 'allows regular users to queue companies' do
          create(:service_configuration, service_name: 'company_financial_data', active: true)
          
          post :queue_financial_data, params: { count: 1 }
          
          expect(response).to have_http_status(:success)
        end
      end

      context 'for admin actions' do
        before do
          sign_out user
          sign_in admin_user
        end

        it 'allows admins to access queue statistics' do
          get :enhancement_queue_status
          
          expect(response).to have_http_status(:success)
        end
      end
    end
  end

  describe 'index page enhancements' do
    it 'includes enhancement dashboard data' do
      companies = create_list(:company, 3)
      
      get :index
      
      expect(assigns(:companies)).to be_present
      expect(assigns(:enhancement_stats)).to be_present
      expect(response).to render_template('index')
    end
  end

  describe 'show page enhancements' do
    it 'includes service status for individual company' do
      get :show, params: { id: company.id }
      
      expect(assigns(:company)).to eq(company)
      expect(assigns(:service_statuses)).to be_present
      expect(response).to render_template('show')
    end
  end
end