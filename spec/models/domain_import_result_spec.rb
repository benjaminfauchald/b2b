# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DomainImportResult do
  let(:result) { described_class.new }

  describe 'initialization' do
    it 'initializes with default values' do
      expect(result.imported_count).to eq(0)
      expect(result.failed_count).to eq(0)
      expect(result.imported_domains).to eq([])
      expect(result.failed_domains).to eq([])
      expect(result.error_message).to be_nil
      expect(result.processing_time).to be_nil
      expect(result.csv_errors).to eq([])
    end

    it 'initializes with start time for processing measurement' do
      expect(result.instance_variable_get(:@start_time)).to be_a(Time)
    end
  end

  describe '#add_imported_domain' do
    it 'adds domain to imported list' do
      domain = create(:domain, domain: 'example.com')

      result.add_imported_domain(domain, 2)

      expect(result.imported_count).to eq(1)
      expect(result.imported_domains).to contain_exactly(
        hash_including(domain: 'example.com', row: 2)
      )
    end

    it 'increments imported count' do
      domain = create(:domain, domain: 'example.com')

      expect {
        result.add_imported_domain(domain, 2)
      }.to change(result, :imported_count).from(0).to(1)
    end
  end

  describe '#add_failed_domain' do
    it 'adds domain to failed list with errors' do
      errors = [ "Domain can't be blank", 'Domain is invalid' ]

      result.add_failed_domain('invalid.domain', 3, errors)

      expect(result.failed_count).to eq(1)
      expect(result.failed_domains).to contain_exactly(
        hash_including(
          domain: 'invalid.domain',
          row: 3,
          errors: errors
        )
      )
    end

    it 'increments failed count' do
      expect {
        result.add_failed_domain('invalid.domain', 3, [ 'Error' ])
      }.to change(result, :failed_count).from(0).to(1)
    end
  end

  describe '#add_csv_error' do
    it 'adds CSV parsing error' do
      result.add_csv_error('Invalid CSV format on line 5')

      expect(result.csv_errors).to include('Invalid CSV format on line 5')
    end
  end

  describe '#success?' do
    context 'when no domains failed and at least one imported' do
      it 'returns true' do
        domain = create(:domain)
        result.add_imported_domain(domain, 2)

        expect(result.success?).to be true
      end
    end

    context 'when some domains failed' do
      it 'returns false' do
        domain = create(:domain)
        result.add_imported_domain(domain, 2)
        result.add_failed_domain('invalid.domain', 3, [ 'Error' ])

        expect(result.success?).to be false
      end
    end

    context 'when no domains were processed' do
      it 'returns false' do
        expect(result.success?).to be false
      end
    end

    context 'when there are CSV errors' do
      it 'returns false' do
        result.add_csv_error('CSV parsing error')

        expect(result.success?).to be false
      end
    end
  end

  describe '#total_count' do
    it 'returns sum of imported and failed counts' do
      domain = create(:domain)
      result.add_imported_domain(domain, 2)
      result.add_failed_domain('invalid.domain', 3, [ 'Error' ])

      expect(result.total_count).to eq(2)
    end
  end

  describe '#has_csv_errors?' do
    context 'with CSV errors' do
      it 'returns true' do
        result.add_csv_error('Parsing error')

        expect(result.has_csv_errors?).to be true
      end
    end

    context 'without CSV errors' do
      it 'returns false' do
        expect(result.has_csv_errors?).to be false
      end
    end
  end

  describe '#finalize!' do
    it 'calculates processing time' do
      # Mock Time.current to simulate elapsed time
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 1.5)

      result = DomainImportResult.new
      result.finalize!

      expect(result.processing_time).to eq(1.5)
    end

    it 'rounds processing time to 2 decimal places' do
      sleep(0.01)

      result.finalize!

      expect(result.processing_time.to_s.split('.').last.length).to be <= 2
    end
  end

  describe '#set_error_message' do
    it 'sets the error message' do
      result.set_error_message('Something went wrong')

      expect(result.error_message).to eq('Something went wrong')
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      domain = create(:domain, domain: 'example.com')
      result.add_imported_domain(domain, 2)
      result.add_failed_domain('invalid.domain', 3, [ 'Error' ])
      result.set_error_message('Test error')
      result.finalize!

      hash = result.to_h

      expect(hash).to include(
        success: false,
        imported_count: 1,
        failed_count: 1,
        total_count: 2,
        imported_domains: array_including(
          hash_including(domain: 'example.com', row: 2)
        ),
        failed_domains: array_including(
          hash_including(domain: 'invalid.domain', row: 3, errors: [ 'Error' ])
        ),
        error_message: 'Test error',
        processing_time: be_a(Float),
        csv_errors: []
      )
    end
  end

  describe '#to_json' do
    it 'returns JSON representation' do
      domain = create(:domain, domain: 'example.com')
      result.add_imported_domain(domain, 2)
      result.finalize!

      json_string = result.to_json
      parsed = JSON.parse(json_string)

      expect(parsed).to include(
        'success' => true,
        'imported_count' => 1,
        'failed_count' => 0,
        'imported_domains' => array_including(
          hash_including('domain' => 'example.com', 'row' => 2)
        )
      )
    end
  end

  describe '#summary_message' do
    context 'with successful import' do
      it 'returns success message' do
        domain = create(:domain)
        result.add_imported_domain(domain, 2)

        expect(result.summary_message).to eq('1 imported')
      end
    end

    context 'with mixed results' do
      it 'returns mixed results message' do
        domain = create(:domain)
        result.add_imported_domain(domain, 2)
        result.add_failed_domain('invalid.domain', 3, [ 'Error' ])

        expect(result.summary_message).to eq('1 imported, 1 failed')
      end
    end

    context 'with all failures' do
      it 'returns failure message' do
        result.add_failed_domain('invalid.domain', 2, [ 'Error' ])

        expect(result.summary_message).to eq('1 failed')
      end
    end

    context 'with CSV errors' do
      it 'includes CSV error information' do
        result.add_csv_error('Parsing error')

        expect(result.summary_message).to include('CSV parsing errors')
      end
    end
  end

  describe '#domains_per_second' do
    it 'calculates processing rate' do
      # Set up time mock before creating the result
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 2.0)

      test_result = DomainImportResult.new
      domain1 = create(:domain)
      domain2 = create(:domain)
      test_result.add_imported_domain(domain1, 2)
      test_result.add_imported_domain(domain2, 3)
      test_result.finalize!

      expect(test_result.domains_per_second).to eq(1.0)
    end

    it 'handles zero processing time' do
      domain = create(:domain)
      result.add_imported_domain(domain, 2)
      allow(result).to receive(:processing_time).and_return(0.0)

      expect(result.domains_per_second).to eq(0.0)
    end
  end
end
