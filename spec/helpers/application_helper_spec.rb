require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#url_safe?' do
    it 'returns true for valid http URLs' do
      expect(helper.url_safe?('http://example.com')).to be true
    end

    it 'returns true for valid https URLs' do
      expect(helper.url_safe?('https://example.com')).to be true
    end

    it 'returns true for valid mailto URLs' do
      expect(helper.url_safe?('mailto:test@example.com')).to be true
    end

    it 'returns false for javascript URLs' do
      expect(helper.url_safe?('javascript:alert("xss")')).to be false
    end

    it 'returns false for data URLs' do
      expect(helper.url_safe?('data:text/html,<script>alert("xss")</script>')).to be false
    end

    it 'returns false for vbscript URLs' do
      expect(helper.url_safe?('vbscript:alert("xss")')).to be false
    end

    it 'returns false for malformed URLs' do
      expect(helper.url_safe?('not-a-url')).to be false
    end

    it 'returns false for blank URLs' do
      expect(helper.url_safe?(nil)).to be false
      expect(helper.url_safe?('')).to be false
      expect(helper.url_safe?('   ')).to be false
    end

    it 'returns false for URLs with other protocols' do
      expect(helper.url_safe?('ftp://example.com')).to be false
      expect(helper.url_safe?('file:///etc/passwd')).to be false
    end

    it 'handles case-insensitive protocol checks' do
      expect(helper.url_safe?('JAVASCRIPT:alert("xss")')).to be false
      expect(helper.url_safe?('HTTPS://example.com')).to be true
    end

    it 'handles whitespace in malicious URLs' do
      expect(helper.url_safe?('  javascript:alert("xss")  ')).to be false
    end
  end

  describe '#safe_external_link' do
    it 'creates safe links for valid URLs' do
      result = helper.safe_external_link('https://example.com', 'Example')
      expect(result).to include('href="https://example.com"')
      expect(result).to include('target="_blank"')
      expect(result).to include('rel="noopener"')
    end

    it 'returns empty string for invalid URLs' do
      expect(helper.safe_external_link('javascript:alert("xss")')).to eq('')
    end

    it 'adds https:// prefix to URLs without protocol' do
      result = helper.safe_external_link('example.com')
      expect(result).to include('href="https://example.com"')
    end
  end
end