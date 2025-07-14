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

  describe '#truncate_url' do
    it 'returns empty string for blank URLs' do
      expect(helper.truncate_url(nil)).to eq('')
      expect(helper.truncate_url('')).to eq('')
    end

    it 'returns full URL when under max length' do
      short_url = 'https://example.com'
      expect(helper.truncate_url(short_url)).to eq(short_url)
    end

    it 'truncates long URLs keeping domain and partial path' do
      long_url = 'https://linkedin.com/sales/people/ACwAAEZya98BKfAe4xzkdmaSBA8VVvAgssLyK_4E'
      result = helper.truncate_url(long_url)
      expect(result).to eq('https://linkedin.com/sales/people/ACwAAEZya98BK...')
      expect(result.length).to be <= 50
    end

    it 'truncates very long domains' do
      very_long_domain = 'https://this-is-a-very-long-domain-name-that-exceeds-normal-limits.example.com'
      result = helper.truncate_url(very_long_domain)
      expect(result).to end_with('...')
      expect(result.length).to be <= 50
    end

    it 'handles custom max length' do
      url = 'https://linkedin.com/company/example-company'
      result = helper.truncate_url(url, 30)
      expect(result.length).to be <= 30
    end

    it 'handles URLs without paths' do
      url = 'https://example.com'
      result = helper.truncate_url(url, 25)
      expect(result).to eq('https://example.com')
    end

    it 'handles malformed URLs gracefully' do
      malformed_url = 'not-a-valid-url-but-very-long-string-that-should-be-truncated'
      result = helper.truncate_url(malformed_url)
      expect(result).to end_with('...')
      expect(result.length).to be <= 50
    end
  end

  describe '#truncate_linkedin_url' do
    it 'returns empty string for blank URLs' do
      expect(helper.truncate_linkedin_url(nil)).to eq('')
      expect(helper.truncate_linkedin_url('')).to eq('')
    end

    it 'returns full URL when under max length' do
      short_url = 'https://linkedin.com/in/john'
      expect(helper.truncate_linkedin_url(short_url)).to eq(short_url)
    end

    it 'shows clean format for LinkedIn personal profiles' do
      long_url = 'https://www.linkedin.com/in/ACwAAEZya98BKfAe4xzkdmaSBA8VVvAgssLyK_4E'
      result = helper.truncate_linkedin_url(long_url, 60)
      expect(result).to eq('linkedin.com/in/ACwAAEZya98BKfAe4xzkdmaSBA8VVvAgssLyK_4E')
    end

    it 'shows clean format for LinkedIn personal profiles when it fits' do
      short_url = 'https://www.linkedin.com/in/john-doe'
      result = helper.truncate_linkedin_url(short_url)
      expect(result).to eq('linkedin.com/in/john-doe')
    end

    it 'shows clean format for LinkedIn company profiles' do
      long_url = 'https://www.linkedin.com/company/microsoft'
      result = helper.truncate_linkedin_url(long_url)
      expect(result).to eq('linkedin.com/company/microsoft')
    end

    it 'handles Sales Navigator URLs' do
      sales_url = 'https://www.linkedin.com/sales/people/ACwAAEZya98BKfAe4xzkdmaSBA8VVvAgssLyK_4E'
      result = helper.truncate_linkedin_url(sales_url, 50)
      expect(result).to eq('linkedin.com/sales/people/ACwAAEZy...')
    end

    it 'falls back to regular truncation for non-LinkedIn URLs' do
      long_url = 'https://example.com/very/long/path/that/should/be/truncated'
      result = helper.truncate_linkedin_url(long_url)
      expect(result).to end_with('...')
      expect(result.length).to be <= 35
    end

    it 'handles custom max length' do
      url = 'https://linkedin.com/in/john-doe-very-long-name'
      result = helper.truncate_linkedin_url(url, 20)
      expect(result.length).to be <= 20
    end

    it 'handles malformed URLs gracefully' do
      malformed_url = 'not-a-valid-url-but-very-long-string-that-should-be-truncated'
      result = helper.truncate_linkedin_url(malformed_url)
      expect(result).to end_with('...')
      expect(result.length).to be <= 35
    end
  end
end
