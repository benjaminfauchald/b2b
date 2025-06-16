# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompanyFinancialsUpdater do
  let(:company) { create(:company, registration_number: '123456789') }
  let(:service) { described_class.new(company) }
  let(:api_url) { "https://data.brreg.no/regnskapsregisteret/regnskap/#{company.registration_number}" }
  let(:success_response) do
    {
      "regnskapsførerNavn" => "Ola Nordmann",
      "regnskapsførerAdresse" => "Testveien 1, 1234 Oslo",
      "regnskapsførerTelefon" => "12345678",
      "regnskapsførerEpost" => "ola@example.com",
      "regnskapsførertype" => {
        "kode" => "REVISJON",
        "beskrivelse" => "Revisjon"
      },
      "reguleringsresultat" => 500_000,
      "aarsresultat" => 1_000_000,
      "driftsinntekter" => 10_000_000,
      "driftskostnader" => 9_000_000
    }.to_json
  end
  
  describe '#call' do
    context 'when the API request is successful' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' })
      end
      
      it 'updates the company with financial data' do
        expect { service.call }
          .to change { company.reload.ordinary_result }.to(500_000)
          .and change { company.annual_result }.to(1_000_000)
          .and change { company.operating_revenue }.to(10_000_000)
          .and change { company.operating_costs }.to(9_000_000)
      end
    end
    
    context 'when the API returns a rate limit error' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 429, headers: { 'Retry-After' => '10' })
      end
      
      it 'raises a RateLimitError with retry_after' do
        expect { service.call }.to raise_error(described_class::RateLimitError) do |error|
          expect(error.retry_after).to eq(10)
        end
      end
    end
    
    context 'when the API returns an error' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 500, body: 'Internal Server Error')
      end
      
      it 'raises an ApiError' do
        expect { service.call }.to raise_error(described_class::ApiError)
      end
    end
    
    context 'when the API returns invalid JSON' do
      before do
        stub_request(:get, api_url)
          .to_return(status: 200, body: 'invalid json')
      end
      
      it 'raises an InvalidResponseError' do
        expect { service.call }.to raise_error(described_class::InvalidResponseError)
      end
    end
    
    context 'when the company has no registration number' do
      let(:company) { build(:company, registration_number: nil) }
      
      it 'does not make an API request' do
        expect(HTTParty).not_to receive(:get)
        service.call
      end
    end
  end
  
  describe 'retry logic' do
    before do
      # First request fails with 429, second succeeds
      stub_request(:get, api_url)
        .to_return(
          { status: 429, headers: { 'Retry-After' => '1' } },
          { status: 200, body: success_response, headers: { 'Content-Type' => 'application/json' } }
        )
    end
    
    it 'retries on rate limit' do
      service.call
    end
  end
end
