# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonImportResult do
  let(:import_result) { described_class.new }

  describe '#initialize' do
    it 'initializes with zero counts' do
      expect(import_result.imported_count).to eq(0)
      expect(import_result.failed_count).to eq(0)
      expect(import_result.duplicate_count).to eq(0)
      expect(import_result.updated_count).to eq(0)
      expect(import_result.imported_people).to eq([])
      expect(import_result.failed_people).to eq([])
      expect(import_result.duplicate_people).to eq([])
      expect(import_result.updated_people).to eq([])
      expect(import_result.csv_errors).to eq([])
    end

    it 'accepts import_tag parameter' do
      result = described_class.new(import_tag: 'test_import_123')
      expect(result.import_tag).to eq('test_import_123')
    end
  end

  describe '#add_imported_person' do
    let(:person) { build(:person, name: 'John Doe', email: 'john@example.com') }

    it 'adds person to imported list and increments count' do
      import_result.add_imported_person(person, 1)

      expect(import_result.imported_count).to eq(1)
      expect(import_result.imported_people.first[:name]).to eq('John Doe')
      expect(import_result.imported_people.first[:email]).to eq('john@example.com')
      expect(import_result.imported_people.first[:row]).to eq(1)
    end
  end

  describe '#add_updated_person' do
    let(:person) { build(:person, name: 'Jane Smith', email: 'jane@example.com') }
    let(:changes) { { title: [ 'Old Title', 'New Title' ] } }

    it 'adds person to updated list and increments count' do
      import_result.add_updated_person(person, 2, changes)

      expect(import_result.updated_count).to eq(1)
      expect(import_result.updated_people.first[:name]).to eq('Jane Smith')
      expect(import_result.updated_people.first[:changes]).to eq(changes)
      expect(import_result.updated_people.first[:row]).to eq(2)
    end
  end

  describe '#add_failed_person' do
    let(:person_data) { { name: 'Bad Data', email: 'invalid-email' } }
    let(:errors) { [ 'Email format is invalid' ] }

    it 'adds person to failed list and increments count' do
      import_result.add_failed_person(person_data, 3, errors)

      expect(import_result.failed_count).to eq(1)
      expect(import_result.failed_people.first[:name]).to eq('Bad Data')
      expect(import_result.failed_people.first[:errors]).to eq(errors)
      expect(import_result.failed_people.first[:row]).to eq(3)
    end

    it 'builds name from first and last name if name is blank' do
      person_data = { first_name: 'John', last_name: 'Doe', email: 'invalid' }
      import_result.add_failed_person(person_data, 4, errors)

      expect(import_result.failed_people.first[:name]).to eq('John Doe')
    end
  end

  describe '#add_duplicate_person' do
    let(:person_data) { { name: 'Duplicate', email: 'duplicate@example.com' } }

    it 'adds person to duplicate list and increments count' do
      import_result.add_duplicate_person(person_data, 5)

      expect(import_result.duplicate_count).to eq(1)
      expect(import_result.duplicate_people.first[:name]).to eq('Duplicate')
      expect(import_result.duplicate_people.first[:row]).to eq(5)
    end
  end

  describe '#success?' do
    it 'returns true when there are imports and no failures' do
      person = build(:person)
      import_result.add_imported_person(person, 1)

      expect(import_result.success?).to be true
    end

    it 'returns true when there are updates and no failures' do
      person = build(:person)
      import_result.add_updated_person(person, 1, {})

      expect(import_result.success?).to be true
    end

    it 'returns false when there are failures' do
      import_result.add_failed_person({}, 1, [ 'error' ])

      expect(import_result.success?).to be false
    end

    it 'returns false when there are CSV errors' do
      import_result.add_csv_error('CSV parsing error')

      expect(import_result.success?).to be false
    end

    it 'returns false when no people were processed' do
      expect(import_result.success?).to be false
    end
  end

  describe '#total_count' do
    it 'returns sum of all counts' do
      person = build(:person)
      import_result.add_imported_person(person, 1)
      import_result.add_updated_person(person, 2, {})
      import_result.add_failed_person({}, 3, [ 'error' ])
      import_result.add_duplicate_person({}, 4)

      expect(import_result.total_count).to eq(4)
    end
  end

  describe '#summary_message' do
    it 'returns CSV error message when there are CSV errors' do
      import_result.add_csv_error('Parse error')

      expect(import_result.summary_message).to eq('CSV parsing errors occurred')
    end

    it 'returns comprehensive summary for mixed results' do
      person = build(:person)
      import_result.add_imported_person(person, 1)
      import_result.add_updated_person(person, 2, {})
      import_result.add_failed_person({}, 3, [ 'error' ])
      import_result.add_duplicate_person({}, 4)

      expect(import_result.summary_message).to eq('1 imported, 1 updated, 1 failed, 1 skipped (duplicates)')
    end

    it 'returns no people message when nothing processed' do
      expect(import_result.summary_message).to eq('No people processed')
    end
  end

  describe '#finalize!' do
    it 'calculates processing time' do
      # Set start time in the past
      import_result.instance_variable_set(:@start_time, 2.seconds.ago)

      import_result.finalize!

      expect(import_result.processing_time).to be > 0
    end
  end

  describe '#people_per_second' do
    it 'calculates processing rate' do
      person = build(:person)
      import_result.add_imported_person(person, 1)
      import_result.add_imported_person(person, 2)

      # Mock processing time of 2 seconds
      import_result.instance_variable_set(:@processing_time, 2.0)

      expect(import_result.people_per_second).to eq(1.0)
    end

    it 'returns 0 when processing time is nil' do
      expect(import_result.people_per_second).to eq(0.0)
    end
  end
end
