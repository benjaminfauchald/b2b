require 'rails_helper'

RSpec.describe EmailVerificationStatusComponent, type: :component do
  let(:person) { create(:person, email: 'test@example.com') }
  let(:component) { described_class.new(person: person) }

  describe 'ZeroBounce functionality' do
    describe '#has_zerobounce_data?' do
      it 'returns true when person has zerobounce data' do
        person.update!(zerobounce_status: 'valid')
        expect(component.has_zerobounce_data?).to be true
      end

      it 'returns false when person has no zerobounce data' do
        person.update!(zerobounce_status: nil)
        expect(component.has_zerobounce_data?).to be false
      end
    end

    describe '#zerobounce_status_text' do
      it 'returns correct text for valid status' do
        person.update!(zerobounce_status: 'valid')
        expect(component.zerobounce_status_text).to eq('Valid')
      end

      it 'returns correct text for invalid status' do
        person.update!(zerobounce_status: 'invalid')
        expect(component.zerobounce_status_text).to eq('Invalid')
      end

      it 'returns correct text for catch-all status' do
        person.update!(zerobounce_status: 'catch-all')
        expect(component.zerobounce_status_text).to eq('Catch-All')
      end

      it 'returns correct text for do_not_mail status' do
        person.update!(zerobounce_status: 'do_not_mail')
        expect(component.zerobounce_status_text).to eq('Do Not Mail')
      end

      it 'returns humanized text for unknown status' do
        person.update!(zerobounce_status: 'some_unknown_status')
        expect(component.zerobounce_status_text).to eq('Some unknown status')
      end

      it 'returns N/A for nil status' do
        person.update!(zerobounce_status: nil)
        expect(component.zerobounce_status_text).to eq('N/A')
      end
    end

    describe '#zerobounce_status_color_classes' do
      it 'returns green classes for valid status' do
        person.update!(zerobounce_status: 'valid')
        expect(component.zerobounce_status_color_classes).to include('bg-green-100', 'text-green-800')
      end

      it 'returns red classes for invalid status' do
        person.update!(zerobounce_status: 'invalid')
        expect(component.zerobounce_status_color_classes).to include('bg-red-100', 'text-red-800')
      end

      it 'returns red classes for do_not_mail status' do
        person.update!(zerobounce_status: 'do_not_mail')
        expect(component.zerobounce_status_color_classes).to include('bg-red-100', 'text-red-800')
      end

      it 'returns yellow classes for catch-all status' do
        person.update!(zerobounce_status: 'catch-all')
        expect(component.zerobounce_status_color_classes).to include('bg-yellow-100', 'text-yellow-800')
      end

      it 'returns gray classes for unknown status' do
        person.update!(zerobounce_status: 'unknown_status')
        expect(component.zerobounce_status_color_classes).to include('bg-gray-100', 'text-gray-800')
      end
    end

    describe '#zerobounce_confidence_normalized' do
      it 'converts ZeroBounce 10-point scale to 0-1 scale' do
        person.update!(zerobounce_quality_score: 8.5)
        expect(component.zerobounce_confidence_normalized).to eq(0.85)
      end

      it 'returns nil when quality score is nil' do
        person.update!(zerobounce_quality_score: nil)
        expect(component.zerobounce_confidence_normalized).to be_nil
      end
    end

    describe '#zerobounce_confidence_percentage' do
      it 'converts normalized confidence to percentage' do
        person.update!(zerobounce_quality_score: 7.3)
        expect(component.zerobounce_confidence_percentage).to eq(73)
      end

      it 'returns nil when quality score is nil' do
        person.update!(zerobounce_quality_score: nil)
        expect(component.zerobounce_confidence_percentage).to be_nil
      end
    end

    describe '#systems_agree?' do
      it 'returns true when systems agree' do
        person.update!(
          email_verification_status: 'valid',
          zerobounce_status: 'valid'
        )
        expect(component.systems_agree?).to be true
      end

      it 'returns false when systems disagree' do
        person.update!(
          email_verification_status: 'valid',
          zerobounce_status: 'invalid'
        )
        expect(component.systems_agree?).to be false
      end
    end

    describe '#agreement_icon_classes' do
      it 'returns green classes when systems agree' do
        person.update!(
          email_verification_status: 'valid',
          zerobounce_status: 'valid'
        )
        expect(component.agreement_icon_classes).to include('text-green-600')
      end

      it 'returns red classes when systems disagree' do
        person.update!(
          email_verification_status: 'valid',
          zerobounce_status: 'invalid'
        )
        expect(component.agreement_icon_classes).to include('text-red-600')
      end
    end

    describe '#zerobounce_imported_text' do
      it 'returns "Imported today" for today' do
        person.update!(zerobounce_imported_at: Time.current)
        expect(component.zerobounce_imported_text).to eq('Imported today')
      end

      it 'returns "Imported yesterday" for yesterday' do
        person.update!(zerobounce_imported_at: 1.day.ago)
        expect(component.zerobounce_imported_text).to eq('Imported yesterday')
      end

      it 'returns days ago for older imports' do
        person.update!(zerobounce_imported_at: 5.days.ago)
        expect(component.zerobounce_imported_text).to eq('Imported 5 days ago')
      end

      it 'returns nil when zerobounce_imported_at is nil' do
        person.update!(zerobounce_imported_at: nil)
        expect(component.zerobounce_imported_text).to be_nil
      end
    end
  end

  describe 'rendering with ZeroBounce data' do
    before do
      person.update!(
        email_verification_status: 'valid',
        email_verification_confidence: 0.8,
        email_verification_checked_at: Time.current,
        zerobounce_status: 'valid',
        zerobounce_quality_score: 8.5,
        zerobounce_imported_at: Time.current,
        zerobounce_free_email: true,
        zerobounce_mx_found: true,
        zerobounce_smtp_provider: 'Gmail',
        zerobounce_did_you_mean: 'corrected@example.com'
      )
    end

    it 'renders the component successfully' do
      expect { render_inline(component) }.not_to raise_error
    end

    it 'includes ZeroBounce comparison section' do
      render_inline(component)
      
      expect(page).to have_text('ZeroBounce Comparison')
      expect(page).to have_text('Our System')
      expect(page).to have_text('ZeroBounce')
    end

    it 'shows agreement status' do
      render_inline(component)
      
      expect(page).to have_text('Agree')
    end

    it 'shows ZeroBounce features' do
      render_inline(component)
      
      expect(page).to have_text('Free Email')
      expect(page).to have_text('MX Found')
      expect(page).to have_text('Gmail')
    end

    it 'shows typo suggestion' do
      render_inline(component)
      
      expect(page).to have_text('Suggested correction')
      expect(page).to have_text('corrected@example.com')
    end
  end

  describe 'rendering without ZeroBounce data' do
    before do
      person.update!(
        email_verification_status: 'valid',
        email_verification_confidence: 0.8,
        email_verification_checked_at: Time.current
      )
    end

    it 'renders without ZeroBounce comparison section' do
      render_inline(component)
      
      expect(page).not_to have_text('ZeroBounce Comparison')
      expect(page).to have_text('Valid')  # Our system status should still show
    end
  end

  describe 'rendering disagreement' do
    before do
      person.update!(
        email_verification_status: 'valid',
        email_verification_confidence: 0.8,
        zerobounce_status: 'invalid',
        zerobounce_quality_score: 2.1,
        zerobounce_imported_at: Time.current
      )
    end

    it 'shows disagreement status' do
      render_inline(component)
      
      expect(page).to have_text('Disagree')
    end
  end

  describe '#render?' do
    it 'returns true when person has email' do
      person.update!(email: 'test@example.com')
      expect(component.render?).to be true
    end

    it 'returns false when person has no email' do
      person.update!(email: nil)
      expect(component.render?).to be false
    end

    it 'returns false when person has empty email' do
      person.update!(email: '')
      expect(component.render?).to be false
    end
  end
end