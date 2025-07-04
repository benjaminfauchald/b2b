require 'rails_helper'

RSpec.describe Person, type: :model do
  describe 'scopes' do
    describe '.imported_with_tag' do
      let!(:person1) { create(:person, import_tag: 'import_test_20241201_120000') }
      let!(:person2) { create(:person, import_tag: 'import_test_20241201_120000') }
      let!(:person3) { create(:person, import_tag: 'import_other_20241201_130000') }
      let!(:person4) { create(:person, import_tag: nil) }

      it 'returns people with the specified import tag' do
        result = Person.imported_with_tag('import_test_20241201_120000')
        expect(result).to contain_exactly(person1, person2)
      end

      it 'returns empty when no people have the tag' do
        result = Person.imported_with_tag('nonexistent_tag')
        expect(result).to be_empty
      end
    end
  end
end
